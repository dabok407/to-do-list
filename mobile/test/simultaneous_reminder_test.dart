import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/services/notification_plan.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tzdata;

Task makeTask(
  String id,
  DateTime due, {
  RepeatUnit repeat = RepeatUnit.none,
  int overdueDays = 0,
}) => Task(
  id: id,
  title: '에어컨 필터 청소',
  due: due,
  created: due.subtract(const Duration(days: 1)),
  repeat: repeat,
  overdueDays: overdueDays,
);

Occurrence makeOccurrence(
  Task task, {
  String? id,
  DateTime? due,
  DateTime? reminder,
  TaskStatus status = TaskStatus.pending,
  int snoozes = 0,
}) => Occurrence(
  id: id ?? '${task.id}@${(due ?? task.due).toIso8601String()}',
  task: task,
  originalDue: due ?? task.due,
  reminder: reminder ?? due ?? task.due,
  status: status,
  snoozes: snoozes,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Tests have no GeneratedPluginRegistrant. Version 22.3.1 leaves its platform
  // singleton late until registration, unlike the former fallback instance.
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  final now = DateTime(2026, 10, 11, 9);
  final due = DateTime(2026, 10, 11, 12);

  test('동일 제목과 시각의 서로 다른 업무는 별도 예약과 payload를 갖는다', () {
    final a = makeOccurrence(makeTask('a', due));
    final b = makeOccurrence(makeTask('b', due));
    final jobs = NotificationPlan.build([a, b], now: now, capacity: 60).jobs;
    expect(jobs, hasLength(2));
    expect(jobs.map((job) => job.at), everyElement(due));
    expect(jobs.map((job) => job.payload).toSet(), {a.id, b.id});
    expect(jobs.map((job) => job.key).toSet(), hasLength(2));
  });

  test('동일 시각의 매일 반복 업무는 별도 OS 반복 트리거를 갖는다', () {
    final a = makeTask('a', due, repeat: RepeatUnit.daily);
    final b = makeTask('b', due, repeat: RepeatUnit.daily);
    final jobs = NotificationPlan.build(
      [
        for (final task in [a, b])
          for (var day = 0; day < 7; day++)
            makeOccurrence(task, due: due.add(Duration(days: day))),
      ],
      now: now,
      capacity: 60,
    ).jobs;
    expect(jobs, hasLength(2));
    expect(
      jobs.map((job) => job.repeat),
      everyElement(NotificationRepeat.daily),
    );
    expect(jobs.map((job) => job.key).toSet(), {'repeat:a:0', 'repeat:b:0'});
    expect(jobs.map((job) => job.payload).toSet(), {
      'repeat:a:0',
      'repeat:b:0',
    });
  });

  test('동일 시각의 미완료 재알림은 업무 사이에서 합쳐지지 않는다', () {
    final past = due.subtract(const Duration(days: 1));
    final a = makeOccurrence(makeTask('a', past, overdueDays: 1));
    final b = makeOccurrence(makeTask('b', past, overdueDays: 1));
    final jobs = NotificationPlan.build([a, b], now: now, capacity: 60).jobs;
    expect(jobs, hasLength(2));
    expect(jobs.map((job) => job.at), everyElement(due));
    expect(
      jobs.map((job) => job.repeat),
      everyElement(NotificationRepeat.daily),
    );
    expect(jobs.map((job) => job.payload).toSet(), {a.id, b.id});
  });

  test('동일 시간 업무 하나를 미루어도 다른 업무의 원래 시각은 유지된다', () {
    final a = makeOccurrence(
      makeTask('a', due),
      reminder: due.add(const Duration(minutes: 10)),
      status: TaskStatus.paused,
      snoozes: 1,
    );
    final b = makeOccurrence(makeTask('b', due));
    final jobs = NotificationPlan.build([a, b], now: now, capacity: 60).jobs;
    expect(jobs, hasLength(2));
    expect(jobs.singleWhere((job) => job.payload == a.id).at, a.reminder);
    expect(jobs.singleWhere((job) => job.payload == b.id).at, due);
  });

  test('같은 시간 업무를 저장·다시 읽은 후 완료와 미루기는 개별 회차에만 적용', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final repository = await TaskRepository.open(
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(repository.db.close);
    final future = DateTime.now().add(const Duration(hours: 1));
    await repository.saveTask(makeTask('a', future));
    await repository.saveTask(makeTask('b', future));
    var rows = await repository.occurrences();
    expect(rows, hasLength(2));
    final a = rows.singleWhere((row) => row.task.id == 'a');
    final b = rows.singleWhere((row) => row.task.id == 'b');
    expect(a.originalDue, b.originalDue);
    await repository.act(a.id, 'snooze', minutes: 10);
    rows = await repository.occurrences();
    expect(rows.singleWhere((row) => row.id == a.id).status, TaskStatus.paused);
    expect(
      rows.singleWhere((row) => row.id == b.id).status,
      TaskStatus.pending,
    );
    expect(rows.singleWhere((row) => row.id == b.id).reminder, future);
    await repository.act(a.id, 'complete');
    rows = await repository.occurrences();
    final jobs = NotificationPlan.build(
      rows,
      now: DateTime.now(),
      capacity: 60,
    ).jobs;
    expect(jobs, hasLength(1));
    expect(jobs.single.payload, b.id);
    expect(jobs.single.at, future);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('${platform.name} 실제 플러그인 메서드 전달', () {
      const notificationChannel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      const timezoneChannel = MethodChannel('flutter_timezone');
      late FlutterLocalNotificationsPlatform previousPlatform;
      TargetPlatform? previousTargetPlatform;
      late ReminderScheduler scheduler;
      late List<Map<String, Object?>> active;
      late Map<int, Map<String, Object?>> pending;
      late List<int> cancelled;
      late List<String?> cancelledTags;

      Map<String, Object?> delivered(int id, String payload) => {
        'id': id,
        if (platform == TargetPlatform.android) 'tag': payload,
        if (platform == TargetPlatform.iOS) 'payload': payload,
      };

      Map<String, Object?> deliverJob(Map<String, Object?> job) =>
          delivered(job['id'] as int, job['payload'] as String);

      String? activePayload(Map<String, Object?> notification) =>
          (notification['payload'] ?? notification['tag']) as String?;

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
        scheduler = ReminderScheduler();
        active = [];
        pending = {};
        cancelled = [];
        cancelledTags = [];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          timezoneChannel,
          (call) async => 'UTC',
        );
        messenger.setMockMethodCallHandler(notificationChannel, (call) async {
          switch (call.method) {
            case 'getActiveNotifications':
              return active;
            case 'canScheduleExactNotifications':
              return true;
            case 'cancelAllPendingNotifications':
              pending.clear();
              return null;
            case 'cancel':
              final args = call.arguments;
              final id = args is int ? args : (args as Map)['id'] as int;
              final tag = args is Map ? args['tag'] as String? : null;
              cancelled.add(id);
              cancelledTags.add(tag);
              active.removeWhere(
                (notification) =>
                    notification['id'] == id &&
                    (platform == TargetPlatform.iOS ||
                        notification['tag'] == tag),
              );
              pending.remove(id);
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

      test('같은 제목·시각을 플랫폼에 서로 다른 ID로 두 번 예약', () async {
        final future = DateTime.now().add(const Duration(hours: 1));
        final a = makeOccurrence(makeTask('a', future));
        final b = makeOccurrence(makeTask('b', future));
        await scheduler.sync([a, b]);
        expect(pending, hasLength(2));
        expect(pending.values.map((job) => job['payload']).toSet(), {
          a.id,
          b.id,
        });
        expect(
          pending.values.map((job) => job['scheduledDateTime']).toSet(),
          hasLength(1),
        );
        for (final job in pending.values) {
          final details = job['platformSpecifics'] as Map;
          if (platform == TargetPlatform.android) {
            expect(details['tag'], job['payload']);
            expect(details['onlyAlertOnce'], false);
            expect(details['groupKey'], isNull);
          } else {
            expect(details['presentBanner'], true);
            expect(details['presentList'], true);
            expect(details['presentSound'], true);
            expect(details['threadIdentifier'], isNull);
          }
        }
      });

      test('실제 해시 충돌이 있어도 두 예약이 덮어쓰이지 않는다', () async {
        const idA = 'task-1gytfkf-1phy';
        const idB = 'task-bd897y-1q43';
        expect(
          ReminderScheduler.notificationId(idA),
          ReminderScheduler.notificationId(idB),
        );
        final future = DateTime.now().add(const Duration(hours: 1));
        final a = makeOccurrence(makeTask('a', future), id: idA);
        final b = makeOccurrence(makeTask('b', future), id: idB);
        await scheduler.sync([a, b]);
        expect(pending, hasLength(2));
        expect(pending.values.map((job) => job['payload']).toSet(), {idA, idB});
        expect(
          pending.keys,
          isNot(contains(ReminderScheduler.testNotificationId)),
        );
      });

      test('완료 취소는 충돌 보정된 실제 알림 ID만 제거한다', () async {
        const idA = 'task-1gytfkf-1phy';
        const idB = 'task-bd897y-1q43';
        final future = DateTime.now().add(const Duration(hours: 1));
        final a = makeOccurrence(makeTask('a', future), id: idA);
        final b = makeOccurrence(makeTask('b', future), id: idB);
        await scheduler.sync([a, b]);
        active.addAll(pending.values.map(deliverJob));
        final actualB =
            active.singleWhere((job) => activePayload(job) == idB)['id'] as int;
        final completedB = makeOccurrence(
          b.task,
          id: idB,
          status: TaskStatus.completed,
        );
        await scheduler.sync([a, completedB]);
        expect(cancelled, [actualB]);
        expect(cancelledTags, [
          platform == TargetPlatform.android ? idB : null,
        ]);
        expect(activePayload(active.single), idA);
        expect(pending.values.single['payload'], idA);
      });

      test('충돌 상대 업무가 완료돼도 남은 업무의 실제 ID를 재사용', () async {
        const idA = 'task-1gytfkf-1phy';
        const idB = 'task-bd897y-1q43';
        final future = DateTime.now().add(const Duration(hours: 1));
        final a = makeOccurrence(makeTask('a', future), id: idA);
        final b = makeOccurrence(makeTask('b', future), id: idB);
        await scheduler.sync([a, b]);
        active.addAll(pending.values.map(deliverJob));
        final actualB =
            active.singleWhere((job) => activePayload(job) == idB)['id'] as int;
        expect(actualB, isNot(ReminderScheduler.notificationId(idB)));
        final completedA = makeOccurrence(
          a.task,
          id: idA,
          status: TaskStatus.completed,
        );
        await scheduler.sync([completedA, b]);
        expect(activePayload(active.single), idB);
        expect(pending.keys.single, actualB);
        expect(pending.values.single['payload'], idB);
        await scheduler.sync([b]);
        expect(pending.keys.single, actualB);
      });

      test('같은 payload의 여러 후속 일정은 실제 ID 하나로 합치지 않는다', () async {
        final future = DateTime.now().add(const Duration(hours: 1));
        final task = makeTask('a', future, overdueDays: 1);
        final occurrence = makeOccurrence(task);
        final originalId = ReminderScheduler.notificationId(occurrence.id);
        active.add(delivered(originalId, occurrence.id));
        await scheduler.sync([occurrence]);
        expect(pending.length, greaterThan(1));
        expect(pending.values.map((job) => job['payload']).toSet(), {
          occurrence.id,
        });
        expect(pending, hasLength(scheduler.lastPlan!.jobs.length));
        expect(pending.keys, contains(originalId));
        for (final job in scheduler.lastPlan!.jobs) {
          expect(
            pending.keys,
            contains(ReminderScheduler.notificationId(job.key)),
          );
        }
      });

      test('단일 OS 반복 요청도 표시 중인 실제 ID를 유지', () async {
        final later = DateTime.now().add(const Duration(hours: 1));
        final next = DateTime(
          later.year,
          later.month,
          later.day,
          later.hour,
          later.minute,
        );
        final previous = DateTime(
          next.year,
          next.month,
          next.day - 1,
          next.hour,
          next.minute,
        );
        final task = makeTask('daily', previous, repeat: RepeatUnit.daily);
        const payload = 'repeat:daily:0';
        final actualId = ReminderScheduler.notificationId(payload) + 17;
        active.add(delivered(actualId, payload));
        await scheduler.sync([
          makeOccurrence(task, due: previous),
          makeOccurrence(task, due: next),
        ]);
        expect(cancelled, isEmpty);
        expect(pending.keys.single, actualId);
        expect(pending.values.single['payload'], payload);
        expect(
          pending.values.single['matchDateTimeComponents'],
          DateTimeComponents.time.index,
        );
      });

      test('전달되지 않은 완료 업무의 해시로 다른 업무의 배너를 지우지 않는다', () async {
        const idA = 'task-1gytfkf-1phy';
        const idB = 'task-bd897y-1q43';
        final future = DateTime.now().add(const Duration(hours: 1));
        final completedA = makeOccurrence(
          makeTask('a', future),
          id: idA,
          status: TaskStatus.completed,
        );
        final b = makeOccurrence(makeTask('b', future), id: idB);
        active.add(delivered(ReminderScheduler.notificationId(idB), idB));
        await scheduler.sync([completedA, b]);
        expect(cancelled, isEmpty);
        expect(activePayload(active.single), idB);
        expect(pending.values.single['payload'], idB);
      });

      test('다른 업무의 표시 중인 배너 ID도 새 예약에서 피한다', () async {
        const idA = 'task-1gytfkf-1phy';
        const idB = 'task-bd897y-1q43';
        final past = DateTime.now().subtract(const Duration(hours: 1));
        final future = DateTime.now().add(const Duration(hours: 1));
        final a = makeOccurrence(makeTask('a', past), id: idA);
        final b = makeOccurrence(makeTask('b', future), id: idB);
        final activeId = ReminderScheduler.notificationId(idA);
        active.add(delivered(activeId, idA));
        await scheduler.sync([a, b]);
        expect(cancelled, isEmpty);
        expect(pending, hasLength(1));
        expect(pending.keys.single, isNot(activeId));
        expect(pending.values.single['payload'], idB);
      });

      test('한 업무 삭제 후 나머지 업무의 배너·예약은 유지', () async {
        final future = DateTime.now().add(const Duration(hours: 1));
        final a = makeOccurrence(makeTask('a', future));
        final b = makeOccurrence(makeTask('b', future));
        await scheduler.sync([a, b]);
        active.addAll(pending.values.map(deliverJob));
        final actualA =
            active.singleWhere((job) => activePayload(job) == a.id)['id']
                as int;
        await scheduler.sync([b]);
        expect(cancelled, [actualA]);
        expect(activePayload(active.single), b.id);
        expect(pending.values.single['payload'], b.id);
      });

      if (platform == TargetPlatform.android) {
        test('payload·tag 없는 예전 배너를 추정 ID로 삭제하지 않는다', () async {
          const idA = 'task-1gytfkf-1phy';
          const idB = 'task-bd897y-1q43';
          final future = DateTime.now().add(const Duration(hours: 1));
          final completedA = makeOccurrence(
            makeTask('a', future),
            id: idA,
            status: TaskStatus.completed,
          );
          final b = makeOccurrence(makeTask('b', future), id: idB);
          // A old untagged banner may share a reused ID with a current request.
          // Neither its title nor the current pending payload proves ownership.
          final reusedId = ReminderScheduler.notificationId(idA);
          active.add({'id': reusedId, 'title': b.task.title});
          pending[reusedId] = {'id': reusedId, 'payload': idA};
          await scheduler.sync([completedA, b]);
          expect(cancelled, isEmpty);
          expect(active, hasLength(1));
          expect(pending.values.single['payload'], idB);
          expect(
            (pending.values.single['platformSpecifics'] as Map)['tag'],
            idB,
          );
        });
      }
    });
  }
}
