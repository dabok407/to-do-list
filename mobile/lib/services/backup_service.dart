import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../data/backup_snapshot.dart';
import '../data/task_repository.dart';
import 'backup_storage.dart';

export '../data/backup_snapshot.dart';

class BackupStatus {
  final bool enabled, hasBackup, invalidBackup;
  final DateTime? lastBackupAt;
  const BackupStatus({
    required this.enabled,
    required this.hasBackup,
    this.lastBackupAt,
    this.invalidBackup = false,
  });
}

/// Backups never depend on a paid subscription and do not change purchase or
/// trial state. Call [maybeAutomaticBackup] on startup/resume and permitted OS
/// background refreshes. Neither mobile OS guarantees an exact weekly run.
class BackupService {
  static const automaticKey = 'automatic_backup_enabled';
  static const interval = Duration(days: 7);
  static const _channel = MethodChannel('com.dabok407.hangeoreum/backup');
  final TaskRepository repository;
  final BackupStorage storage;
  final DateTime Function() clock;
  DateTime? _validatedLatestAt;

  BackupService(
    this.repository, {
    BackupStorage? storage,
    DateTime Function()? clock,
  }) : storage = storage ?? createBackupStorage(() => repository.db.path),
       clock = clock ?? DateTime.now;

  bool get available => storage.supported;

  Future<BackupStatus> loadStatus() async {
    if (!available) return const BackupStatus(enabled: false, hasBackup: false);
    final enabled = await repository.setting(automaticKey) == 'true';
    try {
      final snapshot = await latestBackup();
      return BackupStatus(
        enabled: enabled,
        hasBackup: snapshot != null,
        lastBackupAt: snapshot?.createdAt,
      );
    } on FormatException {
      return BackupStatus(
        enabled: enabled,
        hasBackup: false,
        invalidBackup: true,
      );
    }
  }

  Future<BackupSnapshot?> latestBackup() async {
    // Explicit status/restore reads always revalidate. Clearing before I/O also
    // prevents an observed missing/corrupt file from retaining a fresh cache.
    _validatedLatestAt = null;
    final text = await storage.readLatest();
    final snapshot = text == null ? null : BackupSnapshot.parse(text);
    _validatedLatestAt = snapshot?.createdAt;
    return snapshot;
  }

  Future<void> setAutomatic(bool enabled) async {
    _requireAvailable();
    await _leased(() async {
      // Enabling only succeeds after a real initial backup has been written.
      if (enabled) await _create();
      await repository.setSetting(automaticKey, '$enabled');
    });
  }

  Future<BackupSnapshot> createBackup() async {
    _requireAvailable();
    return _leased(_create);
  }

  Future<BackupSnapshot> _create() async {
    final snapshot = await BackupSnapshot.capture(repository, now: clock());
    await storage.writeLatest(snapshot.contents);
    _validatedLatestAt = snapshot.createdAt;
    return snapshot;
  }

  Future<bool> maybeAutomaticBackup() async {
    if (!available || await repository.setting(automaticKey) != 'true') {
      return false;
    }
    // Foreground reconcile can run every minute. A snapshot validated/written
    // by this service is enough until it is due, avoiding a full JSON read and
    // a database lease on every tick. New engines and explicit status reads
    // still read the file; once due we recheck under the cross-engine lease.
    final validatedAt = _validatedLatestAt;
    if (validatedAt != null &&
        clock().toUtc().difference(validatedAt) < interval) {
      return false;
    }
    try {
      return await _leased(() async {
        // Recheck after taking the cross-engine lease (the user may have just
        // switched it off while a background worker was waiting).
        if (await repository.setting(automaticKey) != 'true') return false;
        BackupSnapshot? latest;
        try {
          latest = await latestBackup();
        } on FormatException {
          /* Replace invalid local backup. */
        }
        if (latest != null &&
            clock().toUtc().difference(latest.createdAt) < interval) {
          return false;
        }
        await _create();
        return true;
      });
    } on BackupBusyException {
      return false;
    }
  }

  /// Native document picker lets the user choose a destination, including an
  /// external provider if they explicitly choose one. Automatic backups stay
  /// only inside the app's local private directory.
  Future<bool> exportBackup() async {
    final snapshot = await createBackup();
    return await _channel.invokeMethod<bool>('export', {
          'contents': snapshot.contents,
          'filename': 'Todoniq-backup.json',
        }) ??
        false;
  }

  Future<BackupSnapshot?> pickBackup() async {
    _requireAvailable();
    final contents = await _channel.invokeMethod<String>('import');
    return contents == null ? null : BackupSnapshot.parse(contents);
  }

  /// Host confirms replacement before this method and refreshes locale,
  /// notifications and widgets after it. Validation has already happened in
  /// [BackupSnapshot.parse], and SQLite restores all rows atomically.
  Future<void> restore(BackupSnapshot snapshot) async {
    _requireAvailable();
    await _leased(() => snapshot.restore(repository));
  }

  void _requireAvailable() {
    if (!available) {
      throw UnsupportedError('Local backups require the installed app');
    }
  }

  Future<T> _leased<T>(Future<T> Function() action) async {
    final owner = '${clock().microsecondsSinceEpoch}-${identityHashCode(this)}';
    final acquired = await repository.db.transaction((tx) async {
      final rows = await tx.query(
        'settings',
        where: 'key=?',
        whereArgs: ['backup_lease'],
      );
      final value = rows.firstOrNull?['value'] as String? ?? '';
      final expiry = int.tryParse(value.split(':').first) ?? 0;
      // Real elapsed wall time is used for inter-engine locks, even in tests
      // that override the scheduler clock.
      final now = DateTime.now().millisecondsSinceEpoch;
      if (expiry > now) return false;
      await tx.insert('settings', {
        'key': 'backup_lease',
        'value': '${now + 120000}:$owner',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
    if (!acquired) throw const BackupBusyException();
    try {
      return await action();
    } finally {
      await repository.db.delete(
        'settings',
        where: 'key=? AND value LIKE ?',
        whereArgs: ['backup_lease', '%:$owner'],
      );
    }
  }
}

class BackupBusyException implements Exception {
  const BackupBusyException();
}
