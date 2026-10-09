import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hangeoreum/services/feature_access.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/notification_plan.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/app/task_controller.dart';

import 'controller_test.dart' show RecordingReminders, RecordingWidgets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TaskRepository repo;
  late FeatureAccess access;
  late DateTime now;
  final start = DateTime(2026, 10, 9, 12);
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repo = await TaskRepository.open(databasePath: inMemoryDatabasePath);
    now = start;
    access = FeatureAccess(repo, clock: () => now);
  });
  tearDown(() async {
    access.dispose();
    await repo.db.close();
  });

  test(
    'headless refresh before first launch neither grants nor consumes trial',
    () async {
      await access.load();
      expect(access.enabled, false);
      expect(await repo.setting('feature_access_v1'), isNull);
      await access.load(startTrial: true);
      expect(access.trialEnds, start.add(const Duration(days: 7)));
    },
  );
  for (final delta in [-1, 0, 1]) {
    test('trial boundary at 7 days plus $delta milliseconds', () async {
      await access.load(startTrial: true);
      now = start.add(Duration(days: 7, milliseconds: delta));
      expect(access.enabled, delta < 0);
      expect(access.allows('complete'), true);
      expect(access.allows('uncomplete'), true);
      expect(access.allows('snooze'), delta < 0);
    });
  }
  test(
    'restart and changing local clock backwards cannot restart expired trial',
    () async {
      await access.load(startTrial: true);
      now = start.add(const Duration(days: 8));
      await access.load();
      now = start;
      final restarted = FeatureAccess(repo, clock: () => now);
      await restarted.load(startTrial: true);
      expect(restarted.enabled, false);
      expect(restarted.trialEnds, start.add(const Duration(days: 7)));
      restarted.dispose();
    },
  );
  test(
    'corrupt persisted state fails closed instead of giving another trial',
    () async {
      await repo.setSetting('feature_access_v1', '{broken');
      await access.load(startTrial: true);
      expect(access.enabled, false);
    },
  );
  test(
    'background refresh and purchase cannot lose the verified entitlement',
    () async {
      await access.load(startTrial: true);
      now = start.add(const Duration(days: 8));
      final worker = FeatureAccess(repo, clock: () => now);
      await Future.wait([access.verifiedStore(active: true), worker.load()]);
      await worker.load();
      expect(worker.enabled, true);
      expect(worker.trialEnds, start.add(const Duration(days: 7)));
      worker.dispose();
    },
  );
  test(
    'verified lease is capped at expiry and revoked by confirmed refund',
    () async {
      await access.load(startTrial: true);
      now = start.add(const Duration(days: 8));
      final expiry = now.add(const Duration(hours: 2));
      await access.verifiedStore(active: true, expires: expiry);
      expect(access.until, expiry);
      await access.verifiedStore(active: false);
      expect(access.enabled, false);
    },
  );
  test(
    'offline verified purchase survives transient error but not its 24h lease',
    () async {
      await access.load(startTrial: true);
      now = start.add(const Duration(days: 8));
      const channel = MethodChannel('com.dabok407.hangeoreum/billing');
      final binding =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      binding.setMockMethodCallHandler(channel, (_) async => {'active': true});
      final service = SubscriptionService(access: access);
      await service.restore();
      expect(service.hasAccess, true);
      binding.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'offline'),
      );
      await service.refresh();
      expect(service.hasAccess, true);
      now = now.add(const Duration(hours: 24));
      expect(service.hasAccess, false);
      service.dispose();
      binding.setMockMethodCallHandler(channel, null);
    },
  );
  for (final repeat in RepeatUnit.values) {
    test(
      'alarm cutoff includes due and overdue jobs without immortal repeats: $repeat',
      () {
        final cutoff = start.add(const Duration(days: 7));
        final task = Task(
          id: 't',
          title: '필터 청소',
          due: start,
          created: start,
          repeat: repeat,
          weekdays: [1, 5],
        );
        final rows = List.generate(14, (i) {
          final due = start.add(Duration(days: i));
          return Occurrence(
            id: 't@$i',
            task: task,
            originalDue: due,
            reminder: due,
          );
        });
        final plan = NotificationPlan.build(
          rows,
          now: start,
          until: cutoff,
          capacity: 400,
        );
        expect(plan.jobs, isNotEmpty);
        expect(
          plan.jobs.every((j) => j.at.isBefore(cutoff) && j.repeat == null),
          true,
        );
        expect(
          NotificationPlan.build(
            rows,
            now: cutoff,
            until: cutoff,
            capacity: 400,
          ).jobs,
          isEmpty,
        );
      },
    );
  }
  for (final source in ['app', 'notification', 'widget']) {
    for (final action in ['start', 'snooze']) {
      test(
        'expired $source cannot bypass $action gate; complete and undo remain usable',
        () async {
          await access.load(startTrial: true);
          now = start.add(const Duration(days: 8));
          final controller = TaskController(
            repo,
            RecordingReminders(),
            widgets: RecordingWidgets(),
            access: access,
          );
          final task = Task(
            id: 't',
            title: '청소',
            due: DateTime.now().add(const Duration(hours: 1)),
            created: DateTime.now(),
          );
          await controller.save(task);
          final o = controller.items.single;
          if (source == 'app') await controller.act(o, action);
          if (source == 'notification') {
            await controller.handleNotification(o.id, action);
          }
          if (source == 'widget') {
            await controller.handleWidgetLaunch(
              'hangeoreum://task?id=${Uri.encodeComponent(o.id)}&action=$action',
            );
          }
          expect((await repo.occurrences()).single.status, TaskStatus.pending);
          expect((await repo.stats())['snoozes'], 0);
          await controller.act(o, 'complete');
          expect(controller.items.single.status, TaskStatus.completed);
          await controller.act(controller.items.single, 'uncomplete');
          expect(controller.items.single.status, TaskStatus.pending);
          expect(controller.reminders.accessUntil, DateTime(1970));
          controller.dispose();
        },
      );
    }
  }
}
