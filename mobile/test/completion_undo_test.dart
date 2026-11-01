import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _UndoReminders extends ReminderScheduler {
  List<Occurrence> snapshot = [];
  @override
  Future<void> requestPermissions() async {}
  @override
  Future<bool?> enabled() async => true;
  @override
  Future<void> sync(
    List<Occurrence> items, {
    Map<String, List<DateTime>> exceptions = const {},
  }) async => snapshot = List.of(items);
}

class _UndoWidgets extends WidgetService {
  List<Occurrence> snapshot = [];
  @override
  Future<void> sync(List<Occurrence> items) async => snapshot = List.of(items);
}

void main() {
  late TaskRepository repository;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repository = await TaskRepository.open(databasePath: inMemoryDatabasePath);
  });
  tearDown(() async => repository.db.close());

  Future<Occurrence> find(String id) async =>
      (await repository.occurrences()).singleWhere((o) => o.id == id);

  Future<Occurrence> prepare({String? action}) async {
    final now = DateTime.now();
    await repository.saveTask(
      Task(
        id: 'undo',
        title: '원래 일',
        due: now.add(const Duration(hours: 1)),
        created: now,
      ),
    );
    final original = (await repository.occurrences()).single;
    if (action != null) await repository.act(original.id, action);
    return find(original.id);
  }

  for (final action in <String?>[null, 'snooze', 'start', 'small']) {
    test('완료 Undo는 ${action ?? 'pending'} 상태·알림·진행 기록을 보존', () async {
      final before = await prepare(action: action);
      final events = await repository.db.query('events', orderBy: 'id');
      await repository.act(before.id, 'complete');
      final after = await find(before.id);
      await repository.undoCompletion(before, after);
      final restored = await find(before.id);
      expect(restored.status, before.status);
      expect(restored.completed, before.completed);
      expect(restored.beforeComplete, before.beforeComplete);
      expect(restored.reminder, before.reminder);
      expect(restored.started, before.started);
      expect(restored.snoozes, before.snoozes);
      expect(restored.smallActive, before.smallActive);
      expect(await repository.db.query('events', orderBy: 'id'), events);
    });
  }

  test('완료 해제 Undo는 전날의 원래 완료 시각·이벤트·날짜별 통계를 복원', () async {
    final original = await prepare(action: 'snooze');
    await repository.act(original.id, 'complete');
    final now = DateTime.now();
    final oldTime = DateTime(now.year, now.month, now.day - 1, 23, 59);
    await repository.db.update(
      'occurrences',
      {'completed': oldTime.toIso8601String()},
      where: 'id=?',
      whereArgs: [original.id],
    );
    await repository.db.update(
      'events',
      {'at': oldTime.toIso8601String()},
      where: "occurrence_id=? AND type='complete'",
      whereArgs: [original.id],
    );
    final before = await find(original.id);
    await repository.act(before.id, 'uncomplete');
    final after = await find(before.id);
    await repository.undoCompletion(before, after);
    final restored = await find(before.id);
    expect(restored.status, TaskStatus.completed);
    expect(restored.completed, oldTime);
    expect(restored.beforeComplete, TaskStatus.paused);
    expect(restored.reminder, before.reminder);
    final events = await repository.db.query(
      'events',
      where: "occurrence_id=? AND type='complete'",
      whereArgs: [before.id],
    );
    expect(events, hasLength(1));
    expect(events.single['at'], oldTime.toIso8601String());
    expect(
      (await repository.statsForPeriod(
        from: dayOf(oldTime),
        until: dayOf(now).subtract(const Duration(microseconds: 1)),
      ))['completed'],
      1,
    );
    expect(
      (await repository.statsForPeriod(
        from: dayOf(now),
        until: now.add(const Duration(days: 1)),
      ))['completed'],
      0,
    );
  });

  test('완료 시각 없는 구버전 기록은 Undo가 새 완료 시각을 만들어내지 않음', () async {
    final original = await prepare();
    await repository.db.update(
      'occurrences',
      {'state': 'completed', 'before_complete': 'pending'},
      where: 'id=?',
      whereArgs: [original.id],
    );
    final before = await find(original.id);
    await repository.act(before.id, 'uncomplete');
    await repository.undoCompletion(before, await find(before.id));
    final restored = await find(before.id);
    expect(restored.status, TaskStatus.completed);
    expect(restored.completed, isNull);
    expect(await repository.db.query('events'), isEmpty);
  });

  test('완료→해제→재완료 뒤 옛 Undo는 최신 완료 시각을 덮어쓰지 않음', () async {
    final before = await prepare();
    await repository.act(before.id, 'complete');
    final after = await find(before.id);
    await repository.act(before.id, 'uncomplete');
    await repository.act(before.id, 'complete');
    final current = await find(before.id);
    expect(current.completed, isNot(after.completed));
    final events = await repository.db.query('events');
    await repository.undoCompletion(before, after);
    expect((await find(before.id)).completed, current.completed);
    expect(await repository.db.query('events'), events);
  });

  test('완료 해제 이후 시작한 최신 진행 상태는 옛 Undo로 덮어쓰지 않음', () async {
    final original = await prepare();
    await repository.act(original.id, 'complete');
    final before = await find(original.id);
    await repository.act(before.id, 'uncomplete');
    final after = await find(before.id);
    await repository.act(before.id, 'start');
    final current = await find(before.id);
    await repository.undoCompletion(before, after);
    final restored = await find(before.id);
    expect(restored.status, TaskStatus.progressing);
    expect(restored.started, current.started);
    expect(restored.reminder, current.reminder);
  });

  test('일정 내용이 수정되거나 삭제되면 이전 완료 Undo는 no-op', () async {
    final before = await prepare();
    await repository.act(before.id, 'complete');
    final after = await find(before.id);
    await repository.saveTask(
      Task.fromMap({...after.task.toMap(), 'title': '새로 수정한 일'}),
      occurrenceId: after.id,
    );
    await repository.undoCompletion(before, after);
    expect((await find(before.id)).status, TaskStatus.completed);
    expect((await find(before.id)).task.title, '새로 수정한 일');
    await repository.deleteTask(before.task.id);
    await repository.undoCompletion(before, after);
    expect(await repository.occurrences(), isEmpty);
  });

  test('동일 이전 스냅샷의 동시 완료 요청은 한 번만 실제 적용', () async {
    final before = await prepare();
    final results = await Future.wait([
      repository.transitionCompletion(before, 'complete'),
      repository.transitionCompletion(before, 'complete'),
    ]);
    expect(results.where((applied) => applied), hasLength(1));
    expect(results.where((applied) => !applied), hasLength(1));
    expect((await find(before.id)).status, TaskStatus.completed);
    expect(await repository.db.query('events'), hasLength(1));
  });

  test('다른 엔진이 먼저 완료한 뒤 UI의 옛 요청은 적용하지 않음', () async {
    final before = await prepare();
    await repository.act(before.id, 'complete');
    final external = await find(before.id);
    final events = await repository.db.query('events');
    expect(await repository.transitionCompletion(before, 'complete'), isFalse);
    expect((await find(before.id)).completed, external.completed);
    expect(await repository.db.query('events'), events);
  });

  test('같은 pending 상태라도 제목이 수정되면 이전 완료 요청은 거절', () async {
    final before = await prepare();
    await repository.saveTask(
      Task.fromMap({...before.task.toMap(), 'title': '외부에서 수정한 일'}),
      occurrenceId: before.id,
    );
    expect(await repository.transitionCompletion(before, 'complete'), isFalse);
    expect((await find(before.id)).status, TaskStatus.pending);
    expect(await repository.db.query('events'), isEmpty);
  });

  test('controller는 외부 완료를 새 성공으로 반환하지 않고 최신 목록은 갱신', () async {
    final before = await prepare();
    final reminders = _UndoReminders();
    final widgets = _UndoWidgets();
    final controller = TaskController(repository, reminders, widgets: widgets);
    addTearDown(controller.dispose);
    await controller.refresh();
    await repository.act(before.id, 'complete');
    final completed = await find(before.id);
    await expectLater(controller.act(before, 'complete'), throwsStateError);
    expect(controller.items.single.completed, completed.completed);
    expect(reminders.snapshot.single.completed, completed.completed);
    expect(widgets.snapshot.single.completed, completed.completed);
  });

  test('controller가 거절한 오래된 연속 요청은 최신 완료를 취소하지 않음', () async {
    final before = await prepare();
    final controller = TaskController(
      repository,
      _UndoReminders(),
      widgets: _UndoWidgets(),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    final completion = controller.act(before, 'complete');
    final staleUncomplete = controller.act(before, 'uncomplete');
    await Future.wait([
      completion,
      expectLater(staleUncomplete, throwsStateError),
    ]);
    expect(controller.items.single.status, TaskStatus.completed);
    expect(await repository.db.query('events'), hasLength(1));
  });

  Future<List<Occurrence>> weekly() async {
    final now = DateTime.now();
    final monday = weekOf(now);
    await repository.saveTask(
      Task(
        id: 'weekly',
        title: '주 1회 운동',
        due: DateTime(monday.year, monday.month, monday.day, 12),
        created: now,
        repeat: RepeatUnit.weeklyGoal,
        countPerWeek: 1,
      ),
    );
    return repository.occurrences();
  }

  test('guarded 완료 해제는 목표 충족으로 자동 건너뛰어져도 실제 적용 성공', () async {
    final rows = await weekly();
    final today = dayOf(DateTime.now());
    final target = rows.firstWhere((o) => dayOf(o.originalDue) == today);
    await repository.act(target.id, 'complete');
    final other = rows.firstWhere(
      (o) => o.id != target.id && weekOf(o.originalDue) == weekOf(today),
    );
    // Also possible after lowering a weekly goal with several completions.
    await repository.db.update(
      'occurrences',
      {
        'state': 'completed',
        'completed': DateTime.now().toIso8601String(),
        'quota_skipped': 0,
        'before_complete': 'pending',
      },
      where: 'id=?',
      whereArgs: [other.id],
    );
    final before = await find(target.id);
    expect(await repository.transitionCompletion(before, 'uncomplete'), isTrue);
    final after = await find(target.id);
    expect(after.status, TaskStatus.skipped);
    expect(after.quotaSkipped, isTrue);
    expect(after.completed, isNull);
  });

  test('주간 목표 완료 Undo는 자동 건너뛴 나머지 회차도 복원', () async {
    final initial = await weekly();
    final before = initial.first;
    await repository.act(before.id, 'complete');
    final after = await find(before.id);
    expect((await repository.occurrences()).any((o) => o.quotaSkipped), isTrue);
    await repository.undoCompletion(before, after);
    final restored = await repository.occurrences();
    expect(restored.any((o) => o.quotaSkipped), isFalse);
    expect((await find(before.id)).status, TaskStatus.pending);
  });

  test('주간 목표 완료 해제 Undo는 원래 완료 시각과 목표 건너뛰기를 복원', () async {
    final initial = await weekly();
    final selected = initial.first;
    await repository.act(selected.id, 'complete');
    final before = await find(selected.id);
    await repository.act(before.id, 'uncomplete');
    final after = await find(before.id);
    expect(
      (await repository.occurrences()).any((o) => o.quotaSkipped),
      isFalse,
    );
    await repository.undoCompletion(before, after);
    expect((await find(before.id)).completed, before.completed);
    expect((await repository.occurrences()).any((o) => o.quotaSkipped), isTrue);
  });

  test('주간 목표 복원 실패는 완료 상태와 이벤트까지 원자적으로 롤백', () async {
    final before = (await weekly()).first;
    await repository.act(before.id, 'complete');
    final after = await find(before.id);
    final events = await repository.db.query('events');
    await repository.db.execute('''
      CREATE TRIGGER fail_quota_undo BEFORE UPDATE ON occurrences
      WHEN OLD.task_id='weekly' AND OLD.quota_skipped=1
        AND NEW.quota_skipped=0
      BEGIN SELECT RAISE(ABORT, 'quota restore failed'); END
    ''');
    await expectLater(
      repository.undoCompletion(before, after),
      throwsA(isA<Exception>()),
    );
    expect((await find(before.id)).status, TaskStatus.completed);
    expect((await find(before.id)).completed, after.completed);
    expect(await repository.db.query('events'), events);
  });

  test('controller의 완료·Undo 연속 호출은 목록·알림·위젯을 같은 상태로 유지', () async {
    final before = await prepare(action: 'snooze');
    final reminders = _UndoReminders();
    final widgets = _UndoWidgets();
    final controller = TaskController(repository, reminders, widgets: widgets);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.act(before, 'complete');
    final after = controller.items.single;
    await Future.wait([
      controller.undoCompletion(before, after),
      controller.act(before, 'complete'),
    ]);
    expect(controller.items.single.status, TaskStatus.completed);
    expect(reminders.snapshot.single.status, TaskStatus.completed);
    expect(widgets.snapshot.single.status, TaskStatus.completed);
    await controller.undoCompletion(before, controller.items.single);
    expect(controller.items.single.status, TaskStatus.paused);
    expect(controller.items.single.reminder, before.reminder);
    expect(reminders.snapshot.single.status, TaskStatus.paused);
    expect(widgets.snapshot.single.status, TaskStatus.paused);
  });
}
