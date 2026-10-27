import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/snooze_target.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/services/notification_plan.dart';
import 'package:hangeoreum/preview.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('tomorrow keeps scheduled wall clock across month/year boundaries', () {
    expect(
      tomorrowAtScheduledTime(
        DateTime(2025, 1, 1, 12, 35),
        DateTime(2026, 12, 31, 23, 59),
      ),
      DateTime(2027, 1, 1, 12, 35),
    );
    expect(
      tomorrowAtScheduledTime(
        DateTime(2025, 1, 1, 0, 5),
        DateTime(2028, 2, 28, 23),
      ),
      DateTime(2028, 2, 29, 0, 5),
    );
  });
  late TaskRepository repo;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repo = await TaskRepository.open(databasePath: inMemoryDatabasePath);
  });
  tearDown(() async => repo.db.close());

  test('snooze moves one reminder exactly, preserves identity, future recurrence and completion history', () async {
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day, 12);
    await repo.saveTask(
      Task(
        id: 'repeat',
        title: '청소',
        due: due,
        created: now,
        repeat: RepeatUnit.daily,
      ),
    );
    final before = await repo.occurrences();
    final current = before.firstWhere((o) => o.originalDue == due);
    final target = tomorrowAtScheduledTime(due, now);
    await repo.snoozeUntil(current.id, target);
    final after = await repo.occurrences();
    final edited = after.firstWhere((o) => o.id == current.id);
    expect(after.length, before.length);
    expect(edited.originalDue, current.originalDue);
    expect(edited.reminder, target);
    expect(edited.status, TaskStatus.paused);
    expect(edited.snoozes, 1);
    expect(
      after.where((o) => o.id != current.id).map((o) => o.reminder),
      before.where((o) => o.id != current.id).map((o) => o.reminder),
    );
    final plan = NotificationPlan.build(after, now: now, capacity: 60);
    expect(
      plan.jobs.where((j) => j.payload == current.id && j.at == target),
      isNotEmpty,
    );
    await repo.act(current.id, 'complete');
    await repo.snoozeUntil(current.id, target.add(const Duration(days: 1)));
    expect(
      (await repo.occurrences()).firstWhere((o) => o.id == current.id).status,
      TaskStatus.completed,
    );
    expect(await repo.todaySnoozes(current.id), 1);
  });

  test('past snooze cannot mutate data or add an event', () async {
    final now = DateTime.now();
    await repo.saveTask(Task(id: 'one', title: '청소', due: now, created: now));
    final before = (await repo.occurrences()).single;
    await expectLater(
      repo.snoozeUntil(before.id, now.subtract(const Duration(minutes: 1))),
      throwsArgumentError,
    );
    expect((await repo.occurrences()).single.reminder, before.reminder);
    expect(await repo.db.query('events'), isEmpty);
  });

  test(
    'repeated absolute snooze is idempotent but state transitions remain',
    () async {
      final now = DateTime.now();
      final target = now.add(const Duration(days: 1));
      await repo.saveTask(
        Task(id: 'same', title: '청소', due: target, created: now),
      );
      final original = (await repo.occurrences()).single;
      await repo.snoozeUntil(original.id, target);
      await repo.snoozeUntil(original.id, target.toUtc());
      var current = (await repo.occurrences()).single;
      expect(current.status, TaskStatus.paused);
      expect(current.snoozes, 1);
      expect(await repo.todaySnoozes(original.id), 1);
      await repo.act(original.id, 'start');
      current = (await repo.occurrences()).single;
      expect(current.status, TaskStatus.progressing);
      final resumeAt = current.reminder;
      await repo.snoozeUntil(original.id, resumeAt);
      await repo.snoozeUntil(original.id, resumeAt);
      current = (await repo.occurrences()).single;
      expect(current.status, TaskStatus.paused);
      expect(current.snoozes, 2);
      expect(await repo.todaySnoozes(original.id), 2);
      expect(
        await repo.db.query('events', where: 'type=?', whereArgs: ['snooze']),
        hasLength(2),
      );
    },
  );

  test(
    'preview ignores repeated target even when passed an old occurrence',
    () async {
      final controller = PreviewController();
      addTearDown(controller.dispose);
      final now = DateTime.now();
      final target = now.add(const Duration(days: 1));
      await controller.save(
        Task(id: 'same-preview', title: '청소', due: target, created: now),
      );
      final original = controller.items.singleWhere(
        (o) => o.task.id == 'same-preview',
      );
      await controller.snoozeUntil(original, target);
      await controller.snoozeUntil(original, target.toUtc());
      final current = controller.items.singleWhere((o) => o.id == original.id);
      expect(current.status, TaskStatus.paused);
      expect(current.snoozes, 1);
      expect(controller.statistics['snoozes'], 1);
    },
  );
}
