import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ConcurrentReadRepository extends TaskRepository {
  Future<void> Function()? onSnapshot;
  _ConcurrentReadRepository(super.db);

  @override
  Future<List<Task>> tasks() async {
    final snapshot = await super.tasks();
    final action = onSnapshot;
    onSnapshot = null;
    await action?.call();
    return snapshot;
  }
}

void main() {
  late TaskRepository repository;
  late DateTime due;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repository = await TaskRepository.open(databasePath: inMemoryDatabasePath);
    final today = DateTime.now();
    due = DateTime(today.year, today.month, today.day + 1, 12);
  });

  tearDown(() async => repository.db.close());

  Task task({RepeatUnit repeat = RepeatUnit.none}) => Task(
    id: 'filter',
    title: '에어컨 필터 청소',
    due: due,
    created: DateTime.now(),
    repeat: repeat,
  );

  Future<Occurrence> prepare(List<String> actions) async {
    await repository.saveTask(task());
    final original = (await repository.occurrences()).single;
    for (final action in actions) {
      await repository.act(original.id, action, minutes: 30);
    }
    return (await repository.occurrences()).single;
  }

  final scenarios = <String, List<String>>{
    '예정': [],
    '미룸': ['snooze'],
    '진행 중': ['start'],
    '작게 시작': ['small'],
    '완료': ['snooze', 'complete'],
    '건너뜀': ['skip'],
    '완료 해제': ['complete', 'uncomplete'],
  };

  for (final entry in scenarios.entries) {
    for (final delta in [const Duration(hours: 2), const Duration(days: 1)]) {
      test('${entry.key}: 날짜/시간 수정은 같은 일정과 기록을 유지 ($delta)', () async {
        final original = await prepare(entry.value);
        final events = await repository.db.query('events', orderBy: 'id');
        final newDue = due.add(delta);
        final edited = Task.fromMap({
          ...original.task.toMap(),
          'due': newDue.toIso8601String(),
        });

        await repository.saveTask(edited);
        await repository.materialize();
        await repository.saveTask(edited);
        final rows = await repository.occurrences();

        expect(rows, hasLength(1));
        final updated = rows.single;
        expect(updated.id, original.id);
        expect(updated.task.id, original.task.id);
        expect(updated.task.created, original.task.created);
        expect(updated.originalDue, newDue);
        expect(updated.task.due, newDue);
        expect(updated.status, original.status);
        expect(updated.snoozes, original.snoozes);
        expect(updated.started, original.started);
        expect(updated.completed, original.completed);
        expect(updated.beforeComplete, original.beforeComplete);
        expect(updated.smallActive, original.smallActive);
        expect(await repository.db.query('events', orderBy: 'id'), events);
        expect((await repository.stats())['registered'], 1);
        expect(await repository.resolveNotification(original.id), isNotNull);
        if (original.status == TaskStatus.pending ||
            original.status == TaskStatus.paused) {
          expect(updated.reminder, newDue);
        } else {
          expect(updated.reminder, original.reminder);
        }
      });
    }
  }

  test('제목·메모 수정은 미루기 시각과 이력을 초기화하지 않는다', () async {
    final original = await prepare(['snooze']);
    final events = await repository.db.query('events');
    await repository.saveTask(
      Task.fromMap({
        ...original.task.toMap(),
        'title': '새 필터로 교체',
        'note': '규격 확인',
      }),
    );
    final updated = (await repository.occurrences()).single;
    expect(updated.id, original.id);
    expect(updated.reminder, original.reminder);
    expect(updated.snoozes, 1);
    expect(await repository.db.query('events'), events);
  });

  test('반복에서 이번만 분리한 일정도 시간을 다시 수정하면 한 회차만 유지', () async {
    await repository.saveTask(task(repeat: RepeatUnit.daily));
    final original = (await repository.occurrences()).first;
    await repository.editOccurrence(
      original,
      Task.fromMap({
        ...original.task.toMap(),
        'due': due.add(const Duration(hours: 1)).toIso8601String(),
      }),
      onlyThis: true,
    );
    final detached = (await repository.occurrences()).singleWhere(
      (o) => o.task.derived,
    );
    await repository.act(detached.id, 'snooze');
    final changed = due.add(const Duration(hours: 3));
    await repository.editOccurrence(
      detached,
      Task.fromMap({
        ...detached.task.toMap(),
        'due': changed.toIso8601String(),
      }),
      onlyThis: true,
    );
    await repository.materialize();
    final rows = await repository.occurrences();
    final edited = rows.where((o) => o.task.derived).toList();
    expect(edited, hasLength(1));
    expect(edited.single.id, detached.id);
    expect(edited.single.originalDue, changed);
    expect(rows.any((o) => o.id == original.id), false);
    expect((await repository.stats())['registered'], 1);
  });

  test('같은 내용의 독립 일정은 시간을 수정해도 합치거나 삭제하지 않는다', () async {
    final original = await prepare(['snooze']);
    final newDue = due.add(const Duration(hours: 2));
    await repository.saveTask(
      Task.fromMap({
        ...original.task.toMap(),
        'id': 'separate',
        'series_id': 'separate',
        'due': newDue.toIso8601String(),
      }),
    );
    await repository.editOccurrence(
      original,
      Task.fromMap({...original.task.toMap(), 'due': newDue.toIso8601String()}),
      onlyThis: true,
    );
    final all = await repository.occurrences();
    expect(all, hasLength(2));
    expect(all.map((o) => o.task.id).toSet(), {'filter', 'separate'});
    expect(all.every((o) => o.originalDue == newDue), true);
  });

  test('구버전이 만든 미사용 중복은 원래 미루기 이력을 보존하고 정리한다', () async {
    final original = await prepare(['snooze']);
    final events = await repository.db.query('events');
    final staleDue = due.add(const Duration(hours: 2));
    // Reproduce a 1101 save: the task deadline moved but the snoozed row stayed.
    await repository.db.update(
      'tasks',
      {'due': staleDue.toIso8601String()},
      where: 'id=?',
      whereArgs: [original.task.id],
    );
    await repository.materialize();
    expect(await repository.occurrences(), hasLength(2));
    final newDue = due.add(const Duration(hours: 4));
    await repository.saveTask(
      Task.fromMap({...original.task.toMap(), 'due': newDue.toIso8601String()}),
    );
    await repository.materialize();
    final updated = (await repository.occurrences()).single;
    expect(updated.id, original.id);
    expect(updated.status, TaskStatus.paused);
    expect(updated.originalDue, newDue);
    expect(updated.reminder, newDue);
    expect(await repository.db.query('events'), events);
  });

  test('명시한 회차가 삭제되었으면 다른 회차를 수정하거나 새로 만들지 않는다', () async {
    final original = await prepare([]);
    await repository.db.delete(
      'occurrences',
      where: 'id=?',
      whereArgs: [original.id],
    );
    final before = await repository.tasks();
    await expectLater(
      repository.editOccurrence(
        original,
        Task.fromMap({
          ...original.task.toMap(),
          'due': due.add(const Duration(hours: 1)).toIso8601String(),
        }),
        onlyThis: true,
      ),
      throwsStateError,
    );
    expect((await repository.tasks()).single.toMap(), before.single.toMap());
    expect(await repository.occurrences(), isEmpty);
  });

  test('삭제된 회차는 반복 설정을 바꿔 저장해도 다시 생성하지 않는다', () async {
    final original = await prepare([]);
    await repository.db.delete(
      'occurrences',
      where: 'id=?',
      whereArgs: [original.id],
    );
    await expectLater(
      repository.editOccurrence(
        original,
        Task.fromMap({...original.task.toMap(), 'repeat_unit': 'daily'}),
        onlyThis: true,
      ),
      throwsStateError,
    );
    expect((await repository.tasks()).single.repeat, RepeatUnit.none);
    expect(await repository.occurrences(), isEmpty);
  });

  test('백그라운드가 이전 시간을 읽는 도중 재수정해도 옛 회차를 재생성하지 않는다', () async {
    final original = await prepare(['snooze']);
    final firstDue = due.add(const Duration(hours: 2));
    await repository.saveTask(
      Task.fromMap({
        ...original.task.toMap(),
        'due': firstDue.toIso8601String(),
      }),
    );
    final latestDue = due.add(const Duration(hours: 4));
    final background = _ConcurrentReadRepository(repository.db);
    var edited = false;
    background.onSnapshot = () async {
      edited = true;
      await repository.saveTask(
        Task.fromMap({
          ...original.task.toMap(),
          'due': latestDue.toIso8601String(),
        }),
      );
    };
    await background.materialize();
    expect(edited, true);
    await repository.materialize();
    final updated = (await repository.occurrences()).single;
    expect(updated.id, original.id);
    expect(updated.originalDue, latestDue);
    expect(updated.reminder, latestDue);
  });

  test('기존 중복 양쪽에 이력이 있으면 어느 쪽도 자동 삭제하지 않는다', () async {
    final original = await prepare(['snooze']);
    final otherDue = due.add(const Duration(hours: 2));
    final row = (await repository.db.query('occurrences')).single;
    await repository.db.insert('occurrences', {
      ...row,
      'id': 'legacy-second',
      'original_due': otherDue.toIso8601String(),
      'reminder': otherDue.toIso8601String(),
    });
    await repository.db.insert('events', {
      'occurrence_id': 'legacy-second',
      'type': 'snooze',
      'at': DateTime.now().toIso8601String(),
      'minutes': 10,
    });
    final beforeTasks = await repository.db.query('tasks');
    final beforeRows = await repository.db.query('occurrences', orderBy: 'id');
    final beforeEvents = await repository.db.query('events', orderBy: 'id');
    await expectLater(
      repository.editOccurrence(
        original,
        Task.fromMap({
          ...original.task.toMap(),
          'due': otherDue.toIso8601String(),
        }),
        onlyThis: true,
      ),
      throwsStateError,
    );
    expect(await repository.db.query('tasks'), beforeTasks);
    expect(await repository.db.query('occurrences', orderBy: 'id'), beforeRows);
    expect(await repository.db.query('events', orderBy: 'id'), beforeEvents);
  });
}
