import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/services/feature_access.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Reminders extends ReminderScheduler {
  Future<void> Function()? onPermissions, onTest;
  int tests = 0, syncs = 0;
  bool? requestedAgain;

  @override
  Future<void> requestPermissions() async => onPermissions?.call();

  @override
  Future<void> testNotification({bool requestPermission = true}) async {
    tests++;
    requestedAgain = requestPermission;
    await onTest?.call();
  }

  @override
  Future<bool?> enabled() async => true;

  @override
  Future<void> sync(
    List<Occurrence> items, {
    Map<String, List<DateTime>> exceptions = const {},
  }) async {
    syncs++;
  }
}

class _Widgets extends WidgetService {
  @override
  Future<void> sync(List<Occurrence> items) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TaskRepository repository;
  late _Reminders reminders;
  late TaskController controller;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repository = await TaskRepository.open(databasePath: inMemoryDatabasePath);
    reminders = _Reminders();
    controller = TaskController(repository, reminders, widgets: _Widgets());
  });

  tearDown(() async {
    controller.dispose();
    await repository.db.close();
  });

  test('권한 요청은 lease 밖에서, 테스트 예약은 lease 안에서 실행', () async {
    reminders.onPermissions = () async {
      expect(await repository.acquireReminderLease('permission'), isTrue);
      await repository.releaseReminderLease('permission');
    };
    reminders.onTest = () async {
      expect(await repository.acquireReminderLease('background'), isFalse);
    };
    await controller.testReminder();
    expect(reminders.tests, 1);
    expect(reminders.requestedAgain, isFalse);
    expect(await repository.acquireReminderLease('after'), isTrue);
    await repository.releaseReminderLease('after');
  });

  test('백그라운드 예약이 끝난 뒤 테스트 알림을 등록', () async {
    expect(await repository.acquireReminderLease('background'), isTrue);
    final released = Completer<void>();
    final release = Timer(const Duration(milliseconds: 250), () async {
      await repository.releaseReminderLease('background');
      released.complete();
    });
    addTearDown(release.cancel);
    reminders.onTest = () async => expect(released.isCompleted, isTrue);
    await controller.testReminder();
    expect(reminders.tests, 1);
  });

  test('동시 reconcile은 테스트 예약 완료 후 실행', () async {
    final entered = Completer<void>(), finish = Completer<void>();
    reminders.onTest = () async {
      entered.complete();
      await finish.future;
    };
    final test = controller.testReminder();
    await entered.future;
    final reconcile = controller.reconcile();
    await Future<void>.delayed(Duration.zero);
    expect(reminders.syncs, 0);
    finish.complete();
    await Future.wait([test, reconcile]);
    expect(reminders.syncs, 1);
  });

  test('예약 오류 후 lease를 반환하고 다음 요청을 처리', () async {
    reminders.onTest = () async => throw StateError('native schedule failure');
    await expectLater(controller.testReminder(), throwsStateError);
    expect(await repository.acquireReminderLease('after'), isTrue);
    await repository.releaseReminderLease('after');
    reminders.onTest = null;
    await controller.testReminder();
    expect(reminders.tests, 2);
  });

  test('다른 엔진의 lease를 빼앗거나 테스트를 몰래 등록하지 않는다', () async {
    expect(await repository.acquireReminderLease('background'), isTrue);
    await expectLater(controller.testReminder(), throwsStateError);
    expect(reminders.tests, 0);
    expect(await repository.acquireReminderLease('after'), isFalse);
    await repository.releaseReminderLease('background');
  });

  test('구독 접근 상태를 재확인해 테스트 예약에 적용', () async {
    controller.dispose();
    final access = FeatureAccess(repository);
    await access.verifiedStore(
      active: true,
      expires: DateTime.now().add(const Duration(days: 1)),
    );
    controller = TaskController(
      repository,
      reminders,
      access: access,
      widgets: _Widgets(),
    );
    addTearDown(access.dispose);
    await controller.testReminder();
    expect(reminders.accessUntil, access.until);
    await access.verifiedStore(active: false);
    await controller.testReminder();
    expect(reminders.accessUntil, DateTime(1970));
  });
}
