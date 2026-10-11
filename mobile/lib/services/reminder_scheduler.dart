import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/task.dart';
import 'notification_plan.dart';
import '../l10n/app_strings.dart';

class ReminderScheduler {
  static const testNotificationId = 100000;
  // Foundation can return GMT rather than an IANA region on iOS simulators
  // and devices configured to a zero-offset time zone.
  static tz.Location resolveTimeZone(String identifier) =>
      identifier == 'GMT' || identifier == 'UTC'
      ? tz.UTC
      : tz.getLocation(identifier);
  final plugin = FlutterLocalNotificationsPlugin();
  Future<void> Function(String id, String action)? onAction;
  NotificationPlan? lastPlan;
  DateTime? accessUntil;
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(resolveTimeZone(zone.identifier));
    await plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              'task',
              actions: [
                DarwinNotificationAction.plain(
                  'start',
                  AppStrings.current.t('지금 시작'),
                  options: {DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(
                  'snooze',
                  AppStrings.current.t('10분 미루기'),
                  options: {DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(
                  'complete',
                  AppStrings.current.t('완료했어요'),
                  options: {DarwinNotificationActionOption.foreground},
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: respond,
    );
  }

  Future<void> respond(NotificationResponse response) async {
    final id = response.payload;
    if (id != null) {
      final action = response.actionId;
      await onAction?.call(
        id,
        action == null || action.isEmpty ? 'open' : action,
      );
    }
  }

  Future<void> handleLaunch() async {
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      await respond(launch!.notificationResponse!);
    }
  }

  Future<void> requestPermissions() async {
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> requestExactPermission() async {
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
  }

  Future<void> openSettings() async {
    await plugin.openAppNotificationSettings();
  }

  Future<AndroidScheduleMode> mode() async {
    final exact = await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.canScheduleExactNotifications();
    return exact == true
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  NotificationDetails details({String? payload}) => NotificationDetails(
    android: AndroidNotificationDetails(
      'tasks_v1',
      AppStrings.current.t('할 일 알림'),
      // The Android plugin exposes the tag, but not payload, when reading
      // delivered notifications. Keep the occurrence identity on the banner.
      tag: payload,
      channelDescription: AppStrings.current.t('예정된 할 일과 미완료 재알림'),
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(
          'start',
          AppStrings.current.t('지금 시작'),
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'snooze',
          AppStrings.current.t('10분 미루기'),
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'complete',
          AppStrings.current.t('완료했어요'),
          showsUserInterface: true,
        ),
      ],
    ),
    iOS: const DarwinNotificationDetails(
      categoryIdentifier: 'task',
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    ),
  );
  Future<bool?> enabled() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
    }
    return (await plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions())
        ?.isEnabled;
  }

  static int notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  Future<void> sync(
    List<Occurrence> items, {
    Map<String, List<DateTime>> exceptions = const {},
  }) async {
    if (accessUntil != null && !accessUntil!.isAfter(DateTime.now())) {
      await plugin.cancelAll();
      lastPlan = NotificationPlan([], 0, null);
      return;
    }
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(resolveTimeZone(zone.identifier));
    final now = DateTime.now(), scheduleMode = await mode();
    lastPlan = NotificationPlan.build(
      items,
      now: now,
      capacity: defaultTargetPlatform == TargetPlatform.android ? 400 : 60,
      exceptions: exceptions,
      until: accessUntil,
    );
    // Deleted and completed reminders disappear, while active alerts survive refill.
    final activePayloads = <int, String>{};
    for (final notification in await plugin.getActiveNotifications()) {
      // The current Android plugin omits payload from delivered notifications.
      // Do not infer an old untagged banner from a hash or pending request: that
      // ID may have since been reused by another task. New banners carry a tag.
      final payload = notification.payload ?? notification.tag;
      if (payload == null || notification.id == null) continue;
      final occurrence = resolveReminderPayload(items, payload, now);
      if (occurrence == null || !occurrence.active) {
        await plugin.cancel(id: notification.id!, tag: notification.tag);
      } else {
        activePayloads[notification.id!] = payload;
      }
    }
    // Cancel delivered alerts by their real platform ID and payload above. A
    // recomputed hash alone could belong to another task after collision handling.
    await plugin.cancelAllPendingNotifications();
    final ids = <int>{testNotificationId};
    final jobsPerPayload = <String, int>{};
    for (final job in lastPlan!.jobs) {
      jobsPerPayload.update(
        job.payload,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    for (final job in lastPlan!.jobs) {
      var id = notificationId(job.key);
      if (jobsPerPayload[job.payload] == 1) {
        // Keep a delivered collision-adjusted ID after another task is removed.
        // Multiple dated follow-ups share a payload but need distinct job IDs.
        final existing =
            activePayloads.entries
                .where((entry) => entry.value == job.payload)
                .map((entry) => entry.key)
                .toList()
              ..sort();
        if (existing.isNotEmpty && !existing.contains(id)) id = existing.first;
      }
      while (ids.contains(id) ||
          (activePayloads.containsKey(id) &&
              activePayloads[id] != job.payload)) {
        id = id == 0x7fffffff ? 1 : id + 1;
      }
      ids.add(id);
      await plugin.zonedSchedule(
        id: id,
        title: job.title,
        body: job.body,
        scheduledDate: tz.TZDateTime(
          tz.local,
          job.at.year,
          job.at.month,
          job.at.day,
          job.at.hour,
          job.at.minute,
          job.at.second,
        ),
        notificationDetails: details(payload: job.payload),
        androidScheduleMode: scheduleMode,
        payload: job.payload,
        matchDateTimeComponents: switch (job.repeat) {
          NotificationRepeat.daily => DateTimeComponents.time,
          NotificationRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
          NotificationRepeat.monthly => DateTimeComponents.dayOfMonthAndTime,
          null => null,
        },
      );
    }
  }

  Future<void> testNotification() async {
    if (accessUntil != null &&
        !DateTime.now()
            .add(const Duration(seconds: 10))
            .isBefore(accessUntil!)) {
      return;
    }
    await requestPermissions();
    await plugin.zonedSchedule(
      id: testNotificationId,
      title: AppStrings.current.t('투두닉 테스트'),
      body: AppStrings.current.t('앱 밖에서도 알림이 도착하는지 확인해주세요.'),
      scheduledDate: tz.TZDateTime.now(tz.local)
          .add(const Duration(seconds: 10)),
      notificationDetails: details(),
      androidScheduleMode: await mode(),
    );
  }
}
