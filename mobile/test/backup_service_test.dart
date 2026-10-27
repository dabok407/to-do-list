import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/services/backup_service.dart';
import 'package:hangeoreum/services/backup_storage.dart';
import 'package:hangeoreum/services/backup_storage_io.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FailingStorage extends MemoryBackupStorage {
  bool fail = false;
  Completer<void>? wait;
  @override
  Future<void> writeLatest(String contents) async {
    if (fail) throw FileSystemException('Disk full');
    await wait?.future;
    await super.writeLatest(contents);
  }
}

class CountingStorage extends MemoryBackupStorage {
  int reads = 0;
  @override
  Future<String?> readLatest() async {
    reads++;
    return super.readLatest();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TaskRepository repository;
  late DateTime now;
  late MemoryBackupStorage storage;
  late BackupService service;
  const channel = MethodChannel('com.dabok407.hangeoreum/backup');
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repository = await TaskRepository.open(databasePath: inMemoryDatabasePath);
    now = DateTime.utc(2026, 10, 26, 12);
    storage = MemoryBackupStorage();
    service = BackupService(repository, storage: storage, clock: () => now);
    await repository.saveTask(
      Task(id: 'ac', title: '필터 청소', due: now, created: now, note: '완전히 말리기'),
    );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await repository.db.close();
  });

  Future<List<Map<String, Object?>>> table(String name) =>
      repository.db.query(name);
  Future<BackupSnapshot> capture() =>
      BackupSnapshot.capture(repository, now: now);
  String alter(
    BackupSnapshot snapshot,
    void Function(Map<String, dynamic>) modify,
  ) {
    final envelope = jsonDecode(snapshot.contents) as Map<String, dynamic>;
    final payload =
        jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
    modify(payload);
    envelope['payload'] = jsonEncode(payload);
    envelope['sha256'] = sha256
        .convert(utf8.encode(envelope['payload'] as String))
        .toString();
    return jsonEncode(envelope);
  }

  test('round trip preserves tasks, completion history, exceptions and safe preferences', () async {
    final original = (await repository.occurrences()).single;
    await repository.act(original.id, 'snooze', minutes: 30);
    await repository.act(original.id, 'complete');
    await repository.db.insert('recurrence_exceptions', {
      'task_id': 'ac',
      'original_due': now.add(const Duration(days: 2)).toIso8601String(),
    });
    await repository.setSetting('display_language', 'en');
    await repository.setSetting('notification_show_titles', 'false');
    final before = {
      for (final name in [
        'tasks',
        'occurrences',
        'events',
        'recurrence_exceptions',
      ])
        name: await table(name),
    };
    final snapshot = await capture();
    expect(snapshot.taskCount, 1);
    expect(snapshot.occurrenceCount, 1);
    await repository.deleteTask('ac');
    await repository.setSetting('display_language', 'ko');
    await service.restore(BackupSnapshot.parse(snapshot.contents));
    for (final name in before.keys) {
      expect(await table(name), before[name]);
    }
    expect(await repository.setting('display_language'), 'en');
    expect(await repository.setting('notification_show_titles'), 'false');
  });

  test(
    'backup and restore never copy purchase, trial, device or lease settings',
    () async {
      for (final key in [
        'trial_started',
        'subscription',
        'device_id',
        'reminder_lease',
        BackupService.automaticKey,
      ]) {
        await repository.setSetting(key, 'BEFORE-$key');
      }
      final snapshot = await capture();
      expect(snapshot.contents, isNot(contains('BEFORE-')));
      for (final key in [
        'trial_started',
        'subscription',
        'device_id',
        'reminder_lease',
        BackupService.automaticKey,
      ]) {
        await repository.setSetting(key, 'AFTER-$key');
      }
      await service.restore(snapshot);
      for (final key in [
        'trial_started',
        'subscription',
        'device_id',
        'reminder_lease',
        BackupService.automaticKey,
      ]) {
        expect(await repository.setting(key), 'AFTER-$key');
      }
    },
  );

  test(
    'legacy exercise and study categories survive a full round trip',
    () async {
      for (final category in ['운동', '공부']) {
        await repository.saveTask(
          Task(
            id: category,
            title: '$category 기록',
            category: category,
            due: now,
            created: now,
          ),
        );
      }
      final snapshot = await capture();
      await repository.deleteTask('운동');
      await repository.deleteTask('공부');
      await service.restore(BackupSnapshot.parse(snapshot.contents));
      final tasks = {
        for (final task in await repository.tasks()) task.id: task,
      };
      expect(tasks['운동']!.category, '운동');
      expect(tasks['공부']!.category, '공부');
      expect((await repository.occurrences()).length, 3);
    },
  );

  test('long notes and small steps survive a full backup round trip', () async {
    final note = List.filled(100001, '메').join();
    final smallStep = List.filled(100001, '시').join();
    await repository.saveTask(
      Task(
        id: 'long-text',
        title: '긴 메모',
        due: now,
        created: now,
        note: note,
        smallStep: smallStep,
      ),
    );
    final snapshot = await capture();
    await repository.deleteTask('long-text');
    await service.restore(BackupSnapshot.parse(snapshot.contents));
    final restored = (await repository.tasks()).singleWhere(
      (task) => task.id == 'long-text',
    );
    expect(restored.note, note);
    expect(restored.smallStep, smallStep);
  });

  test('checksum catches truncated and silently changed data', () async {
    final snapshot = await capture();
    expect(
      () => BackupSnapshot.parse(snapshot.contents.substring(0, 100)),
      throwsFormatException,
    );
    expect(
      () => BackupSnapshot.parse(snapshot.contents.replaceAll('필터', '변경')),
      throwsFormatException,
    );
    final envelope = jsonDecode(snapshot.contents) as Map<String, dynamic>;
    envelope['version'] = 999;
    expect(
      () => BackupSnapshot.parse(jsonEncode(envelope)),
      throwsFormatException,
    );
  });

  test('rehashed invalid fields, dates, references and settings are still rejected', () async {
    final snapshot = await capture();
    final changes = <void Function(Map<String, dynamic>)>[
      (root) => (root['data']['settings'] as List).add({
        'key': 'subscription',
        'value': 'pro',
      }),
      (root) => root['data']['occurrences'][0]['task_id'] = 'missing',
      (root) => root['data']['tasks'][0]['due'] = '2026-13-01T12:00:00.000',
      (root) => root['data']['tasks'][0]['priority'] = 99,
      (root) => root['data']['tasks'][0]['category'] = 'unknown-category',
      (root) => root['data']['tasks'][0]['repeat_interval'] = 9999999,
      (root) => root['data']['tasks'][0]['injected_column'] = 'bad',
      (root) => (root['data']['tasks'] as List).add(
        Map<String, dynamic>.from(root['data']['tasks'][0]),
      ),
      (root) => root['data']['occurrences'][0]['state'] = 'executed',
    ];
    for (final change in changes) {
      expect(
        () => BackupSnapshot.parse(alter(snapshot, change)),
        throwsFormatException,
      );
    }
    expect((await repository.tasks()).single.title, '필터 청소');
  });

  test(
    'restore SQL failure rolls back every deleted row and preference',
    () async {
      final snapshot = await capture();
      await repository.saveTask(
        Task(id: 'later', title: '나중 기록', due: now, created: now),
      );
      final original = await table('tasks');
      await repository.db.execute(
        "CREATE TRIGGER fail_restore BEFORE INSERT ON tasks BEGIN SELECT RAISE(ABORT, 'simulated disk error'); END",
      );
      await expectLater(
        service.restore(snapshot),
        throwsA(isA<DatabaseException>()),
      );
      expect(await table('tasks'), original);
      expect((await repository.occurrences()).length, 2);
      expect(await repository.setting('backup_lease'), isNull);
    },
  );

  test('automatic is off by default, creates initial file and replaces only after seven days', () async {
    expect((await service.loadStatus()).enabled, false);
    expect(await service.maybeAutomaticBackup(), false);
    await service.setAutomatic(true);
    final first = storage.contents;
    expect((await service.loadStatus()).lastBackupAt, now);
    now = now.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
    expect(await service.maybeAutomaticBackup(), false);
    expect(storage.contents, first);
    now = now.add(const Duration(seconds: 1));
    expect(await service.maybeAutomaticBackup(), true);
    expect(storage.contents, isNot(first));
    expect((await service.loadStatus()).lastBackupAt, now);
    await service.setAutomatic(false);
    now = now.add(const Duration(days: 100));
    expect(await service.maybeAutomaticBackup(), false);
  });

  test('clock moving backwards does not replace latest backup', () async {
    await service.setAutomatic(true);
    final previous = storage.contents;
    now = now.subtract(const Duration(days: 1));
    expect(await service.maybeAutomaticBackup(), false);
    expect(storage.contents, previous);
  });

  test(
    'minute checks reuse validated backup time and recheck at weekly boundary',
    () async {
      final file = CountingStorage();
      final backups = BackupService(
        repository,
        storage: file,
        clock: () => now,
      );
      await backups.setAutomatic(true);
      final initialTime = now;
      for (var minute = 1; minute <= 60; minute++) {
        now = initialTime.add(Duration(minutes: minute));
        expect(await backups.maybeAutomaticBackup(), false);
      }
      expect(file.reads, 0);
      // A new foreground/background engine validates once, then uses its cache.
      final restarted = BackupService(
        repository,
        storage: file,
        clock: () => now,
      );
      expect(await restarted.maybeAutomaticBackup(), false);
      expect(file.reads, 1);
      expect(await restarted.maybeAutomaticBackup(), false);
      expect(file.reads, 1);
      now = initialTime.add(const Duration(days: 7));
      expect(await restarted.maybeAutomaticBackup(), true);
      expect(file.reads, 2);
      expect(await restarted.maybeAutomaticBackup(), false);
      expect(file.reads, 2);
      expect(await repository.setting('backup_lease'), isNull);
    },
  );

  test(
    'explicit status validation invalidates cached corrupt backup',
    () async {
      await service.setAutomatic(true);
      storage.contents = 'broken';
      expect((await service.loadStatus()).invalidBackup, true);
      expect(await service.maybeAutomaticBackup(), true);
      expect((await service.latestBackup())!.taskCount, 1);
    },
  );

  test('failed initial or weekly write does not claim success or destroy previous backup', () async {
    final file = FailingStorage()..fail = true;
    final backups = BackupService(repository, storage: file, clock: () => now);
    await expectLater(
      backups.setAutomatic(true),
      throwsA(isA<FileSystemException>()),
    );
    expect(await repository.setting(BackupService.automaticKey), isNull);
    file.fail = false;
    await backups.setAutomatic(true);
    final good = file.contents;
    now = now.add(const Duration(days: 8));
    file.fail = true;
    await expectLater(
      backups.maybeAutomaticBackup(),
      throwsA(isA<FileSystemException>()),
    );
    expect(file.contents, good);
    expect(await repository.setting('backup_lease'), isNull);
  });

  test(
    'cross service lease prevents simultaneous backup replacements',
    () async {
      final file = FailingStorage()..wait = Completer<void>();
      final first = BackupService(repository, storage: file, clock: () => now);
      final second = BackupService(repository, storage: file, clock: () => now);
      final running = first.createBackup();
      while (await repository.setting('backup_lease') == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await expectLater(
        second.createBackup(),
        throwsA(isA<BackupBusyException>()),
      );
      file.wait!.complete();
      await running;
      expect(await repository.setting('backup_lease'), isNull);
    },
  );

  test(
    'bad local backup is reported and replaced by an eligible automatic run',
    () async {
      storage.contents = 'broken';
      final status = await service.loadStatus();
      expect(status.invalidBackup, true);
      expect(status.hasBackup, false);
      await repository.setSetting(BackupService.automaticKey, 'true');
      expect(await service.maybeAutomaticBackup(), true);
      expect((await service.latestBackup())!.taskCount, 1);
    },
  );

  test(
    'file store retains one stable file and preserves it on failed replacement',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'todoniq-backup-test-',
      );
      try {
        final file = FileBackupStorage(directory.path);
        await file.writeLatest('first');
        await file.writeLatest('second');
        expect(await file.readLatest(), 'second');
        expect((await directory.list().toList()).length, 1);
        final pending = Directory(
          '${directory.path}${Platform.pathSeparator}latest.pending',
        );
        await pending.create();
        await expectLater(
          file.writeLatest('third'),
          throwsA(isA<FileSystemException>()),
        );
        expect(await file.readLatest(), 'second');
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('import validates before confirmation; cancellation leaves database unchanged', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    expect(await service.pickBackup(), isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'broken');
    await expectLater(service.pickBackup(), throwsFormatException);
    expect((await repository.tasks()).single.title, '필터 청소');
    final snapshot = await capture();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => snapshot.contents);
    expect((await service.pickBackup())!.taskCount, 1);
  });

  test('export passes only the safe snapshot to native picker and respects cancellation', () async {
    await repository.setSetting('subscription', 'private-purchase');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'export');
          expect(call.arguments['filename'], 'Todoniq-backup.json');
          final contents = call.arguments['contents'] as String;
          expect(contents, isNot(contains('private-purchase')));
          expect(BackupSnapshot.parse(contents).taskCount, 1);
          return false;
        });
    expect(await service.exportBackup(), false);
    expect((await service.latestBackup())!.taskCount, 1);
  });
}
