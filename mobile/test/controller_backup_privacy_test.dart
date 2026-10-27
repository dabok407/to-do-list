import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/services/backup_service.dart';
import 'package:hangeoreum/services/backup_storage.dart';
import 'package:hangeoreum/services/notification_privacy.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Reminders extends ReminderScheduler {
  Future<void> Function()? onInitialize, onSync;
  final actions = <String>[];
  List<Occurrence> scheduled = [];

  @override
  Future<void> initialize() async {
    actions.add('initialize:${AppStrings.current.languageCode}');
    await onInitialize?.call();
  }

  @override
  Future<bool?> enabled() async => true;

  @override
  Future<void> sync(
    List<Occurrence> items, {
    Map<String, List<DateTime>> exceptions = const {},
  }) async {
    actions.add('sync:${AppStrings.current.languageCode}');
    scheduled = List.of(items);
    await onSync?.call();
  }
}

class _Widgets extends WidgetService {
  List<Occurrence> received = [];
  @override
  Future<void> sync(List<Occurrence> items) async => received = List.of(items);
}

class _Backups extends BackupService {
  Future<void> Function()? onAutomatic;
  _Backups(super.repository) : super(storage: MemoryBackupStorage());
  @override
  Future<bool> maybeAutomaticBackup() async {
    await onAutomatic?.call();
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TaskRepository repository;
  late _Reminders reminders;
  late _Widgets widgets;
  late _Backups backups;
  late TaskController controller;
  final due = DateTime(2026, 10, 26, 12);

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repository = await TaskRepository.open(databasePath: inMemoryDatabasePath);
    reminders = _Reminders();
    widgets = _Widgets();
    backups = _Backups(repository);
    controller = TaskController(
      repository,
      reminders,
      widgets: widgets,
      backups: backups,
    );
    AppStrings.current = const AppStrings('ko');
  });

  tearDown(() async {
    controller.dispose();
    await repository.db.close();
    AppStrings.current = const AppStrings('ko');
  });

  Future<void> assertLeaseFree() async {
    expect(await repository.acquireReminderLease('after'), isTrue);
    await repository.releaseReminderLease('after');
  }

  Future<BackupSnapshot> prepareRestore() async {
    await repository.saveTask(
      Task(id: 'backed-up', title: '복원할 일', due: due, created: due),
    );
    await repository.setSetting('display_language', 'en');
    await NotificationPrivacy(repository).setShowTitles(false);
    final snapshot = await BackupSnapshot.capture(repository);
    await repository.deleteTask('backed-up');
    await repository.saveTask(
      Task(id: 'current', title: '현재 할 일', due: due, created: due),
    );
    await controller.localeController.setPreference('ko');
    await NotificationPrivacy(repository).setShowTitles(true);
    return snapshot;
  }

  test(
    'privacy waits before writing and holds the lease through native sync',
    () async {
      expect(await repository.acquireReminderLease('background'), isTrue);
      final change = controller.setNotificationTitles(false);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(await repository.setting(NotificationPrivacy.settingKey), isNull);
      expect(reminders.actions, isEmpty);
      reminders.onSync = () async {
        expect(await NotificationPrivacy(repository).load(), isFalse);
        expect(await repository.acquireReminderLease('competitor'), isFalse);
      };
      backups.onAutomatic = assertLeaseFree;
      await repository.releaseReminderLease('background');
      await change;
      expect(reminders.actions, ['sync:ko']);
      await assertLeaseFree();
    },
  );

  test(
    'busy privacy change fails before saving instead of deferring it',
    () async {
      await NotificationPrivacy(repository).setShowTitles(true);
      expect(await repository.acquireReminderLease('background'), isTrue);
      await expectLater(
        controller.setNotificationTitles(false),
        throwsStateError,
      );
      expect(await NotificationPrivacy(repository).load(), isTrue);
      expect(reminders.actions, isEmpty);
      expect(await repository.acquireReminderLease('competitor'), isFalse);
      await repository.releaseReminderLease('background');
      // The rejected operation must not poison the controller's serial queue.
      await controller.setNotificationTitles(false);
      expect(await NotificationPrivacy(repository).load(), isFalse);
    },
  );

  test('restore waits before replacing data and initializes restored language before sync', () async {
    final snapshot = await prepareRestore();
    expect(await repository.acquireReminderLease('background'), isTrue);
    final restore = controller.restoreBackup(snapshot);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect((await repository.tasks()).single.id, 'current');
    expect(await NotificationPrivacy(repository).load(), isTrue);
    expect(reminders.actions, isEmpty);
    reminders.onInitialize = () async {
      expect((await repository.tasks()).single.id, 'backed-up');
      expect(await repository.acquireReminderLease('competitor'), isFalse);
    };
    reminders.onSync = () async {
      expect(await NotificationPrivacy(repository).load(), isFalse);
      expect(await repository.acquireReminderLease('competitor'), isFalse);
    };
    backups.onAutomatic = assertLeaseFree;
    await repository.releaseReminderLease('background');
    await restore;
    expect(reminders.actions, ['initialize:en', 'sync:en']);
    expect(reminders.scheduled.single.task.id, 'backed-up');
    expect(widgets.received.single.task.id, 'backed-up');
    expect(controller.localeController.preference, 'en');
    await assertLeaseFree();
  });

  test(
    'busy restore leaves current data, language and privacy unchanged',
    () async {
      final snapshot = await prepareRestore();
      expect(await repository.acquireReminderLease('background'), isTrue);
      await expectLater(controller.restoreBackup(snapshot), throwsStateError);
      expect((await repository.tasks()).single.id, 'current');
      expect(await repository.setting('display_language'), 'ko');
      expect(await NotificationPrivacy(repository).load(), isTrue);
      expect(reminders.actions, isEmpty);
      expect(await repository.acquireReminderLease('competitor'), isFalse);
      await repository.releaseReminderLease('background');
    },
  );

  test(
    'failed atomic restore reports failure and releases both leases',
    () async {
      final snapshot = await prepareRestore();
      await repository.db.execute(
        "CREATE TRIGGER fail_restore BEFORE INSERT ON tasks BEGIN SELECT RAISE(ABORT, 'restore failure'); END",
      );
      await expectLater(
        controller.restoreBackup(snapshot),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repository.tasks()).single.id, 'current');
      expect(await NotificationPrivacy(repository).load(), isTrue);
      expect(reminders.actions, isEmpty);
      expect(await repository.setting('backup_lease'), isNull);
      await assertLeaseFree();
      await repository.db.execute('DROP TRIGGER fail_restore');
      await controller.restoreBackup(snapshot);
      expect(reminders.scheduled.single.task.id, 'backed-up');
    },
  );

  test('native initialization failure preserves restored data and still attempts scheduling', () async {
    final snapshot = await prepareRestore();
    reminders.onInitialize = () async => throw StateError('unavailable');
    await controller.restoreBackup(snapshot);
    expect(reminders.actions, ['initialize:en', 'sync:en']);
    expect((await repository.tasks()).single.id, 'backed-up');
    await assertLeaseFree();
  });

  test('native sync failure retains saved privacy, reports warning and releases lease', () async {
    reminders.onSync = () async =>
        throw StateError('native scheduling failure');
    await controller.setNotificationTitles(false);
    expect(await NotificationPrivacy(repository).load(), isFalse);
    expect(controller.warning, contains('알림을 예약하지 못했습니다'));
    await assertLeaseFree();
  });
}
