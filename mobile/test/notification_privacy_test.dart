import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/services/notification_privacy.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezone = MethodChannel('flutter_timezone');

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('${platform.name} 알림 제목 공개 설정', () {
      late FlutterLocalNotificationsPlatform previousPlugin;
      late AppStrings previousStrings;
      TargetPlatform? previousTarget;
      late TaskRepository repository;
      late ReminderScheduler scheduler;
      late DateTime now;
      late Map<int, Map<String, Object?>> pending;
      late List<Map<String, Object?>> active;
      late List<MethodCall> calls;

      Occurrence occurrence(
        String id, {
        RepeatUnit repeat = RepeatUnit.none,
        TaskStatus status = TaskStatus.pending,
        bool overdue = false,
      }) {
        final due = DateTime(now.year, now.month, now.day, 12);
        final original = overdue ? due.subtract(const Duration(days: 1)) : due;
        final task = Task(
          id: id,
          title: '개인 제목 $id',
          note: '공개 금지 메모',
          smallStep: '공개 금지 작은 단계',
          due: original,
          created: now,
          repeat: repeat,
          weekdays: [due.weekday],
          overdueDays: overdue ? 1 : 0,
        );
        return Occurrence(
          id: '$id@${original.toIso8601String()}',
          task: task,
          originalDue: original,
          reminder: status == TaskStatus.pending ? original : due,
          status: status,
          snoozes: status == TaskStatus.paused ? 1 : 0,
        );
      }

      setUp(() async {
        previousPlugin = FlutterLocalNotificationsPlatform.instance;
        previousTarget = debugDefaultTargetPlatformOverride;
        previousStrings = AppStrings.current;
        AppStrings.current = const AppStrings('ko');
        debugDefaultTargetPlatformOverride = platform;
        if (platform == TargetPlatform.android) {
          AndroidFlutterLocalNotificationsPlugin.registerWith();
        } else {
          IOSFlutterLocalNotificationsPlugin.registerWith();
        }
        tzdata.initializeTimeZones();
        tz.setLocalLocation(tz.UTC);
        final future = DateTime.now().add(const Duration(days: 2));
        now = DateTime(future.year, future.month, future.day, 9);
        repository = await TaskRepository.open(
          databasePath: inMemoryDatabasePath,
        );
        scheduler = ReminderScheduler(repository: repository, now: () => now);
        pending = {};
        active = [];
        calls = [];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(timezone, (_) async => 'UTC');
        messenger.setMockMethodCallHandler(notifications, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'requestPermissions':
            case 'requestNotificationsPermission':
            case 'canScheduleExactNotifications':
              return true;
            case 'getActiveNotifications':
              return active;
            case 'pendingNotificationRequests':
              return pending.values.toList();
            case 'cancelAllPendingNotifications':
              pending.clear();
              return null;
            case 'cancelAll':
              pending.clear();
              active.clear();
              return null;
            case 'cancel':
              final id = platform == TargetPlatform.iOS
                  ? call.arguments as int
                  : (call.arguments as Map)['id'];
              active.removeWhere((item) => item['id'] == id);
              pending.remove(id);
              return null;
            case 'zonedSchedule':
              final arguments = Map<String, Object?>.from(
                call.arguments as Map,
              );
              pending[arguments['id'] as int] = arguments;
              return null;
            default:
              return null;
          }
        });
      });

      tearDown(() async {
        await repository.db.close();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(timezone, null);
        messenger.setMockMethodCallHandler(notifications, null);
        FlutterLocalNotificationsPlatform.instance = previousPlugin;
        debugDefaultTargetPlatformOverride = previousTarget;
        AppStrings.current = previousStrings;
      });

      test('최초 설치는 제목 표시이며 새 서비스도 저장값을 읽는다', () async {
        expect(await NotificationPrivacy(repository).load(), true);
        final task = occurrence('default');
        await scheduler.sync([task]);
        expect(pending.values.single['title'], task.task.title);
        await NotificationPrivacy(repository).setShowTitles(false);
        expect(
          await NotificationPrivacy(TaskRepository(repository.db)).load(),
          false,
        );
        final restarted = ReminderScheduler(
          repository: TaskRepository(repository.db),
          now: () => now,
        );
        await restarted.sync([task]);
        expect(pending.values.single['title'], '투두닉');
        await NotificationPrivacy(repository).setShowTitles(true);
        await restarted.sync([task]);
        expect(pending.values.single['title'], task.task.title);
      });

      test('단발·반복·미완료·진행·미루기 알림 전체의 내용과 제목을 가린다', () async {
        final tasks = [
          occurrence('single'),
          occurrence('daily', repeat: RepeatUnit.daily),
          occurrence('weekly', repeat: RepeatUnit.weekly),
          occurrence('monthly', repeat: RepeatUnit.monthly),
          occurrence('overdue', overdue: true),
          occurrence('progress', status: TaskStatus.progressing),
          occurrence('snoozed', status: TaskStatus.paused),
        ];
        await scheduler.sync(tasks);
        final original = Map<int, Map<String, Object?>>.from(pending);
        expect(original.length, greaterThanOrEqualTo(7));
        await NotificationPrivacy(repository).setShowTitles(false);
        await scheduler.sync(tasks);
        expect(pending.keys, unorderedEquals(original.keys));
        for (final entry in pending.entries) {
          expect(entry.value['title'], '투두닉');
          expect(entry.value['body'], '예정된 할 일을 확인해주세요.');
          for (final field in [
            'payload',
            'scheduledDateTime',
            'scheduledDateTimeISO8601',
            'matchDateTimeComponents',
            'platformSpecifics',
          ]) {
            expect(
              entry.value[field],
              original[entry.key]![field],
              reason: field,
            );
          }
          expect(entry.value.toString(), isNot(contains('개인 제목')));
          expect(entry.value.toString(), isNot(contains('공개 금지')));
        }
      });

      test('이미 전달된 제목 배너와 오래된 태그 없는 배너도 제거한다', () async {
        final task = occurrence('active');
        active.addAll([
          {
            'id': 301,
            'title': task.task.title,
            'body': '이전 내용',
            'payload': task.id,
            'tag': task.id,
          },
          {'id': 302, 'title': '이전 개인 제목', 'body': '태그가 없는 이전 버전'},
          {
            'id': 303,
            'title': '투두닉',
            'body': '예정된 할 일을 확인해주세요.',
            'payload': task.id,
            'tag': task.id,
          },
          {
            'id': ReminderScheduler.testNotificationId,
            'title': '이전 테스트',
            'body': '이전 내용',
          },
        ]);
        await NotificationPrivacy(repository).setShowTitles(false);
        await scheduler.sync([task]);
        expect(active.map((item) => item['id']), [303]);
        final cancelled = calls
            .where((call) => call.method == 'cancel')
            .map(
              (call) => platform == TargetPlatform.iOS
                  ? call.arguments as int
                  : (call.arguments as Map)['id'],
            );
        expect(
          cancelled,
          unorderedEquals([301, 302, ReminderScheduler.testNotificationId]),
        );
      });

      test('예약된 테스트도 원래 시각·payload를 보존하며 영문 일반 문구로 교체한다', () async {
        await scheduler.testNotification(requestPermission: false);
        final original = Map<String, Object?>.from(
          pending[ReminderScheduler.testNotificationId]!,
        );
        // An older request may have text captured before a privacy change.
        pending[ReminderScheduler.testNotificationId] = {
          ...original,
          'title': '개인 제목 테스트',
          'body': '공개 금지 메모',
        };
        AppStrings.current = const AppStrings('en');
        await NotificationPrivacy(repository).setShowTitles(false);
        await scheduler.sync([]);
        final replacement = pending[ReminderScheduler.testNotificationId]!;
        expect(replacement['title'], 'Todoniq');
        expect(replacement['body'], 'Open the app to see your scheduled task.');
        expect(replacement['payload'], original['payload']);
        expect(
          replacement['scheduledDateTimeISO8601'],
          original['scheduledDateTimeISO8601'],
        );
        await scheduler.testNotification(requestPermission: false);
        expect(
          pending[ReminderScheduler.testNotificationId]!['title'],
          'Todoniq',
        );
        expect(
          pending[ReminderScheduler.testNotificationId]!['body'],
          'Open the app to see your scheduled task.',
        );
      });

      test('숨김 설정은 동일 시각 알림을 합치지 않고 각각의 열기 대상을 유지한다', () async {
        final a = occurrence('same-a');
        final b = occurrence('same-b');
        await NotificationPrivacy(repository).setShowTitles(false);
        await scheduler.sync([a, b]);
        expect(pending, hasLength(2));
        expect(
          pending.values.map((item) => item['payload']),
          unorderedEquals([a.id, b.id]),
        );
        expect(pending.values.map((item) => item['title']).toSet(), {'투두닉'});
      });

      test('손상된 설정값으로 제목이 의도치 않게 다시 노출되지 않는다', () async {
        await repository.setSetting(NotificationPrivacy.settingKey, 'invalid');
        await scheduler.sync([occurrence('invalid-setting')]);
        expect(pending.values.single['title'], '투두닉');
        expect(pending.values.single['body'], '예정된 할 일을 확인해주세요.');
      });

      test('숨김 재예약에 실패해도 기존 제목 알림을 그대로 남겨두지 않는다', () async {
        await scheduler.sync([occurrence('before-error')]);
        active.add({'id': 401, 'title': '기존 개인 제목', 'body': '이전 내용'});
        expect(pending, isNotEmpty);
        await NotificationPrivacy(repository).setShowTitles(false);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              timezone,
              (_) async =>
                  throw PlatformException(code: 'timezone-unavailable'),
            );
        await expectLater(
          scheduler.sync([occurrence('before-error')]),
          throwsA(isA<PlatformException>()),
        );
        expect(pending, isEmpty);
        expect(active, isEmpty);
      });

      test('이전 테스트 배너를 가리면서 같은 ID의 새 테스트 예약을 보존한다', () async {
        await scheduler.testNotification(requestPermission: false);
        final original = Map<String, Object?>.from(
          pending[ReminderScheduler.testNotificationId]!,
        );
        active.add({
          'id': ReminderScheduler.testNotificationId,
          'title': '이전 테스트 제목',
          'body': '이전 내용',
        });
        await NotificationPrivacy(repository).setShowTitles(false);
        await scheduler.sync([]);
        expect(active, isEmpty);
        final restored = pending[ReminderScheduler.testNotificationId]!;
        expect(restored['title'], '투두닉');
        expect(restored['payload'], original['payload']);
        expect(
          restored['scheduledDateTimeISO8601'],
          original['scheduledDateTimeISO8601'],
        );
      });
    });
  }
}
