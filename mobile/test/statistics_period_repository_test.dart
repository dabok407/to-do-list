import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/statistics_breakdown.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late TaskRepository repository;
  final from = DateTime(2026, 1, 10);
  final until = DateTime(2026, 1, 11).subtract(const Duration(microseconds: 1));

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repository = await TaskRepository.open(databasePath: inMemoryDatabasePath);
  });
  tearDown(() async => repository.db.close());

  Future<void> occurrence(
    String id, {
    required DateTime created,
    required DateTime due,
    DateTime? completed,
    TaskStatus state = TaskStatus.pending,
    bool derived = false,
    bool quotaSkipped = false,
  }) async {
    final task = Task(
      id: id,
      title: id,
      due: due,
      created: created,
      derived: derived,
    );
    await repository.db.insert('tasks', task.toMap());
    await repository.db.insert('occurrences', {
      'id': id,
      'task_id': id,
      'original_due': due.toIso8601String(),
      'reminder': due.toIso8601String(),
      'state': state.name,
      'completed': completed?.toIso8601String(),
      'quota_skipped': quotaSkipped ? 1 : 0,
    });
  }

  Future<void> event(
    String id,
    DateTime at,
    int minutes, {
    String type = 'snooze',
  }) async {
    await repository.db.insert('events', {
      'occurrence_id': id,
      'type': type,
      'at': at.toIso8601String(),
      'minutes': minutes,
    });
  }

  test('all detail queries share the inclusive custom range', () async {
    final before = from.subtract(const Duration(microseconds: 1));
    final after = until.add(const Duration(microseconds: 1));
    await occurrence(
      'at-start',
      created: from,
      due: from,
      completed: DateTime(2026, 1, 10, 10, 15),
      state: TaskStatus.completed,
    );
    await occurrence(
      'at-end',
      created: until,
      due: until,
      completed: until,
      state: TaskStatus.completed,
    );
    await occurrence(
      'late-complete',
      created: before,
      due: before,
      completed: DateTime(2026, 1, 10, 10, 45),
      state: TaskStatus.completed,
    );
    await occurrence(
      'completed-at-start',
      created: before,
      due: before,
      completed: from,
      state: TaskStatus.completed,
    );
    await occurrence('pending', created: before, due: from);
    await occurrence(
      'manual-skip',
      created: before,
      due: until,
      state: TaskStatus.skipped,
    );
    await occurrence(
      'quota-skip',
      created: before,
      due: from,
      state: TaskStatus.skipped,
      quotaSkipped: true,
    );
    await occurrence(
      'derived',
      created: DateTime(2026, 1, 10, 12),
      due: DateTime(2026, 1, 10, 12),
      derived: true,
    );
    await occurrence(
      'previous-day',
      created: before,
      due: before,
      completed: before,
      state: TaskStatus.completed,
    );
    for (var i = 0; i < 4; i++) {
      // More future completions in one hour must not win the selected range's
      // popular-hour query, which previously only had a lower date bound.
      await occurrence(
        'future-$i',
        created: after,
        due: after,
        completed: DateTime(2026, 1, 11, 20, i),
        state: TaskStatus.completed,
      );
    }
    await event('at-start', from, 5);
    await event('at-start', DateTime(2026, 1, 10, 15), 25);
    await event('at-end', until, 30);
    await event('at-start', before, 200);
    await event('at-start', after, 300);
    await event('at-start', DateTime(2026, 1, 10, 16), 100, type: 'complete');

    final statistics = await repository.statsForPeriod(
      from: from,
      until: until,
    );
    expect(
      statistics['registered'],
      2,
      reason: 'Only non-derived tasks created within both boundaries count.',
    );
    expect(statistics['total'], 7);
    expect(statistics['completed'], 4);
    expect(statistics['snoozes'], 3);
    expect(statistics['average'], 20);
    expect(statistics['hour'], '10시');

    final breakdown = StatisticsBreakdown.fromOccurrences(
      await repository.occurrences(),
      now: DateTime(2026, 10, 20),
      from: from,
      until: until,
    );
    expect(breakdown.total, statistics['total']);
    expect(breakdown.completed, statistics['completed']);
  });

  test(
    'empty and adjacent periods never leak registration or delay totals',
    () async {
      await occurrence(
        'source',
        created: from,
        due: from,
        completed: from,
        state: TaskStatus.completed,
      );
      await event('source', from, 30);
      for (final range in [
        [DateTime(2025, 1, 1), DateTime(2025, 1, 2)],
        [DateTime(2026, 1, 11), DateTime(2026, 1, 12)],
      ]) {
        final statistics = await repository.statsForPeriod(
          from: range[0],
          until: range[1],
        );
        expect(statistics['registered'], 0);
        expect(statistics['total'], 0);
        expect(statistics['completed'], 0);
        expect(statistics['snoozes'], 0);
        expect(statistics['average'], 0);
        expect(statistics['hour'], '기록 없음');
      }
    },
  );

  test('a reversed range is rejected before querying', () async {
    await expectLater(
      repository.statsForPeriod(from: until, until: from),
      throwsArgumentError,
    );
  });

  test('a future end cannot include future-dated records', () async {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    await occurrence(
      'already-done',
      created: now.subtract(const Duration(hours: 2)),
      due: now.subtract(const Duration(hours: 1)),
      completed: now.subtract(const Duration(minutes: 30)),
      state: TaskStatus.completed,
    );
    await occurrence(
      'future-done',
      created: tomorrow,
      due: tomorrow,
      completed: tomorrow,
      state: TaskStatus.completed,
    );
    await event('already-done', now.subtract(const Duration(hours: 1)), 10);
    await event('future-done', tomorrow, 90);
    final statistics = await repository.statsForPeriod(
      from: now.subtract(const Duration(days: 1)),
      until: tomorrow,
    );
    expect(statistics['registered'], 1);
    expect(statistics['total'], 1);
    expect(statistics['completed'], 1);
    expect(statistics['snoozes'], 1);
    expect(statistics['average'], 10);
    final breakdown = StatisticsBreakdown.fromOccurrences(
      await repository.occurrences(),
      now: now,
      from: now.subtract(const Duration(days: 1)),
      until: tomorrow,
    );
    expect(breakdown.total, statistics['total']);
    expect(breakdown.completed, statistics['completed']);
  });
}
