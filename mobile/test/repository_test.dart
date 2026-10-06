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
}
