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
      version: 1,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys=ON'),
      onCreate: (db, version) async {
        await db.execute(
          '''CREATE TABLE tasks(id TEXT PRIMARY KEY, title TEXT NOT NULL,
          note TEXT NOT NULL, small_step TEXT NOT NULL, priority INTEGER NOT NULL,
          due TEXT NOT NULL, created TEXT NOT NULL, repeat_unit TEXT NOT NULL,
          repeat_interval INTEGER NOT NULL, weekdays TEXT NOT NULL, end_date TEXT, month_week INTEGER NOT NULL)''',
        );
        await db.execute(
          '''CREATE TABLE occurrences(id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
          original_due TEXT NOT NULL, reminder TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending',
          started TEXT, completed TEXT, snoozes INTEGER NOT NULL DEFAULT 0,
          small_active INTEGER NOT NULL DEFAULT 0, before_complete TEXT, UNIQUE(task_id,original_due))''',
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

  Future<void> deleteTask(String id) async =>
      db.delete('tasks', where: 'id=?', whereArgs: [id]);
  Future<void> materialize({DateTime? through}) async {
    final now = DateTime.now();
    final until = through ?? DateTime(now.year, now.month + 3, 0);
    final all = await tasks();
    await db.transaction((tx) async {
      for (final t in all) {
        final cutoff = now.subtract(const Duration(days: 30));
        final from = t.due.isAfter(cutoff) ? t.due : cutoff;
        final dates = t.repeat == RepeatUnit.none
            ? [t.due]
            : RecurrenceCalculator.between(t, from, until);
        for (final due in dates) {
          await tx.insert('occurrences', {
            'id': '${t.id}@${due.toIso8601String()}',
            'task_id': t.id,
            'original_due': due.toIso8601String(),
            'reminder': due.toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
  }

  Future<List<Occurrence>> occurrences() async {
    final all = {for (final t in await tasks()) t.id: t};
    return (await db.query('occurrences', orderBy: 'original_due'))
        .where((m) => all.containsKey(m['task_id']))
        .map((m) => Occurrence.fromMap(m, all[m['task_id']]!))
        .toList();
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
          await db.rawQuery('SELECT COUNT(*) FROM tasks WHERE created>=?', [
            from,
          ]),
        ) ??
        0;
    final total =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM occurrences WHERE original_due BETWEEN ? AND ?',
            [from, now],
          ),
        ) ??
        0;
    final completed =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM occurrences WHERE original_due BETWEEN ? AND ? AND state='completed'",
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
