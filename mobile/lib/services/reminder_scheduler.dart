import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/task.dart';
import '../data/task_repository.dart';
import 'notification_plan.dart';
import 'notification_privacy.dart';
import '../l10n/app_strings.dart';

class ReminderScheduler {
  ReminderScheduler({DateTime Function()? now, TaskRepository? repository})
    : _now = now ?? DateTime.now,
      _privacy = repository == null ? null : NotificationPrivacy(repository);

  static const testNotificationId = 100000;
  static const _testPayloadPrefix = 'todoniq:test:v1:';
  // Foundation can return GMT rather than an IANA region on iOS simulators
  // and devices configured to a zero-offset time zone.
  static tz.Location resolveTimeZone(String identifier) =>
      identifier == 'GMT' || identifier == 'UTC'
      ? tz.UTC
      : tz.getLocation(identifier);
  final plugin = FlutterLocalNotificationsPlugin();
  final DateTime Function() _now;
  final NotificationPrivacy? _privacy;
  Future<void> _queuedWork = Future<void>.value();
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
    // A test request carries scheduling metadata, not a task identity.
    if (response.id == testNotificationId) return;
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
  }) => _serial(() async {
    final showTitles = await _privacy?.load() ?? true;
    try {
      await _sync(items, exceptions: exceptions, showTitles: showTitles);
    } catch (_) {
      if (!showTitles) {
        // If rebuilding private reminders fails (for example a time-zone
        // lookup), do not leave earlier title-bearing requests behind. The
        // caller reports the scheduling error and can retry reconciliation.
        try {
          await plugin.cancelAll();
        } catch (_) {
          // Preserve the original scheduling error for the caller.
        }
      }
      rethrow;
    }
  });

  Future<void> _serial(Future<void> Function() operation) {
    final current = _queuedWork.then((_) => operation());
    // Report a failed operation to its caller without poisoning later work.
    _queuedWork = current.catchError((Object _) {});
    return current;
  }

  Future<void> _sync(
    List<Occurrence> items, {
    required Map<String, List<DateTime>> exceptions,
    required bool showTitles,
  }) async {
    if (accessUntil != null && !accessUntil!.isAfter(_now())) {
      await plugin.cancelAll();
      lastPlan = NotificationPlan([], 0, null);
      return;
    }
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(resolveTimeZone(zone.identifier));
    final now = _now(), scheduleMode = await mode();
    lastPlan = NotificationPlan.build(
      items,
      now: now,
      capacity: defaultTargetPlatform == TargetPlatform.android ? 400 : 60,
      exceptions: exceptions,
      until: accessUntil,
    );
    // Capture a future test before dismissing an older delivered test with the
    // same ID: native cancel(id) can remove both the banner and pending request.
    PendingNotificationRequest? pendingTest;
    DateTime? testAt;
    for (final request in await plugin.pendingNotificationRequests()) {
      if (request.id != testNotificationId) continue;
      final at = _testTime(request.payload);
      if (at != null && _canScheduleTest(at)) {
        pendingTest = request;
        testAt = at;
      }
      break;
    }
    // Deleted and completed reminders disappear, while active alerts survive refill.
    final activePayloads = <int, String>{};
    for (final notification in await plugin.getActiveNotifications()) {
      // A preference change must also remove titles that were already delivered,
      // including older untagged banners and test requests. Pending requests are
      // rescheduled below with the same identity and delivery instant.
      if (!showTitles &&
          notification.id != null &&
          (notification.title != NotificationPrivacy.hiddenContent.title ||
              notification.body != NotificationPrivacy.hiddenContent.body)) {
        await plugin.cancel(id: notification.id!, tag: notification.tag);
        continue;
      }
      // Keep an already delivered test banner; it is not an obsolete task.
      if (notification.id == testNotificationId) continue;
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
    // Pending requests survive a new scheduler instance through their payload.
    // Restore the original instant first, without extending the ten-second wait.
    // A request that fired or expired is absent or no longer in the future.
    if (pendingTest != null && testAt != null && _canScheduleTest(testAt)) {
      final content = NotificationPrivacy.content(
        showTitles: showTitles,
        title: pendingTest.title,
        body: pendingTest.body,
      );
      await plugin.zonedSchedule(
        id: testNotificationId,
        title: content.title,
        body: content.body,
        scheduledDate: tz.TZDateTime.from(testAt, tz.local),
        notificationDetails: details(),
        androidScheduleMode: scheduleMode,
        payload: pendingTest.payload,
      );
    }
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
      final content = NotificationPrivacy.content(
        showTitles: showTitles,
        title: job.title,
        body: job.body,
      );
      await plugin.zonedSchedule(
        id: id,
        title: content.title,
        body: content.body,
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

  static DateTime? _testTime(String? payload) {
    if (payload == null || !payload.startsWith(_testPayloadPrefix)) return null;
    final timestamp = int.tryParse(
      payload.substring(_testPayloadPrefix.length),
    );
    if (timestamp == null) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true);
    } on ArgumentError {
      return null;
    }
  }

  bool _canScheduleTest(DateTime at) =>
      at.isAfter(_now()) && (accessUntil == null || at.isBefore(accessUntil!));

  Future<void> testNotification({bool requestPermission = true}) =>
      _serial(() => _testNotification(requestPermission: requestPermission));

  Future<void> _testNotification({required bool requestPermission}) async {
    if (!_canScheduleTest(_now().add(const Duration(seconds: 10)))) return;
    if (requestPermission) await requestPermissions();
    final scheduleMode = await mode();
    // Permission dialogs can remain open past the access deadline. Darwin
    // calendar triggers use whole seconds, so the payload must match that instant.
    final at = DateTime.fromMillisecondsSinceEpoch(
      (_now().add(const Duration(seconds: 10)).millisecondsSinceEpoch ~/ 1000) *
          1000,
      isUtc: true,
    );
    if (!_canScheduleTest(at)) return;
    final content = NotificationPrivacy.content(
      showTitles: await _privacy?.load() ?? true,
      title: AppStrings.current.t('투두닉 테스트'),
      body: AppStrings.current.t('앱 밖에서도 알림이 도착하는지 확인해주세요.'),
    );
    await plugin.zonedSchedule(
      id: testNotificationId,
      title: content.title,
      body: content.body,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: details(),
      androidScheduleMode: scheduleMode,
      payload: '$_testPayloadPrefix${at.millisecondsSinceEpoch}',
    );
  }
}
