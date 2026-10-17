import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  Task task({String id = 'new-task', String category = '기타', int? priority}) {
    final now = DateTime.now();
    return priority == null
        ? Task(
            id: id,
            title: '분류와 우선순위 확인',
            category: category,
            due: now.add(const Duration(hours: 1)),
            created: now,
          )
        : Task(
            id: id,
            title: '분류와 우선순위 확인',
            category: category,
            priority: priority,
            due: now.add(const Duration(hours: 1)),
            created: now,
          );
  }

  test(
    'new tasks use normal priority while explicit stored priorities survive',
    () {
      expect(task().priority, 1);
      for (final priority in [0, 1, 2]) {
        final saved = task(priority: priority).toMap();
        expect(Task.fromMap(saved).priority, priority);
      }
    },
  );

  test('Other has one stable category key in Korean and English', () {
    expect(taskCategories, ['생활', '업무', '건강', '배움', '기타']);
    expect(const AppStrings('ko').category('기타'), '기타');
    expect(const AppStrings('en').category('기타'), 'Other');
    expect(const AppStrings('en').category('운동'), 'Exercise');
    expect(const AppStrings('en').category('공부'), 'Study');
    expect(const AppStrings('en').category('내 분류'), '내 분류');
    expect(Task.fromMap(task().toMap()).category, '기타');
  });

  group('category and priority persistence', () {
    late TaskRepository repository;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      repository = await TaskRepository.open(
        databasePath: inMemoryDatabasePath,
      );
    });

    tearDown(() async => repository.db.close());

    test(
      'Other is saved and materialized without replacing existing values',
      () async {
        await repository.saveTask(task());
        await repository.saveTask(
          task(id: 'existing-low', category: '생활', priority: 0),
        );
        await repository.saveTask(
          task(id: 'existing-normal', category: '운동', priority: 1),
        );
        await repository.saveTask(
          task(id: 'existing-high', category: '내 분류', priority: 2),
        );
        await repository.materialize();

        final saved = {
          for (final value in await repository.tasks()) value.id: value,
        };
        expect(saved['new-task']?.category, '기타');
        expect(saved['new-task']?.priority, 1);
        expect(saved['existing-low']?.category, '생활');
        expect(saved['existing-low']?.priority, 0);
        expect(saved['existing-normal']?.category, '운동');
        expect(saved['existing-normal']?.priority, 1);
        expect(saved['existing-high']?.category, '내 분류');
        expect(saved['existing-high']?.priority, 2);

        final occurrences = await repository.occurrences();
        expect(occurrences, hasLength(4));
        expect(
          occurrences
              .singleWhere((value) => value.task.id == 'new-task')
              .task
              .category,
          '기타',
        );
      },
    );
  });
}
