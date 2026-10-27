import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import 'task_repository.dart';

/// A portable logical backup; purchases, trial dates, leases and device IDs are
/// deliberately absent. It is not a database file and cannot execute SQL.
class BackupSnapshot {
  static const maxBytes = 20 * 1024 * 1024;
  static const _format = 'todoniq-backup';
  static const _version = 1;
  static const safeSettings = {'display_language', 'notification_show_titles'};
  static const _columns = <String, List<String>>{
    'tasks': [
      'id',
      'title',
      'note',
      'category',
      'small_step',
      'priority',
      'due',
      'created',
      'repeat_unit',
      'repeat_interval',
      'weekdays',
      'end_date',
      'month_week',
      'series_id',
      'derived',
      'count_per_week',
      'overdue_days',
      'overdue_minute',
    ],
    'occurrences': [
      'id',
      'task_id',
      'original_due',
      'reminder',
      'state',
      'started',
      'completed',
      'snoozes',
      'small_active',
      'before_complete',
      'quota_skipped',
    ],
    'events': ['id', 'occurrence_id', 'type', 'at', 'minutes'],
    'recurrence_exceptions': ['task_id', 'original_due'],
    'settings': ['key', 'value'],
  };
  final DateTime createdAt;
  final Map<String, List<Map<String, Object?>>> _rows;
  final String contents;
  int get taskCount => _rows['tasks']!.length;
  int get occurrenceCount => _rows['occurrences']!.length;

  BackupSnapshot._(this.createdAt, this._rows, this.contents);

  static Future<BackupSnapshot> capture(
    TaskRepository repository, {
    DateTime? now,
  }) async {
    final rows = await repository.db.transaction((tx) async {
      final data = <String, Object?>{};
      for (final table in _columns.keys) {
        data[table] = await tx.query(
          table,
          columns: _columns[table],
          where: table == 'settings' ? 'key IN (?,?)' : null,
          whereArgs: table == 'settings' ? safeSettings.toList() : null,
          orderBy: table == 'recurrence_exceptions'
              ? 'task_id, original_due'
              : table == 'settings'
              ? 'key'
              : 'id',
        );
      }
      return data;
    });
    final payload = jsonEncode({
      'createdAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'data': rows,
    });
    // Read back through the same validator used for imports before replacing
    // the previous file; a corrupt database must not destroy a good backup.
    return parse(
      jsonEncode({
        'format': _format,
        'version': _version,
        'payload': payload,
        'sha256': sha256.convert(utf8.encode(payload)).toString(),
      }),
    );
  }

  static BackupSnapshot parse(String contents) {
    try {
      if (contents.length > maxBytes ||
          utf8.encode(contents).length > maxBytes) {
        throw const FormatException('Backup exceeds the size limit');
      }
      final envelope = _map(jsonDecode(contents));
      _keys(envelope, {'format', 'version', 'payload', 'sha256'});
      if (envelope['format'] != _format || envelope['version'] != _version) {
        throw const FormatException('Unsupported backup format or version');
      }
      final payload = _text(envelope, 'payload', maxBytes);
      final digest = sha256.convert(utf8.encode(payload)).toString();
      if (envelope['sha256'] != digest) {
        throw const FormatException('Backup checksum does not match');
      }
      final root = _map(jsonDecode(payload));
      _keys(root, {'createdAt', 'data'});
      final createdAt = _date(root, 'createdAt')!;
      final data = _map(root['data']);
      _keys(data, _columns.keys.toSet());
      final rows = <String, List<Map<String, Object?>>>{};
      var count = 0;
      for (final table in _columns.keys) {
        final raw = data[table];
        if (raw is! List) throw const FormatException('Invalid table');
        count += raw.length;
        if (count > 100000) throw const FormatException('Too many backup rows');
        rows[table] = List.unmodifiable(
          raw.map((value) {
            final row = _map(value);
            _keys(row, _columns[table]!.toSet());
            return Map<String, Object?>.unmodifiable(row);
          }),
        );
      }
      _validate(rows);
      return BackupSnapshot._(createdAt, Map.unmodifiable(rows), contents);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid backup file');
    }
  }

  Future<void> restore(TaskRepository repository) async {
    // All inserts and deletes are one SQLite transaction. A constraint or disk
    // error rolls back to the complete original database, including settings.
    await repository.db.transaction((tx) async {
      for (final table in [
        'events',
        'recurrence_exceptions',
        'occurrences',
        'tasks',
      ]) {
        await tx.delete(table);
      }
      for (final table in [
        'tasks',
        'occurrences',
        'events',
        'recurrence_exceptions',
      ]) {
        for (final row in _rows[table]!) {
          await tx.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }
      for (final row in _rows['settings']!) {
        await tx.insert(
          'settings',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if ((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw const FormatException('Backup references are invalid');
      }
    });
  }

  static void _validate(Map<String, List<Map<String, Object?>>> rows) {
    final taskIds = <String>{};
    for (final row in rows['tasks']!) {
      final id = _text(row, 'id', 1024, nonempty: true);
      if (!taskIds.add(id)) throw const FormatException('Duplicate task');
      _text(row, 'series_id', 1024, nonempty: true);
      _text(row, 'title', 1000, nonempty: true);
      // These editable fields have no smaller application-level length limit.
      // The validated UTF-8 envelope already caps the entire backup at 20 MiB.
      _text(row, 'note', maxBytes);
      _text(row, 'small_step', maxBytes);
      // Older releases stored 운동/공부. Keep those identifiers intact instead
      // of silently rewriting a user's category during a portable restore.
      _choice(row, 'category', {'생활', '업무', '건강', '배움', '기타', '운동', '공부'});
      _choice(row, 'repeat_unit', {
        'none',
        'daily',
        'weekly',
        'monthly',
        'monthlyWeekday',
        'weeklyGoal',
      });
      _integer(row, 'priority', 0, 2);
      _integer(row, 'repeat_interval', 1, 365);
      _integer(row, 'month_week', -1, 5);
      _integer(row, 'count_per_week', 1, 7);
      _integer(row, 'derived', 0, 1);
      _integer(row, 'overdue_days', 0, 3660);
      if (row['overdue_minute'] != null) {
        _integer(row, 'overdue_minute', 0, 1439);
      }
      final weekdays = jsonDecode(_text(row, 'weekdays', 100));
      if (weekdays is! List ||
          weekdays.length > 7 ||
          weekdays.any((day) => day is! int || day < 1 || day > 7) ||
          weekdays.toSet().length != weekdays.length) {
        throw const FormatException('Invalid weekdays');
      }
      _date(row, 'due');
      _date(row, 'created');
      _date(row, 'end_date', optional: true);
    }
    final occurrenceIds = <String>{};
    final dueKeys = <String>{};
    for (final row in rows['occurrences']!) {
      final id = _text(row, 'id', 2048, nonempty: true);
      if (!occurrenceIds.add(id)) {
        throw const FormatException('Duplicate occurrence');
      }
      final taskId = _text(row, 'task_id', 1024, nonempty: true);
      if (!taskIds.contains(taskId)) {
        throw const FormatException('Missing task');
      }
      _date(row, 'original_due');
      _date(row, 'reminder');
      if (!dueKeys.add(jsonEncode([taskId, row['original_due']]))) {
        throw const FormatException('Duplicate task occurrence date');
      }
      _date(row, 'started', optional: true);
      _date(row, 'completed', optional: true);
      const states = {
        'pending',
        'progressing',
        'paused',
        'completed',
        'skipped',
      };
      _choice(row, 'state', states);
      if (row['before_complete'] != null) {
        _choice(row, 'before_complete', states);
      }
      _integer(row, 'snoozes', 0, 1000000);
      _integer(row, 'small_active', 0, 1);
      _integer(row, 'quota_skipped', 0, 1);
    }
    final eventIds = <int>{};
    for (final row in rows['events']!) {
      final id = _integer(row, 'id', 1, 9007199254740991);
      if (!eventIds.add(id)) throw const FormatException('Duplicate event');
      if (!occurrenceIds.contains(_text(row, 'occurrence_id', 2048))) {
        throw const FormatException('Missing occurrence');
      }
      _choice(row, 'type', {
        'start',
        'pause',
        'snooze',
        'small',
        'complete',
        'uncomplete',
        'skip',
        'resume',
      });
      _date(row, 'at');
      _integer(row, 'minutes', 0, 100000000);
    }
    final exceptions = <String>{};
    for (final row in rows['recurrence_exceptions']!) {
      final task = _text(row, 'task_id', 1024);
      if (!taskIds.contains(task)) {
        throw const FormatException('Missing exception task');
      }
      _date(row, 'original_due');
      if (!exceptions.add(jsonEncode([task, row['original_due']]))) {
        throw const FormatException('Duplicate exception');
      }
    }
    final settings = <String>{};
    for (final row in rows['settings']!) {
      final key = _text(row, 'key', 100);
      if (!safeSettings.contains(key) || !settings.add(key)) {
        throw const FormatException('Backup contains an unsupported setting');
      }
      _choice(
        row,
        'value',
        key == 'display_language' ? {'system', 'ko', 'en'} : {'true', 'false'},
      );
    }
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid object');
    }
    return value;
  }

  static void _keys(Map<String, Object?> map, Set<String> keys) {
    if (map.length != keys.length || !map.keys.every(keys.contains)) {
      throw const FormatException('Unexpected backup fields');
    }
  }

  static String _text(
    Map<String, Object?> map,
    String key,
    int max, {
    bool nonempty = false,
  }) {
    final value = map[key];
    if (value is! String ||
        value.length > max ||
        (nonempty && value.trim().isEmpty) ||
        value.contains('\u0000')) {
      throw FormatException('Invalid $key');
    }
    return value;
  }

  static int _integer(Map<String, Object?> map, String key, int min, int max) {
    final value = map[key];
    if (value is! int || value < min || value > max) {
      throw FormatException('Invalid $key');
    }
    return value;
  }

  static void _choice(
    Map<String, Object?> map,
    String key,
    Set<String> values,
  ) {
    if (!values.contains(map[key])) throw FormatException('Invalid $key');
  }

  static DateTime? _date(
    Map<String, Object?> map,
    String key, {
    bool optional = false,
  }) {
    if (optional && map[key] == null) return null;
    final text = _text(map, key, 40);
    final date = DateTime.tryParse(text);
    if (date == null ||
        date.year < 1900 ||
        date.year > 9999 ||
        date.toIso8601String() != text) {
      throw FormatException('Invalid $key');
    }
    return date;
  }
}
