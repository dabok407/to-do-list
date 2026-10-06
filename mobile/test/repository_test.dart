import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';

void main() {
  late TaskRepository repository;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repository = await TaskRepository.open(databasePath: inMemoryDatabasePath);
  });
  tearDown(() async => repository.db.close());
  Task make({RepeatUnit repeat = RepeatUnit.none}) {
    final now = DateTime.now();
    return Task(
      id: 't',
      title: '안방 대청소',
      due: now.subtract(const Duration(minutes: 1)),
      created: now,
      repeat: repeat,
    );
  }

  test('완료 해제는 이전 상태와 통계를 복원하고 원래 시간을 보존', () async {
    await repository.saveTask(make());
    final original = (await repository.occurrences()).single;
    await repository.act(original.id, 'snooze', minutes: 30);
    await repository.act(original.id, 'complete');
    expect((await repository.stats())['completed'], 1);
    await repository.act(original.id, 'uncomplete');
    final restored = (await repository.occurrences()).single;
    expect(restored.status, TaskStatus.paused);
    expect(restored.originalDue, original.originalDue);
    expect(restored.snoozes, 1);
    expect((await repository.stats())['completed'], 0);
    expect((await repository.stats())['average'], 30.0);
  });
  test('반복 materialize는 중복 없이 저장하고 다음 회차가 유지', () async {
    await repository.saveTask(make(repeat: RepeatUnit.daily));
    final before = await repository.occurrences();
    await repository.materialize();
    expect((await repository.occurrences()).length, before.length);
    await repository.act(before.first.id, 'complete');
    expect(
      (await repository.occurrences()).where((o) => o.active).length,
      before.length - 1,
    );
  });
  test('오늘 미루기 횟수와 5분 시작 상태', () async {
    await repository.saveTask(make());
    final id = (await repository.occurrences()).single.id;
    for (var i = 0; i < 3; i++) {
      await repository.act(id, 'snooze');
    }
    expect(await repository.todaySnoozes(id), 3);
    await repository.act(id, 'small');
    final o = (await repository.occurrences()).single;
    expect(o.smallActive, true);
    expect(o.status, TaskStatus.progressing);
    expect(o.reminder.difference(o.started!).inMinutes, 5);
  });
  test('시리즈 삭제 시 회차와 이벤트도 삭제', () async {
    await repository.saveTask(make());
    final id = (await repository.occurrences()).single.id;
    await repository.act(id, 'snooze');
    await repository.deleteTask('t');
    expect(await repository.occurrences(), isEmpty);
    expect(await repository.db.query('events'), isEmpty);
  });
  test('이번 회차 수정은 재생성되지 않고 다음 반복과 등록 수를 유지', () async {
    await repository.saveTask(make(repeat: RepeatUnit.daily));
    final original = (await repository.occurrences()).first;
    final edited = Task.fromMap({
      ...original.task.toMap(),
      'title': '이번만 작은 청소',
      'due': original.originalDue
          .add(const Duration(hours: 2))
          .toIso8601String(),
    });
    await repository.editOccurrence(original, edited, onlyThis: true);
    await repository.materialize();
    final all = await repository.occurrences();
    expect(all.any((o) => o.id == original.id), false);
    expect(all.where((o) => o.task.title == '이번만 작은 청소').length, 1);
    expect(all.where((o) => o.task.id == 't').isNotEmpty, true);
    expect((await repository.stats())['registered'], 1);
    await repository.deleteTask(all.first.task.id);
    expect(await repository.occurrences(), isEmpty);
  });
  test('앞으로 수정은 지난 완료를 보존하고 이후 규칙을 분리', () async {
    await repository.saveTask(make(repeat: RepeatUnit.daily));
    final before = await repository.occurrences();
    await repository.act(before.first.id, 'complete');
    final selected = before[1];
    final edited = Task.fromMap({
      ...selected.task.toMap(),
      'due': selected.originalDue.toIso8601String(),
      'title': '새 반복',
    });
    await repository.editOccurrence(selected, edited, onlyThis: false);
    final all = await repository.occurrences();
    expect(
      all.firstWhere((o) => o.id == before.first.id).status,
      TaskStatus.completed,
    );
    expect(
      all.where(
        (o) => o.task.id == 't' && o.originalDue.isAfter(selected.originalDue),
      ),
      isEmpty,
    );
    expect(all.where((o) => o.task.title == '새 반복').length, greaterThan(1));
    expect((await repository.stats())['registered'], 1);
  });
  test('예정 시간 전에 완료한 일도 완료 수와 분모에 포함', () async {
    final t = make();
    await repository.saveTask(
      Task.fromMap({
        ...t.toMap(),
        'due': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      }),
    );
    await repository.act(
      (await repository.occurrences()).single.id,
      'complete',
    );
    final stats = await repository.stats();
    expect(stats['completed'], 1);
    expect(stats['total'], 1);
  });
  test('요일 자유 주 2회 목표 달성 및 완료 해제는 남은 알림 후보를 복원', () async {
    final monday = weekOf(DateTime.now());
    await repository.saveTask(
      Task(
        id: 'goal',
        title: '주 2회 운동',
        due: DateTime(monday.year, monday.month, monday.day, 19),
        created: DateTime.now(),
        repeat: RepeatUnit.weeklyGoal,
        countPerWeek: 2,
      ),
    );
    final week = (await repository.occurrences())
        .where((o) => weekOf(o.originalDue) == monday)
        .toList();
    await repository.act(week[0].id, 'complete');
    await repository.act(week[1].id, 'complete');
    final achieved = await repository.occurrences();
    expect(achieved.where((o) => o.quotaSkipped).isNotEmpty, true);
    expect(
      achieved.where(
        (o) =>
            weekOf(o.originalDue) ==
                DateTime(monday.year, monday.month, monday.day + 7) &&
            o.active,
      ),
      isNotEmpty,
    );
    await repository.act(week[1].id, 'uncomplete');
    final restored = await repository.occurrences();
    expect(restored.where((o) => o.quotaSkipped), isEmpty);
    expect(restored.singleWhere((o) => o.id == week[1].id).active, true);
  });
  test('사용자가 건너뛴 주간 목표 회차는 목표 해제 때 복원하지 않음', () async {
    final today = dayOf(DateTime.now());
    await repository.saveTask(
      Task(
        id: 'goal',
        title: '운동',
        due: today,
        created: today,
        repeat: RepeatUnit.weeklyGoal,
      ),
    );
    final first = (await repository.occurrences()).first;
    await repository.act(first.id, 'skip');
    await repository.reconcileWeeklyGoals();
    final skipped = (await repository.occurrences()).first;
    expect(skipped.status, TaskStatus.skipped);
    expect(skipped.quotaSkipped, false);
  });
  test('foreground/background 알림 예약 lease는 서로 덮어쓰지 않음', () async {
    expect(await repository.acquireReminderLease('ui'), true);
    expect(await repository.acquireReminderLease('background'), false);
    await repository.releaseReminderLease('background');
    expect(await repository.acquireReminderLease('background'), false);
    await repository.releaseReminderLease('ui');
    expect(await repository.acquireReminderLease('background'), true);
  });
  test('OS 반복 알림 payload는 현재 회차를 찾아 완료 기록을 남김', () async {
    await repository.saveTask(make(repeat: RepeatUnit.daily));
    final o = await repository.resolveNotification('repeat:t');
    expect(o, isNotNull);
    expect(dayOf(o!.originalDue), dayOf(DateTime.now()));
    await repository.act(o.id, 'complete');
    expect(
      (await repository.occurrences())
          .singleWhere((item) => item.id == o.id)
          .status,
      TaskStatus.completed,
    );
  });
  test('미래 이번만 수정 후 그 이전에서 앞으로 수정하면 회차가 중복되지 않음', () async {
    final anchor = dayOf(DateTime.now());
    await repository.saveTask(
      Task(
        id: 'r',
        title: '매일 청소',
        due: DateTime(anchor.year, anchor.month, anchor.day, 19),
        created: anchor,
        repeat: RepeatUnit.daily,
      ),
    );
    var all = await repository.occurrences();
    final exception = all[5];
    await repository.editOccurrence(
      exception,
      Task.fromMap({
        ...exception.task.toMap(),
        'due': exception.originalDue.toIso8601String(),
        'title': '이번만 다른 청소',
      }),
      onlyThis: true,
    );
    all = await repository.occurrences();
    final split = all.firstWhere(
      (o) =>
          dayOf(o.originalDue) ==
          DateTime(anchor.year, anchor.month, anchor.day + 2),
    );
    await repository.editOccurrence(
      split,
      Task.fromMap({
        ...split.task.toMap(),
        'due': split.originalDue.toIso8601String(),
        'title': '앞으로 새 청소',
      }),
      onlyThis: false,
    );
    await repository.materialize();
    final day = (await repository.occurrences())
        .where((o) => dayOf(o.originalDue) == dayOf(exception.originalDue))
        .toList();
    expect(day, hasLength(1));
    expect(day.single.task.title, '앞으로 새 청소');
  });
  test('반복 이번 회차 삭제와 앞으로 삭제는 이전 기록을 유지', () async {
    await repository.saveTask(make(repeat: RepeatUnit.daily));
    final all = await repository.occurrences();
    await repository.act(all.first.id, 'complete');
    await repository.deleteOccurrence(all[1], scope: 'this');
    await repository.materialize();
    expect(
      (await repository.occurrences()).any((o) => o.id == all[1].id),
      false,
    );
    await repository.deleteOccurrence(all[3], scope: 'future');
    await repository.materialize();
    final retained = await repository.occurrences();
    expect(
      retained.singleWhere((o) => o.id == all.first.id).status,
      TaskStatus.completed,
    );
    expect(
      retained.any((o) => !o.originalDue.isBefore(all[3].originalDue)),
      false,
    );
  });
  test('장기 미래에 시작하는 반복도 예정 목록에 첫 회차를 표시', () async {
    final now = DateTime.now();
    final future = DateTime(now.year, now.month + 6, 15, 19);
    await repository.saveTask(
      Task(
        id: 'future',
        title: '6개월 뒤 반복',
        due: future,
        created: now,
        repeat: RepeatUnit.daily,
      ),
    );
    expect((await repository.occurrences()).single.originalDue, future);
  });
  test('지난 주간 알림을 다시 눌러도 완료한 최신 회차 대신 이전 회차를 변경하지 않음', () async {
    await repository.saveTask(make(repeat: RepeatUnit.daily));
    final today = (await repository.occurrences()).first;
    await repository.act(today.id, 'complete');
    final resolved = await repository.resolveNotification('repeat:t:0');
    expect(resolved?.status, TaskStatus.completed);
  });
}
