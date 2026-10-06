import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../domain/task.dart';
import '../domain/recurrence.dart';

class TaskRepository {
  final Database db;
  TaskRepository(this.db);
  static Future<TaskRepository> open({String? databasePath}) async {
    final db = await openDatabase(
      databasePath ?? path.join(await getDatabasesPath(), 'hangeoreum.db'),
      singleInstance: false,
      version: 3,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN series_id TEXT NOT NULL DEFAULT ''",
          );
          await db.execute('UPDATE tasks SET series_id=id');
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN derived INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'CREATE TABLE recurrence_exceptions(task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE, original_due TEXT NOT NULL, PRIMARY KEY(task_id,original_due))',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN count_per_week INTEGER NOT NULL DEFAULT 1',
          );
          await db.execute(
            'ALTER TABLE occurrences ADD COLUMN quota_skipped INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        }
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys=ON');
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA busy_timeout=5000');
      },
      onCreate: (db, version) async {
        await db.execute(
          '''CREATE TABLE tasks(id TEXT PRIMARY KEY, title TEXT NOT NULL,
          note TEXT NOT NULL, small_step TEXT NOT NULL, priority INTEGER NOT NULL,
          due TEXT NOT NULL, created TEXT NOT NULL, repeat_unit TEXT NOT NULL,
          repeat_interval INTEGER NOT NULL, weekdays TEXT NOT NULL, end_date TEXT, month_week INTEGER NOT NULL,
          series_id TEXT NOT NULL, derived INTEGER NOT NULL DEFAULT 0,
          count_per_week INTEGER NOT NULL DEFAULT 1)''',
        );
        await db.execute(
          '''CREATE TABLE occurrences(id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
          original_due TEXT NOT NULL, reminder TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending',
          started TEXT, completed TEXT, snoozes INTEGER NOT NULL DEFAULT 0,
          small_active INTEGER NOT NULL DEFAULT 0, before_complete TEXT,
          quota_skipped INTEGER NOT NULL DEFAULT 0, UNIQUE(task_id,original_due))''',
        );
        await db.execute(
          '''CREATE TABLE events(id INTEGER PRIMARY KEY AUTOINCREMENT,
          occurrence_id TEXT NOT NULL REFERENCES occurrences(id) ON DELETE CASCADE,
          type TEXT NOT NULL, at TEXT NOT NULL, minutes INTEGER NOT NULL DEFAULT 0)''',
        );
        await db.execute(
          'CREATE INDEX occurrence_due ON occurrences(original_due)',
        );
        await db.execute('CREATE INDEX event_time ON events(at)');
        await db.execute(
          'CREATE TABLE recurrence_exceptions(task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE, original_due TEXT NOT NULL, PRIMARY KEY(task_id,original_due))',
        );
        await db.execute(
          'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      },
    );
    return TaskRepository(db);
  }

  Future<List<Task>> tasks() async =>
      (await db.query('tasks')).map(Task.fromMap).toList();
  Future<void> saveTask(Task task) async {
    await db.transaction((tx) async {
      final existing = await tx.query(
        'tasks',
        where: 'id=?',
        whereArgs: [task.id],
      );
      if (existing.isEmpty) {
        await tx.insert('tasks', task.toMap());
      } else {
        await tx.update(
          'tasks',
          task.toMap(),
          where: 'id=?',
          whereArgs: [task.id],
        );
        // Editing the series preserves terminal and already-started history.
        await tx.delete(
          'occurrences',
          where: "task_id=? AND state='pending' AND snoozes=0",
          whereArgs: [task.id],
        );
      }
    });
    await materialize();
  }

  Future<void> deleteTask(String id) async {
    final rows = await db.query('tasks', where: 'id=?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await db.delete(
        'tasks',
        where: 'series_id=?',
        whereArgs: [rows.first['series_id']],
      );
    }
  }

  Future<void> deleteOccurrence(
    Occurrence original, {
    required String scope,
  }) async {
    if (scope == 'series') {
      await deleteTask(original.task.id);
      return;
    }
    final cutoff = original.originalDue.toIso8601String();
    await db.transaction((tx) async {
      if (scope == 'this') {
        if (original.task.repeat != RepeatUnit.none) {
          await tx.insert('recurrence_exceptions', {
            'task_id': original.task.id,
            'original_due': cutoff,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await tx.delete('occurrences', where: 'id=?', whereArgs: [original.id]);
        if (original.task.repeat == RepeatUnit.none) {
          await tx.delete(
            'tasks',
            where: 'id=?',
            whereArgs: [original.task.id],
          );
        }
      } else if (scope == 'future') {
        final series = await tx.query(
          'tasks',
          where: 'series_id=?',
          whereArgs: [original.task.seriesId],
        );
        for (final task in series) {
          final previousEnd = task['end_date'] == null
              ? null
              : DateTime.parse(task['end_date'] as String);
          final end = DateTime(
            original.originalDue.year,
            original.originalDue.month,
            original.originalDue.day - 1,
          );
          if (previousEnd == null || previousEnd.isAfter(end)) {
            await tx.update(
              'tasks',
              {'end_date': end.toIso8601String()},
              where: 'id=?',
              whereArgs: [task['id']],
            );
          }
          await tx.delete(
            'occurrences',
            where: 'task_id=? AND original_due>=?',
            whereArgs: [task['id'], cutoff],
          );
          if (DateTime.parse(task['due'] as String)
                  .compareTo(original.originalDue) >=
              0) {
            await tx.delete('tasks', where: 'id=?', whereArgs: [task['id']]);
          }
        }
      } else {
        throw ArgumentError.value(scope, 'scope');
      }
    });
  }

  Future<void> editOccurrence(
    Occurrence original,
    Task edited, {
    required bool onlyThis,
  }) async {
    final source = original.task;
    if (source.repeat == RepeatUnit.none) {
      await saveTask(edited);
      return;
    }
    final replacement = Task.fromMap({
      ...edited.toMap(),
      'id': 't${DateTime.now().microsecondsSinceEpoch}',
      'series_id': source.seriesId,
      'derived': 1,
      if (onlyThis) 'repeat_unit': 'none',
      if (onlyThis) 'end_date': null,
    });
    await db.transaction((tx) async {
      await tx.insert('tasks', replacement.toMap());
      if (onlyThis) {
        await tx.insert('recurrence_exceptions', {
          'task_id': source.id,
          'original_due': original.originalDue.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } else {
        final cutoff = original.originalDue.toIso8601String();
        final end = DateTime(
          original.originalDue.year,
          original.originalDue.month,
          original.originalDue.day - 1,
        );
        final series = await tx.query(
          'tasks',
          where: 'series_id=? AND id<>?',
          whereArgs: [source.seriesId, replacement.id],
        );
        for (final previous in series) {
          final previousEnd = previous['end_date'] == null
              ? null
              : DateTime.parse(previous['end_date'] as String);
          if (previousEnd == null || previousEnd.isAfter(end)) {
            await tx.update(
              'tasks',
              {'end_date': end.toIso8601String()},
              where: 'id=?',
              whereArgs: [previous['id']],
            );
          }
          final rows = await tx.query(
            'occurrences',
            where: 'task_id=? AND original_due>=? AND id<>?',
            whereArgs: [previous['id'], cutoff, original.id],
          );
          for (final row in rows) {
            if ((row['state'] == 'pending' && row['snoozes'] == 0) ||
                row['quota_skipped'] == 1) {
              await tx.delete(
                'occurrences',
                where: 'id=?',
                whereArgs: [row['id']],
              );
            } else {
              // Keep completion/progress events, while the new series takes over
              // untouched future dates and avoids creating the same day's row twice.
              final due = DateTime.parse(row['original_due'] as String);
              if (due != replacement.due) {
                await tx.update(
                  'occurrences',
                  {'task_id': replacement.id},
                  where: 'id=?',
                  whereArgs: [row['id']],
                );
              }
              final newDue = DateTime(
                due.year,
                due.month,
                due.day,
                replacement.due.hour,
                replacement.due.minute,
              );
              await tx.insert('recurrence_exceptions', {
                'task_id': replacement.id,
                'original_due': newDue.toIso8601String(),
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        }
      }
      final newId = '${replacement.id}@${replacement.due.toIso8601String()}';
      final row = (await tx.query(
        'occurrences',
        where: 'id=?',
        whereArgs: [original.id],
      )).first;
      await tx.insert('occurrences', {
        ...row,
        'id': newId,
        'task_id': replacement.id,
        'original_due': replacement.due.toIso8601String(),
        if (original.quotaSkipped) 'state': 'pending',
        if (original.quotaSkipped) 'quota_skipped': 0,
        'reminder':
            original.status == TaskStatus.pending || original.quotaSkipped
            ? replacement.due.toIso8601String()
            : original.reminder.toIso8601String(),
      });
      await tx.update(
        'events',
        {'occurrence_id': newId},
        where: 'occurrence_id=?',
        whereArgs: [original.id],
      );
      await tx.delete('occurrences', where: 'id=?', whereArgs: [original.id]);
    });
    await materialize();
  }

  Future<void> materialize({DateTime? through}) async {
    final now = DateTime.now();
    final until = through ?? DateTime(now.year, now.month + 3, 0);
    final all = await tasks();
    await db.transaction((tx) async {
      for (final t in all) {
        final exceptions = (await tx.query(
          'recurrence_exceptions',
          where: 'task_id=?',
          whereArgs: [t.id],
        )).map((e) => e['original_due']).toSet();
        final cutoff = now.subtract(const Duration(days: 30));
        final from = t.due.isAfter(cutoff) ? t.due : cutoff;
        final first = t.repeat == RepeatUnit.none
            ? null
            : RecurrenceCalculator.next(t, from);
        final next = first != null && first.isAfter(until) ? first : null;
        final dates = t.repeat == RepeatUnit.none
            ? (t.end != null && dayOf(t.due).isAfter(dayOf(t.end!))
                  ? <DateTime>[]
                  : [t.due])
            : next == null
            ? RecurrenceCalculator.between(t, from, until)
            : [next];
        for (final due in dates) {
          if (exceptions.contains(due.toIso8601String())) continue;
          await tx.insert('occurrences', {
            'id': '${t.id}@${due.toIso8601String()}',
            'task_id': t.id,
            'original_due': due.toIso8601String(),
            'reminder': due.toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
    await reconcileWeeklyGoals();
  }

  /// Only automatic quota skips are reversible; a deliberate skip stays skipped.
  Future<void> reconcileWeeklyGoals() async {
    final all = await tasks();
    final goals = {
      for (final t in all.where((t) => t.repeat == RepeatUnit.weeklyGoal))
        t.id: t,
    };
    if (goals.isEmpty) return;
    final byId = {for (final t in all) t.id: t};
    final rows = await db.query('occurrences');
    final completed = <String, int>{};
    for (final row in rows.where((r) => r['state'] == 'completed')) {
      final task = byId[row['task_id']];
      if (task == null) continue;
      final due = DateTime.parse(row['original_due'] as String);
      final key = '${task.seriesId}@${dayKey(weekOf(due))}';
      completed[key] = (completed[key] ?? 0) + 1;
    }
    final today = dayOf(DateTime.now());
    await db.transaction((tx) async {
      for (final row in rows) {
        final task = goals[row['task_id']];
        if (task == null) continue;
        final due = DateTime.parse(row['original_due'] as String);
        if (dayOf(due).isBefore(today)) continue;
        final count = completed['${task.seriesId}@${dayKey(weekOf(due))}'] ?? 0;
        if (count >= task.countPerWeek && row['state'] == 'pending') {
          await tx.update(
            'occurrences',
            {'state': 'skipped', 'quota_skipped': 1},
            where: 'id=?',
            whereArgs: [row['id']],
          );
        } else if (count < task.countPerWeek && row['quota_skipped'] == 1) {
          await tx.update(
            'occurrences',
            {'state': 'pending', 'quota_skipped': 0},
            where: 'id=?',
            whereArgs: [row['id']],
          );
        }
      }
    });
  }

  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where: 'key=?', whereArgs: [key]);
    return rows.firstOrNull?['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, List<DateTime>>> notificationExceptions() async {
    final result = <String, List<DateTime>>{};
    for (final row in await db.query('recurrence_exceptions')) {
      (result[row['task_id'] as String] ??= []).add(
        DateTime.parse(row['original_due'] as String),
      );
    }
    return result;
  }

  /// Coordinates foreground and background notification registration engines.
  Future<bool> acquireReminderLease(String owner) async =>
      db.transaction((tx) async {
        final rows = await tx.query(
          'settings',
          where: 'key=?',
          whereArgs: ['reminder_lease'],
        );
        final until =
            int.tryParse(
              (rows.firstOrNull?['value'] as String? ?? '').split(':').first,
            ) ??
            0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (until > now) return false;
        await tx.insert('settings', {
          'key': 'reminder_lease',
          'value': '${now + 90000}:$owner',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        return true;
      });

  Future<void> releaseReminderLease(String owner) async {
    await db.delete(
      'settings',
      where: 'key=? AND value LIKE ?',
      whereArgs: ['reminder_lease', '%:$owner'],
    );
  }

  Future<List<Occurrence>> occurrences() async {
    final all = {for (final t in await tasks()) t.id: t};
    return (await db.query('occurrences', orderBy: 'original_due'))
        .where((m) => all.containsKey(m['task_id']))
        .map((m) => Occurrence.fromMap(m, all[m['task_id']]!))
        .toList();
  }

  Future<Occurrence?> resolveNotification(String payload) async {
    if (!payload.startsWith('repeat:')) {
      return (await occurrences()).where((o) => o.id == payload).firstOrNull;
    }
    final now = DateTime.now();
    // Repeating requests carry a series id; create today's row even after months away.
    await materialize(through: DateTime(now.year, now.month, now.day + 1));
    return resolveReminderPayload(await occurrences(), payload, now);
  }

  Future<void> act(String id, String action, {int minutes = 10}) async {
    final now = DateTime.now();
    await db.transaction((tx) async {
      final rows = await tx.query(
        'occurrences',
        where: 'id=?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return;
      final m = rows.first, status = m['state'];
      if (action == 'unskip') {
        if (status != 'skipped' || m['quota_skipped'] == 1) return;
        await tx.update(
          'occurrences',
          {'state': 'pending'},
          where: 'id=?',
          whereArgs: [id],
        );
        await tx.delete(
          'events',
          where: "occurrence_id=? AND type='skip'",
          whereArgs: [id],
        );
        return;
      }
      if (action == 'uncomplete') {
        if (status != 'completed') return;
        await tx.update(
          'occurrences',
          {
            'state': m['before_complete'] ?? 'pending',
            'completed': null,
            'before_complete': null,
          },
          where: 'id=?',
          whereArgs: [id],
        );
        await tx.delete(
          'events',
          where: "occurrence_id=? AND type='complete'",
          whereArgs: [id],
        );
        return;
      }
      if (status == 'completed' || status == 'skipped') return;
      final values = <String, Object?>{};
      switch (action) {
        case 'complete':
          values.addAll({
            'state': 'completed',
            'completed': now.toIso8601String(),
            'before_complete': status,
          });
        case 'start':
        case 'small':
          values.addAll({
            'state': 'progressing',
            'started': now.toIso8601String(),
            'small_active': action == 'small' ? 1 : 0,
            'reminder': now
                .add(Duration(minutes: action == 'small' ? 5 : 30))
                .toIso8601String(),
          });
        case 'snooze':
          values.addAll({
            'state': 'paused',
            'reminder': now.add(Duration(minutes: minutes)).toIso8601String(),
            'snoozes': (m['snoozes'] as int) + 1,
          });
        case 'skip':
          values['state'] = 'skipped';
        default:
          return;
      }
      await tx.update('occurrences', values, where: 'id=?', whereArgs: [id]);
      await tx.insert('events', {
        'occurrence_id': id,
        'type': action,
        'at': now.toIso8601String(),
        'minutes': action == 'snooze' ? minutes : 0,
      });
    });
    await reconcileWeeklyGoals();
  }

  Future<int> todaySnoozes(String id) async =>
      Sqflite.firstIntValue(
        await db.rawQuery(
          "SELECT COUNT(*) FROM events WHERE occurrence_id=? AND type='snooze' AND at>=?",
          [id, dayOf(DateTime.now()).toIso8601String()],
        ),
      ) ??
      0;
  Future<Map<String, Object>> stats() async {
    final from = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String();
    final now = DateTime.now().toIso8601String();
    final registered =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM tasks WHERE created>=? AND derived=0',
            [from],
          ),
        ) ??
        0;
    final total =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM occurrences WHERE quota_skipped=0 AND (original_due BETWEEN ? AND ? OR (state='completed' AND completed BETWEEN ? AND ?))",
            [from, now, from, now],
          ),
        ) ??
        0;
    final completed =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM occurrences WHERE completed BETWEEN ? AND ? AND state='completed'",
            [from, now],
          ),
        ) ??
        0;
    final delays = await db.rawQuery(
      "SELECT COUNT(*) count, COALESCE(AVG(minutes),0) average FROM events WHERE type='snooze' AND at>=?",
      [from],
    );
    final hours = await db.rawQuery(
      "SELECT substr(completed,12,2) hour, COUNT(*) count FROM occurrences WHERE completed>=? GROUP BY hour ORDER BY count DESC LIMIT 1",
      [from],
    );
    return {
      'registered': registered,
      'completed': completed,
      'total': total,
      'snoozes': delays.first['count'] ?? 0,
      'average': delays.first['average'] ?? 0,
      'hour': hours.isEmpty ? '기록 없음' : '${hours.first['hour']}시',
    };
  }
}
