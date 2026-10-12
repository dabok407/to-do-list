import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  const notificationChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezoneChannel = MethodChannel('flutter_timezone');

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('${platform.name} 테스트 알림 보존', () {
      late FlutterLocalNotificationsPlatform previousPlatform;
      TargetPlatform? previousTargetPlatform;
      late Map<int, Map<String, Object?>> pending;
      late List<Map<String, Object?>> active;
      late List<MethodCall> calls;
      late DateTime now;
      late String zone;
      Future<void> Function(MethodCall)? beforeCall;
      late ReminderScheduler scheduler;

      Map<String, Object?> getTest() =>
          pending[ReminderScheduler.testNotificationId]!;

      Occurrence task() {
        final due = now.add(const Duration(hours: 1));
        final task = Task(
          id: 'task',
          title: '업무 알림',
          due: due,
          created: now,
          overdueDays: 0,
        );
        return Occurrence(
          id: 'task@${due.toIso8601String()}',
          task: task,
          originalDue: due,
          reminder: due,
        );
      }

      List<MethodCall> scheduledTests() => calls
          .where(
            (call) =>
                call.method == 'zonedSchedule' &&
                (call.arguments as Map)['id'] ==
                    ReminderScheduler.testNotificationId,
          )
          .toList();

      setUp(() {
        previousPlatform = FlutterLocalNotificationsPlatform.instance;
        previousTargetPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = platform;
        if (platform == TargetPlatform.android) {
          AndroidFlutterLocalNotificationsPlugin.registerWith();
        } else {
          IOSFlutterLocalNotificationsPlugin.registerWith();
        }
        tzdata.initializeTimeZones();
        tz.setLocalLocation(tz.UTC);
        // The platform plugin also validates against the real wall clock.
        final future = DateTime.now().toUtc().add(const Duration(days: 1));
        now = DateTime.utc(
          future.year,
          future.month,
          future.day,
          future.hour,
          future.minute,
          future.second,
        );
        zone = 'UTC';
        scheduler = ReminderScheduler(now: () => now);
        pending = {};
        active = [];
        calls = [];
        beforeCall = null;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          timezoneChannel,
          (call) async => zone,
        );
        messenger.setMockMethodCallHandler(notificationChannel, (call) async {
          calls.add(call);
          await beforeCall?.call(call);
          switch (call.method) {
            case 'requestPermissions':
            case 'requestNotificationsPermission':
            case 'canScheduleExactNotifications':
              return true;
            case 'getActiveNotifications':
              return active;
            case 'pendingNotificationRequests':
              return [
                for (final job in pending.values)
                  {
                    'id': job['id'],
                    'title': job['title'],
                    'body': job['body'],
                    'payload': job['payload'],
                  },
              ];
            case 'cancelAllPendingNotifications':
              pending.clear();
              return null;
            case 'cancelAll':
              pending.clear();
              active.clear();
              return null;
            case 'zonedSchedule':
              final args = Map<String, Object?>.from(call.arguments as Map);
              pending[args['id'] as int] = args;
              return null;
            default:
              return null;
          }
        });
      });

      tearDown(() {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(notificationChannel, null);
        messenger.setMockMethodCallHandler(timezoneChannel, null);
        FlutterLocalNotificationsPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = previousTargetPlatform;
      });

      test('업무 동기화가 실제 pending 테스트 예약과 원래 시각을 보존', () async {
        await scheduler.testNotification();
        final original = Map<String, Object?>.from(
          pending[ReminderScheduler.testNotificationId]!,
        );
        await scheduler.sync([]);
        expect(pending, contains(ReminderScheduler.testNotificationId));
        final restored = pending[ReminderScheduler.testNotificationId]!;
        for (final field in [
          'title',
          'body',
          'payload',
          'scheduledDateTime',
          'scheduledDateTimeISO8601',
        ]) {
          expect(restored[field], original[field], reason: field);
        }
      });

      test('동기화마다 원래 시각과 문구를 유지하고 업무보다 먼저 복원', () async {
        await scheduler.testNotification();
        final original = Map<String, Object?>.from(getTest());
        pending[ReminderScheduler.testNotificationId] = {
          ...original,
          'title': 'Saved English test title',
          'body': 'Saved English test body',
        };
        now = now.add(const Duration(seconds: 2));
        calls.clear();
        await scheduler.sync([task()]);
        final scheduled = calls
            .where((call) => call.method == 'zonedSchedule')
            .toList();
        expect(scheduled, hasLength(2));
        expect(
          (scheduled.first.arguments as Map)['id'],
          ReminderScheduler.testNotificationId,
        );
        expect(
          calls[calls.indexOf(scheduled.first) - 1].method,
          'cancelAllPendingNotifications',
        );
        expect(getTest()['title'], 'Saved English test title');
        expect(getTest()['body'], 'Saved English test body');
        expect(getTest()['payload'], original['payload']);
        expect(getTest()['scheduledDateTime'], original['scheduledDateTime']);
        now = now.add(const Duration(seconds: 2));
        await scheduler.sync([]);
        expect(getTest()['scheduledDateTime'], original['scheduledDateTime']);
      });

      test('새 scheduler도 실제 pending payload에서 발송 시각을 복원', () async {
        await scheduler.testNotification();
        final original = Map<String, Object?>.from(getTest());
        now = now.add(const Duration(seconds: 3));
        await ReminderScheduler(now: () => now).sync([]);
        expect(getTest()['payload'], original['payload']);
        expect(getTest()['scheduledDateTime'], original['scheduledDateTime']);
      });

      test('밀리초가 있는 현재 시각도 OS 트리거와 payload의 발송 시각이 같음', () async {
        now = now.add(const Duration(microseconds: 123456));
        await scheduler.testNotification();
        final original = Map<String, Object?>.from(getTest());
        final at = DateTime.fromMillisecondsSinceEpoch(
          int.parse((original['payload'] as String).split(':').last),
          isUtc: true,
        );
        expect(at.millisecond, 0);
        expect(at.microsecond, 0);
        expect(original['scheduledDateTimeISO8601'], at.toIso8601String());
        await scheduler.sync([]);
        expect(
          getTest()['scheduledDateTimeISO8601'],
          original['scheduledDateTimeISO8601'],
        );
      });

      test('시간대가 바뀌어도 테스트의 절대 발송 시각을 유지', () async {
        await scheduler.testNotification();
        final originalAt = now.add(const Duration(seconds: 10));
        zone = 'Asia/Seoul';
        await scheduler.sync([]);
        expect(getTest()['timeZoneName'], 'Asia/Seoul');
        expect(
          getTest()['scheduledDateTimeISO8601'],
          tz.TZDateTime.from(
            originalAt,
            tz.getLocation('Asia/Seoul'),
          ).toIso8601String(),
        );
        final payload = getTest()['payload'] as String;
        expect(payload.endsWith('${originalAt.millisecondsSinceEpoch}'), true);
      });

      test('이미 전달된 테스트 배너는 유지하며 pending이 없으면 재생성하지 않음', () async {
        await scheduler.testNotification();
        final original = Map<String, Object?>.from(getTest());
        pending.remove(ReminderScheduler.testNotificationId);
        active.add({
          'id': ReminderScheduler.testNotificationId,
          if (platform == TargetPlatform.iOS) 'payload': original['payload'],
          if (platform == TargetPlatform.android) 'tag': original['payload'],
        });
        await scheduler.sync([]);
        await scheduler.sync([]);
        expect(scheduledTests(), hasLength(1));
        expect(active, hasLength(1));
        expect(calls.where((call) => call.method == 'cancel'), isEmpty);
      });

      test('기존 테스트 배너가 있어도 새 미래 pending 테스트는 보존', () async {
        await scheduler.testNotification();
        active.add({
          'id': ReminderScheduler.testNotificationId,
          'payload': getTest()['payload'],
        });
        now = now.add(const Duration(seconds: 2));
        await scheduler.testNotification();
        final original = Map<String, Object?>.from(getTest());
        await scheduler.sync([]);
        expect(getTest()['payload'], original['payload']);
        expect(active, hasLength(1));
      });

      test('이미 발송 시각이 지난 pending 테스트는 재예약하지 않음', () async {
        await scheduler.testNotification();
        now = now.add(const Duration(seconds: 10));
        await scheduler.sync([]);
        expect(pending, isEmpty);
        expect(scheduledTests(), hasLength(1));
      });

      test('pending 삭제를 기다리는 중 발송 시각이 지나면 복원하지 않음', () async {
        await scheduler.testNotification();
        beforeCall = (call) async {
          if (call.method == 'cancelAllPendingNotifications') {
            now = now.add(const Duration(seconds: 10));
          }
        };
        await scheduler.sync([]);
        expect(pending, isEmpty);
        expect(scheduledTests(), hasLength(1));
      });

      test('접근 만료 시 기존 cancelAll 정책으로 예약과 배너 모두 제거', () async {
        await scheduler.testNotification();
        active.add({'id': ReminderScheduler.testNotificationId});
        scheduler.accessUntil = now;
        await scheduler.sync([]);
        expect(pending, isEmpty);
        expect(active, isEmpty);
        expect(calls.where((call) => call.method == 'cancelAll'), hasLength(1));
        expect(scheduler.lastPlan!.jobs, isEmpty);
      });

      test('테스트 발송 시각이 접근 종료와 같거나 늦으면 복원하지 않음', () async {
        await scheduler.testNotification();
        scheduler.accessUntil = now.add(const Duration(seconds: 10));
        await scheduler.sync([]);
        expect(pending, isEmpty);
        expect(scheduledTests(), hasLength(1));
      });

      test('접근 기간이 부족하면 권한 요청 없이 테스트 예약을 거절', () async {
        scheduler.accessUntil = now.add(const Duration(seconds: 10));
        await scheduler.testNotification();
        expect(calls, isEmpty);
        expect(pending, isEmpty);
      });

      test('권한 응답을 기다리는 중 접근이 만료되면 테스트를 예약하지 않음', () async {
        scheduler.accessUntil = now.add(const Duration(seconds: 30));
        beforeCall = (call) async {
          if (call.method == 'requestPermissions' ||
              call.method == 'requestNotificationsPermission') {
            now = now.add(const Duration(seconds: 25));
          }
        };
        await scheduler.testNotification();
        expect(pending, isEmpty);
      });

      test('잘못된 시각 payload나 예전 payload 없는 테스트는 복원하지 않음', () async {
        for (final payload in [
          null,
          '',
          'task@2026-10-12',
          'todoniq:test:v1:invalid',
          'todoniq:test:v1:999999999999999999999999',
          'todoniq:test:v1:8640000000000001',
        ]) {
          pending[ReminderScheduler.testNotificationId] = {
            'id': ReminderScheduler.testNotificationId,
            'title': 'legacy',
            'payload': payload,
          };
          await scheduler.sync([]);
          expect(pending, isEmpty, reason: '$payload');
        }
        expect(scheduledTests(), isEmpty);
      });

      test('테스트 알림 응답을 업무 열기나 완료로 전달하지 않음', () async {
        await scheduler.testNotification();
        final actions = <String>[];
        scheduler.onAction = (id, action) async => actions.add('$id:$action');
        for (final action in ['', 'complete']) {
          await scheduler.respond(
            NotificationResponse(
              notificationResponseType:
                  NotificationResponseType.selectedNotification,
              id: ReminderScheduler.testNotificationId,
              payload: getTest()['payload'] as String,
              actionId: action,
            ),
          );
        }
        expect(actions, isEmpty);
        await scheduler.respond(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            id: 123,
            payload: 'task@due',
          ),
        );
        expect(actions, ['task@due:open']);
      });

      test('상위 호출자가 권한을 요청한 경우 중복 권한 요청 없이 예약', () async {
        await scheduler.testNotification(requestPermission: false);
        expect(pending, contains(ReminderScheduler.testNotificationId));
        expect(
          calls.where((call) => call.method.startsWith('request')),
          isEmpty,
        );
      });

      test('sync 도중 테스트 요청은 pending 취소가 끝날 때까지 대기', () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        beforeCall = (call) async {
          if (call.method == 'cancelAllPendingNotifications') {
            entered.complete();
            await release.future;
          }
        };
        final sync = scheduler.sync([task()]);
        await entered.future;
        final test = scheduler.testNotification();
        await Future<void>.delayed(Duration.zero);
        expect(scheduledTests(), isEmpty);
        expect(
          calls.where((call) => call.method.startsWith('request')),
          isEmpty,
        );
        release.complete();
        await Future.wait([sync, test]);
        expect(pending, hasLength(2));
        expect(scheduledTests(), hasLength(1));
      });

      test('테스트 권한 요청 도중 sync는 기다린 후 실제 예약을 보존', () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        beforeCall = (call) async {
          if (call.method == 'requestPermissions' ||
              call.method == 'requestNotificationsPermission') {
            entered.complete();
            await release.future;
          }
        };
        final test = scheduler.testNotification();
        await entered.future;
        final sync = scheduler.sync([]);
        await Future<void>.delayed(Duration.zero);
        expect(
          calls.where((call) => call.method == 'cancelAllPendingNotifications'),
          isEmpty,
        );
        release.complete();
        await Future.wait([test, sync]);
        expect(pending, contains(ReminderScheduler.testNotificationId));
        expect(scheduledTests(), hasLength(2));
        expect(
          (scheduledTests()[0].arguments as Map)['payload'],
          (scheduledTests()[1].arguments as Map)['payload'],
        );
      });

      for (final failure in [
        'cancelAllPendingNotifications',
        'requestPermissions',
        'zonedSchedule',
      ]) {
        test('$failure 실패 후 다음 queued 작업은 정상 진행', () async {
          var didFail = false;
          beforeCall = (call) async {
            final shouldFail = failure == 'requestPermissions'
                ? call.method == 'requestPermissions' ||
                      call.method == 'requestNotificationsPermission'
                : call.method == failure;
            if (shouldFail && !didFail) {
              didFail = true;
              throw PlatformException(code: 'transient');
            }
          };
          final failed = failure == 'cancelAllPendingNotifications'
              ? scheduler.sync([])
              : scheduler.testNotification();
          final recovered = failure == 'requestPermissions'
              ? scheduler.sync([task()])
              : scheduler.testNotification();
          await expectLater(failed, throwsA(isA<PlatformException>()));
          await recovered;
          expect(didFail, true);
          expect(pending, hasLength(1));
          if (failure != 'requestPermissions') {
            expect(pending, contains(ReminderScheduler.testNotificationId));
          }
        });
      }
    });
  }
}
