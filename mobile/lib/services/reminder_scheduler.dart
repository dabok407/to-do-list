import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/task.dart';
import 'notification_plan.dart';

class ReminderScheduler {
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
                  '지금 시작',
                  options: {DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(
                  'snooze',
                  '10분 미루기',
                  options: {DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(
                  'complete',
                  '완료했어요',
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

  NotificationDetails details() => const NotificationDetails(
    android: AndroidNotificationDetails(
      'tasks_v1',
      '할 일 알림',
      channelDescription: '예정된 할 일과 미완료 재알림',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction('start', '지금 시작', showsUserInterface: true),
        AndroidNotificationAction(
          'snooze',
          '10분 미루기',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'complete',
          '완료했어요',
          showsUserInterface: true,
        ),
      ],
    ),
    iOS: DarwinNotificationDetails(
      categoryIdentifier: 'task',
      presentAlert: true,
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
    for (final notification in await plugin.getActiveNotifications()) {
      final payload = notification.payload;
      if (payload == null || notification.id == null) continue;
      final occurrence = resolveReminderPayload(items, payload, now);
      if (occurrence == null || !occurrence.active) {
        await plugin.cancel(id: notification.id!);
      }
    }
    // Preserve visible alerts on a background refill; only remove terminal tasks.
    for (final o in items.where((o) => !o.active)) {
      for (final key in [
        o.id,
        '${o.id}:30',
        '${o.id}:60',
        'overdue:${o.id}:repeat',
      ]) {
        await plugin.cancel(id: notificationId(key));
      }
    }
    await plugin.cancelAllPendingNotifications();
    final ids = <int>{};
    for (final job in lastPlan!.jobs) {
      var id = notificationId(job.key);
      while (!ids.add(id)) {
        id = (id + 1) & 0x7fffffff;
      }
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
        notificationDetails: details(),
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
      id: 100000,
      title: '한걸음 테스트',
      body: '앱 밖에서도 알림이 도착하는지 확인해주세요.',
      scheduledDate: tz.TZDateTime.now(tz.local)
          .add(const Duration(seconds: 10)),
      notificationDetails: details(),
      androidScheduleMode: await mode(),
    );
  }
}
