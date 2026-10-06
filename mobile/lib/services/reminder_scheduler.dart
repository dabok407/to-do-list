import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/task.dart';

class ReminderScheduler {
  final plugin = FlutterLocalNotificationsPlugin();
  Future<void> Function(String id, String action)? onAction;
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
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

  void respond(NotificationResponse response) {
    final id = response.payload;
    if (id != null &&
        response.actionId != null &&
        response.actionId!.isNotEmpty) {
      onAction?.call(id, response.actionId!);
    }
  }

  Future<void> handleLaunch() async {
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      respond(launch!.notificationResponse!);
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
      channelDescription: '예정된 할 일과 보류 후 재알림',
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
  Future<void> sync(List<Occurrence> items) async {
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    final now = DateTime.now(), scheduleMode = await mode();
    final jobs = <({Occurrence occurrence, DateTime at, int followup})>[];
    for (final o in items.where((o) => o.active)) {
      if (!o.reminder.isAfter(now)) continue;
      jobs.add((occurrence: o, at: o.reminder, followup: 0));
      if (o.status == TaskStatus.paused) {
        for (final minutes in [30, 60]) {
          final at = o.reminder.add(Duration(minutes: minutes));
          if (dayOf(at) == dayOf(o.reminder)) {
            jobs.add((occurrence: o, at: at, followup: minutes));
          }
        }
      }
    }
    jobs.sort((a, b) => a.at.compareTo(b.at));
    // Stay below Apple's pending-notification cap; refill on launches and actions.
    await plugin.cancelAll();
    var id = 1;
    for (final job in jobs.take(60)) {
      final o = job.occurrence;
      await plugin.zonedSchedule(
        id: id++,
        title: o.task.title,
        body: o.status == TaskStatus.progressing
            ? '진행은 어떤가요? 완료했거나 잠시 쉬어도 괜찮아요.'
            : job.followup > 0
            ? '아까 하기로 한 일이 있어요. 5분만 시작해볼까요?'
            : o.status == TaskStatus.paused
            ? '아까 하기로 했어요. 지금 시작해볼까요?'
            : '지금 시작해볼까요?',
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
        payload: o.id,
      );
    }
  }

  Future<void> testNotification() async {
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
