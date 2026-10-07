import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('schema 2 upgrade preserves history and enables schema 3 features', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp(
      'schema_migration_',
    );
    final databasePath = path.join(directory.path, 'version_2.db');
    Database? legacy;
    TaskRepository? repository;
    addTearDown(() async {
      if (legacy?.isOpen ?? false) await legacy!.close();
      if (repository?.db.isOpen ?? false) await repository!.db.close();
      await directory.delete(recursive: true);
    });

    final now = DateTime.now();
    final anchor = DateTime(now.year, now.month, now.day - 3, 19);
    final pausedDue = DateTime(now.year, now.month, now.day - 2, 19);
    final exceptionDue = DateTime(now.year, now.month, now.day - 1, 19);
    final task = <String, Object?>{
      'id': 'legacy-task',
      'title': '기존 반복',
      'note': '보존할 메모',
      'small_step': '5분만 시작',
      'priority': 2,
      'due': anchor.toIso8601String(),
      'created': anchor.subtract(const Duration(days: 1)).toIso8601String(),
      'repeat_unit': 'daily',
      'repeat_interval': 1,
      'weekdays': '[]',
      'end_date': exceptionDue.toIso8601String(),
      'month_week': 1,
      'series_id': 'legacy-series',
      'derived': 1,
    };
    final completed = <String, Object?>{
      'id': 'legacy-completed',
      'task_id': task['id'],
      'original_due': anchor.toIso8601String(),
      'reminder': anchor.add(const Duration(minutes: 5)).toIso8601String(),
      'state': 'completed',
      'started': anchor.add(const Duration(minutes: 5)).toIso8601String(),
      'completed': anchor.add(const Duration(minutes: 20)).toIso8601String(),
      'snoozes': 1,
      'small_active': 0,
      'before_complete': 'progressing',
    };
    final paused = <String, Object?>{
      'id': 'legacy-paused',
      'task_id': task['id'],
      'original_due': pausedDue.toIso8601String(),
      'reminder': pausedDue.add(const Duration(minutes: 30)).toIso8601String(),
      'state': 'paused',
      'started': pausedDue.add(const Duration(minutes: 5)).toIso8601String(),
      'completed': null,
      'snoozes': 2,
      'small_active': 1,
      'before_complete': null,
    };
    final events = <Map<String, Object?>>[
      {
        'id': 1,
        'occurrence_id': completed['id'],
        'type': 'start',
        'at': completed['started'],
        'minutes': 0,
      },
      {
        'id': 2,
        'occurrence_id': completed['id'],
        'type': 'complete',
        'at': completed['completed'],
        'minutes': 0,
      },
      {
        'id': 3,
        'occurrence_id': paused['id'],
        'type': 'small',
        'at': paused['started'],
        'minutes': 0,
      },
      {
        'id': 4,
        'occurrence_id': paused['id'],
        'type': 'snooze',
        'at': pausedDue.add(const Duration(minutes: 10)).toIso8601String(),
        'minutes': 30,
      },
    ];
    final exception = <String, Object?>{
      'task_id': task['id'],
      'original_due': exceptionDue.toIso8601String(),
    };

    // This fixture is the old on-disk schema, not a version 3 database with
    // user_version changed. It deliberately has none of the new columns/table.
    legacy = await openDatabase(
      databasePath,
      version: 2,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE tasks(
          id TEXT PRIMARY KEY, title TEXT NOT NULL, note TEXT NOT NULL,
          small_step TEXT NOT NULL, priority INTEGER NOT NULL, due TEXT NOT NULL,
          created TEXT NOT NULL, repeat_unit TEXT NOT NULL,
          repeat_interval INTEGER NOT NULL, weekdays TEXT NOT NULL,
          end_date TEXT, month_week INTEGER NOT NULL, series_id TEXT NOT NULL,
          derived INTEGER NOT NULL DEFAULT 0)''');
        await db.execute('''CREATE TABLE occurrences(
          id TEXT PRIMARY KEY,
          task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
          original_due TEXT NOT NULL, reminder TEXT NOT NULL,
          state TEXT NOT NULL DEFAULT 'pending', started TEXT, completed TEXT,
          snoozes INTEGER NOT NULL DEFAULT 0,
          small_active INTEGER NOT NULL DEFAULT 0, before_complete TEXT,
          UNIQUE(task_id,original_due))''');
        await db.execute('''CREATE TABLE events(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          occurrence_id TEXT NOT NULL REFERENCES occurrences(id) ON DELETE CASCADE,
          type TEXT NOT NULL, at TEXT NOT NULL,
          minutes INTEGER NOT NULL DEFAULT 0)''');
        await db.execute(
          'CREATE INDEX occurrence_due ON occurrences(original_due)',
        );
        await db.execute('CREATE INDEX event_time ON events(at)');
        await db.execute('''CREATE TABLE recurrence_exceptions(
          task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
          original_due TEXT NOT NULL, PRIMARY KEY(task_id,original_due))''');
      },
    );
    await legacy.insert('tasks', task);
    await legacy.insert('occurrences', completed);
    await legacy.insert('occurrences', paused);
    for (final event in events) {
      await legacy.insert('events', event);
    }
    await legacy.insert('recurrence_exceptions', exception);
    expect(await legacy.getVersion(), 2);
    await legacy.close();

    repository = await TaskRepository.open(databasePath: databasePath);
    expect(await repository.db.getVersion(), 3);
    expect(await repository.db.query('tasks'), [
      {...task, 'count_per_week': 1},
    ]);
    final migrated = (await repository.tasks()).single;
    expect(migrated.countPerWeek, 1);
    expect(migrated.seriesId, 'legacy-series');
    expect(migrated.derived, isTrue);
    expect(await repository.db.query('occurrences', orderBy: 'original_due'), [
      {...completed, 'quota_skipped': 0},
      {...paused, 'quota_skipped': 0},
    ]);
    final history = await repository.occurrences();
    expect(history.map((o) => o.status), [
      TaskStatus.completed,
      TaskStatus.paused,
    ]);
    expect(history.every((o) => !o.quotaSkipped), isTrue);
    expect(history.first.beforeComplete, TaskStatus.progressing);
    expect(history.last.smallActive, isTrue);
    expect(await repository.db.query('events', orderBy: 'id'), events);
    expect(await repository.db.query('recurrence_exceptions'), [exception]);
    expect(await repository.notificationExceptions(), {
      'legacy-task': [exceptionDue],
    });
    await repository.materialize();
    expect(await repository.db.query('occurrences', orderBy: 'original_due'), [
      {...completed, 'quota_skipped': 0},
      {...paused, 'quota_skipped': 0},
    ]);

    expect(await repository.setting('last_background_refresh'), isNull);
    await repository.setSetting('last_background_refresh', 'first');
    await repository.setSetting('last_background_refresh', 'persisted');
    expect(await repository.acquireReminderLease('foreground'), isTrue);
    expect(await repository.acquireReminderLease('background'), isFalse);
    await repository.releaseReminderLease('background');
    expect(await repository.acquireReminderLease('background'), isFalse);
    await repository.releaseReminderLease('foreground');
    expect(await repository.acquireReminderLease('background'), isTrue);
    await repository.releaseReminderLease('background');
    await repository.saveTask(
      Task(
        id: 'weekly-goal',
        title: '주 3회 운동',
        due: DateTime(now.year, now.month, now.day, 19),
        created: now,
        repeat: RepeatUnit.weeklyGoal,
        countPerWeek: 3,
      ),
    );
    await repository.db.close();

    repository = await TaskRepository.open(databasePath: databasePath);
    expect(await repository.db.getVersion(), 3);
    final weeklyGoal = (await repository.tasks()).singleWhere(
      (t) => t.id == 'weekly-goal',
    );
    expect(weeklyGoal.repeat, RepeatUnit.weeklyGoal);
    expect(weeklyGoal.countPerWeek, 3);
    expect(await repository.setting('last_background_refresh'), 'persisted');
    expect(await repository.acquireReminderLease('reopened'), isTrue);
    await repository.releaseReminderLease('reopened');
    expect(await repository.db.query('events', orderBy: 'id'), events);
    expect(await repository.db.query('recurrence_exceptions'), [exception]);
    expect(
      (await repository.db.rawQuery('PRAGMA foreign_keys')).single.values.first,
      1,
    );
    expect(await repository.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

    await repository.deleteTask('legacy-task');
    expect((await repository.tasks()).map((t) => t.id), ['weekly-goal']);
    expect(
      await repository.db.query(
        'occurrences',
        where: 'task_id=?',
        whereArgs: ['legacy-task'],
      ),
      isEmpty,
    );
    expect(await repository.db.query('events'), isEmpty);
    expect(await repository.db.query('recurrence_exceptions'), isEmpty);
    expect(await repository.occurrences(), isNotEmpty);
    expect(await repository.setting('last_background_refresh'), 'persisted');
  });
}
