import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hangeoreum/main.dart' as app;
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/feature_access.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/l10n/app_strings.dart';

import 'bootstrap.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('실제 기기 CRUD·알림 예약·완료 해제·DB 재연결', (tester) async {
    final controller = await launchApplication(tester);
    // Keep the native device's real language. The production app resolves it
    // during startup, so UI finders must use that same resolved language.
    final strings = AppStrings(controller.localeController.locale.languageCode);
    await tester.tap(find.byTooltip(strings.t('할 일 추가')));
    await tester.pumpAndSettle();
    final titleInput = find.byKey(const Key('editor-title'));
    await tester.ensureVisible(titleInput);
    await tester.enterText(titleInput, '안방 대청소 통합 테스트');
    await tester.pumpAndSettle();
    final titleFocus = tester
        .widget<EditableText>(
          find.descendant(of: titleInput, matching: find.byType(EditableText)),
        )
        .focusNode;
    expect(titleFocus.hasFocus, isTrue);
    await tester.tap(find.text(strings.t('할 일 추가')));
    await tester.pumpAndSettle();
    expect(
      titleFocus.hasFocus,
      isFalse,
      reason: '입력 바깥을 터치하면 네이티브 화면에서도 키보드 포커스가 해제되어야 한다',
    );
    debugPrint('NATIVE_KEYBOARD_DISMISSAL_OK');
    final smallInput = find.byKey(const Key('editor-small-step'));
    await tester.ensureVisible(smallInput);
    await tester.enterText(smallInput, '바닥 물건 5개 치우기');
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.t('저장')));
    await tester.pumpAndSettle();
    // Anchor the alarm in the future; the editor's default time can cross midnight
    // while CI is building and installing the app.
    await controller.save(
      Task.fromMap({
        ...controller.items.single.task.toMap(),
        'due': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      }),
    );
    await tester.pumpAndSettle();
    final occurrence = controller.items.single;
    expect(occurrence.task.title, '안방 대청소 통합 테스트');
    expect(occurrence.task.smallStep, '바닥 물건 5개 치우기');
    final pending = await controller.reminders.plugin
        .pendingNotificationRequests();
    expect(
      pending.any((n) => n.payload == occurrence.id),
      true,
      reason:
          'warning=${controller.warning}; enabled=${await controller.reminders.enabled()}; '
          'planned=${controller.reminders.lastPlan?.jobs.map((j) => '${j.payload}@${j.at}').toList()}; '
          'pending=${pending.map((n) => '${n.id}:${n.payload}').toList()}; occurrence=${occurrence.id}',
    );
    // Exercise two real SQLite tasks through the production OS plugin, including
    // a deliberately identical title and due time. Completing one must leave
    // the other's real pending request intact on both mobile platforms.
    final duplicate = Task.fromMap({
      ...occurrence.task.toMap(),
      'id': 'integration-same-time',
      'series_id': 'integration-same-time',
    });
    await controller.save(duplicate);
    final second = controller.items.singleWhere(
      (o) => o.task.id == duplicate.id,
    );
    final together = await controller.reminders.plugin
        .pendingNotificationRequests();
    final firstIds = together
        .where((n) => n.payload == occurrence.id)
        .map((n) => n.id)
        .toSet();
    final secondIds = together
        .where((n) => n.payload == second.id)
        .map((n) => n.id)
        .toSet();
    expect(firstIds, isNotEmpty);
    expect(secondIds, isNotEmpty);
    expect(firstIds.intersection(secondIds), isEmpty);
    await controller.act(second, 'complete');
    final remaining = await controller.reminders.plugin
        .pendingNotificationRequests();
    expect(remaining.any((n) => n.payload == occurrence.id), isTrue);
    expect(remaining.any((n) => n.payload == second.id), isFalse);
    await controller.delete(duplicate);
    expect(controller.items, hasLength(1));
    debugPrint('NATIVE_SAME_TIME_REMINDERS_ISOLATED_OK');
    // Wait for two independent task reminders to actually reach the OS at the
    // same clock time. Pending requests alone cannot prove their delivery.
    final deliveryCreated = DateTime.now();
    final deliveryDue = DateTime(
      deliveryCreated.year,
      deliveryCreated.month,
      deliveryCreated.day,
      deliveryCreated.hour,
      deliveryCreated.minute + 2,
    );
    final deliveryTasks = [
      for (final suffix in ['a', 'b'])
        Task(
          id: 'integration-delivered-$suffix',
          groupId: 'integration-delivered-$suffix',
          title: '같은 시각 실제 알림 $suffix',
          due: deliveryDue,
          created: deliveryCreated,
          overdueDays: 0,
        ),
    ];
    String? activePayload(ActiveNotification notification) =>
        notification.payload ?? notification.tag;
    Future<List<ActiveNotification>> waitForActive(
      bool Function(List<ActiveNotification>) ready,
      Duration timeout,
    ) async {
      final result = await tester.runAsync(() async {
        final elapsed = Stopwatch()..start();
        var active = await controller.reminders.plugin.getActiveNotifications();
        while (!ready(active) && elapsed.elapsed < timeout) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          active = await controller.reminders.plugin.getActiveNotifications();
        }
        return active;
      });
      expect(result, isNotNull);
      return result!;
    }

    try {
      for (final task in deliveryTasks) {
        await controller.save(task);
      }
      final deliveryOccurrences = [
        for (final task in deliveryTasks)
          controller.items.singleWhere((o) => o.task.id == task.id),
      ];
      final deliveryPayloads = deliveryOccurrences.map((o) => o.id).toSet();
      expect(deliveryPayloads, hasLength(2));
      final deliveryJobs = controller.reminders.lastPlan!.jobs
          .where((job) => deliveryPayloads.contains(job.payload))
          .toList();
      expect(deliveryJobs, hasLength(2));
      expect(deliveryJobs.map((job) => job.at), everyElement(deliveryDue));
      expect(
        deliveryDue.difference(DateTime.now()),
        greaterThan(const Duration(seconds: 20)),
        reason:
            'Both minute-based reminders must be registered before delivery.',
      );
      final deliveryPending = await controller.reminders.plugin
          .pendingNotificationRequests();
      final deliveryIds = {
        for (final payload in deliveryPayloads)
          payload: deliveryPending.singleWhere((n) => n.payload == payload).id,
      };
      expect(deliveryIds.values.toSet(), hasLength(2));
      final delivered = await waitForActive(
        (active) => deliveryIds.entries.every(
          (expected) => active.any(
            (n) => n.id == expected.value && activePayload(n) == expected.key,
          ),
        ),
        deliveryDue.difference(DateTime.now()) + const Duration(seconds: 45),
      );
      for (final expected in deliveryIds.entries) {
        expect(
          delivered.any(
            (n) => n.id == expected.value && activePayload(n) == expected.key,
          ),
          isTrue,
          reason:
              'platform=${Platform.operatingSystem}; due=$deliveryDue; '
              'expected=${deliveryIds.entries.toList()}; '
              'active=${delivered.map((n) => '${n.id}:${activePayload(n)}').toList()}',
        );
      }
      final firstDelivery = deliveryOccurrences.first;
      final secondDelivery = deliveryOccurrences.last;
      await controller.act(firstDelivery, 'complete');
      final afterCompletion = await waitForActive(
        (active) =>
            !active.any((n) => activePayload(n) == firstDelivery.id) &&
            active.any(
              (n) =>
                  n.id == deliveryIds[secondDelivery.id] &&
                  activePayload(n) == secondDelivery.id,
            ),
        const Duration(seconds: 5),
      );
      expect(
        afterCompletion.any((n) => activePayload(n) == firstDelivery.id),
        isFalse,
      );
      expect(
        afterCompletion.any(
          (n) =>
              n.id == deliveryIds[secondDelivery.id] &&
              activePayload(n) == secondDelivery.id,
        ),
        isTrue,
      );
      debugPrint('NATIVE_SAME_TIME_DELIVERED_OK');
    } finally {
      for (final task in deliveryTasks) {
        await controller.delete(task);
      }
    }
    expect(controller.items, hasLength(1));
    await controller.act(occurrence, 'snooze', minutes: 30);
    await tester.pumpAndSettle();
    expect(controller.items.single.status, TaskStatus.paused);
    // A snooze moves the first alert. Subsequent reminders are daily at the
    // original due time, and never reach or cross the access deadline.
    final current = controller.items.single;
    final due = current.originalDue;
    final until = controller.access!.until!;
    final expected =
        1 +
        List.generate(
              32,
              (i) => DateTime(
                due.year,
                due.month,
                due.day + i + 1,
                due.hour,
                due.minute,
              ),
            )
            .where((at) => at.isAfter(current.reminder) && at.isBefore(until))
            .length;
    expect(
      (await controller.reminders.plugin.pendingNotificationRequests())
          .where((n) => n.payload == occurrence.id)
          .length,
      expected,
    );
    await controller.act(controller.items.single, 'complete');
    await tester.pumpAndSettle();
    expect(
      await controller.reminders.plugin.pendingNotificationRequests(),
      isEmpty,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(strings.t('완료')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(strings.t('완료 해제')));
    await tester.pumpAndSettle();
    expect(controller.items.single.status, TaskStatus.paused);
    await controller.testReminder();
    final beforeTestRefill = await controller.reminders.plugin
        .pendingNotificationRequests();
    final testRequests = beforeTestRefill
        .where((n) => n.id == ReminderScheduler.testNotificationId)
        .toList();
    expect(
      testRequests,
      hasLength(1),
      reason:
          'The production test reminder must be pending before delivery. '
          'platform=${Platform.operatingSystem}; '
          'pending=${beforeTestRefill.map((n) => '${n.id}:${n.payload}').toList()}',
    );
    final originalTestRequest = testRequests.single;
    expect(originalTestRequest.payload, isNotEmpty);
    expect(originalTestRequest.title, strings.t('투두닉 테스트'));
    expect(originalTestRequest.body, strings.t('앱 밖에서도 알림이 도착하는지 확인해주세요.'));
    // Force the same refill that can follow a foreground resume or task edit.
    // Its payload includes the original absolute delivery time: preserving it
    // proves that refill neither cancels the test nor restarts its ten seconds.
    await controller.reconcile();
    final afterTestRefill = await controller.reminders.plugin
        .pendingNotificationRequests();
    final restoredTestRequests = afterTestRefill
        .where((n) => n.id == ReminderScheduler.testNotificationId)
        .toList();
    expect(
      restoredTestRequests,
      hasLength(1),
      reason:
          'Reconciliation must preserve the pending test reminder. '
          'platform=${Platform.operatingSystem}; '
          'original=${originalTestRequest.id}:${originalTestRequest.payload}; '
          'pending=${afterTestRefill.map((n) => '${n.id}:${n.payload}').toList()}',
    );
    final restoredTestRequest = restoredTestRequests.single;
    expect(restoredTestRequest.payload, originalTestRequest.payload);
    expect(restoredTestRequest.title, originalTestRequest.title);
    expect(restoredTestRequest.body, originalTestRequest.body);
    debugPrint('NATIVE_TEST_REMINDER_REFILL_PRESERVED_OK');
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 12));
    });
    if (Platform.isAndroid) {
      expect(
        (await controller.reminders.plugin.getActiveNotifications()).any(
          (n) => n.id == 100000,
        ),
        true,
      );
    } else {
      // iOS foreground banners are not necessarily retained in Notification Center.
      expect(
        (await controller.reminders.plugin.pendingNotificationRequests()).any(
          (n) => n.id == 100000,
        ),
        false,
      );
    }
    // Expiry uses the real SQLite store, OS notification plugin, controller,
    // and UI on each platform. The fixture changes time state, not store billing.
    final savedAccess = await controller.repository.setting(
      'feature_access_v1',
    );
    expect(savedAccess, isNotNull);
    try {
      // Simulate a store-verified purchase last seen 30 days ago. This checks
      // SQLite -> access -> production OS scheduler, without claiming real IAP.
      for (final knownExpiry in [false, true]) {
        await controller.repository.setSetting(
          'feature_access_v1',
          jsonEncode({
            'version': 2,
            'verifiedPaid': true,
            'trialEnds': DateTime.now()
                .subtract(const Duration(days: 30))
                .toIso8601String(),
            'paidUntil': knownExpiry
                ? DateTime.now()
                      .add(const Duration(days: 335))
                      .toIso8601String()
                : null,
            'lastSeen': DateTime.now()
                .subtract(const Duration(days: 30))
                .toIso8601String(),
          }),
        );
        await controller.reconcile();
        expect(controller.access!.paidActive, true);
        expect(
          controller.reminders.lastPlan!.jobs.any(
            (job) =>
                job.repeat != null ||
                job.at.isAfter(DateTime.now().add(const Duration(days: 7))),
          ),
          true,
        );
        expect(
          await controller.reminders.plugin.pendingNotificationRequests(),
          isNotEmpty,
        );
      }
      debugPrint('NATIVE_OFFLINE_PAID_REMINDERS_OK');
      await controller.repository.setSetting(
        'feature_access_v1',
        jsonEncode({
          'trialEnds': DateTime.now()
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
          'paidUntil': null,
          'lastSeen': DateTime.now().toIso8601String(),
        }),
      );
      await controller.reconcile();
      await tester.pumpAndSettle();
      expect(
        await controller.reminders.plugin.pendingNotificationRequests(),
        isEmpty,
      );
      final before = controller.items.single;
      await controller.act(before, 'snooze', minutes: 60);
      await controller.handleWidgetLaunch(
        'hangeoreum://task?id=${Uri.encodeComponent(before.id)}&action=start',
      );
      expect(controller.items.single.status, TaskStatus.paused);
      expect(controller.items.single.snoozes, before.snoozes);
      // Opening a blocked widget action may open detail; dismiss before tabs.
      controller.pendingOpenId = null;
      await tester.pumpAndSettle();
      final close = find.byTooltip(strings.t('닫기'));
      if (close.evaluate().isNotEmpty) {
        await tester.tap(close.last);
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(strings.t('통계')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          strings.t(
            '7일 체험이 끝났어요. Pro를 구독하면 알림·미루기와 30일·90일 통계를 계속 사용할 수 있어요. 기존 기록은 그대로 남아 있어요.',
          ),
        ),
        findsOneWidget,
      );
      await controller.act(before, 'complete');
      await controller.act(controller.items.single, 'uncomplete');
      expect(controller.items.single.status, TaskStatus.paused);
      expect(
        await controller.reminders.plugin.pendingNotificationRequests(),
        isEmpty,
      );
    } finally {
      await controller.repository.setSetting('feature_access_v1', savedAccess!);
      await controller.reconcile();
    }
    expect(
      await controller.reminders.plugin.pendingNotificationRequests(),
      isNotEmpty,
    );
    debugPrint('NATIVE_TRIAL_EXPIRY_AND_RESTORE_OK');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await controller.repository.db.close();
    final reopened = await TaskRepository.open();
    expect((await reopened.occurrences()).single.status, TaskStatus.paused);
    final reminders = ReminderScheduler();
    await reminders.initialize();
    final restoredAccess = FeatureAccess(reopened);
    await restoredAccess.load();
    final restored = TaskController(
      reopened,
      reminders,
      access: restoredAccess,
    );
    // main() reloads the stored preference before scheduling or mounting the UI.
    // Do the same when recreating the production controller against the real DB.
    await restored.localeController.load();
    expect(
      restored.localeController.locale,
      controller.localeController.locale,
    );
    // The scenario above exercises the real device's automatic language.
    // Persist that same resolved language for the separate native process,
    // whose widget/OCR checks read their exact expectations from the fixture DB.
    final nativeLanguage = restored.localeController.locale.languageCode;
    await restored.setLanguage(nativeLanguage);
    expect(restored.localeController.preference, nativeLanguage);
    expect(await reopened.setting('display_language'), nativeLanguage);
    expect(restored.localeController.locale.languageCode, nativeLanguage);
    debugPrint('NATIVE_UI_LANGUAGE:$nativeLanguage');
    await restored.reconcile();
    await tester.pumpWidget(
      app.HangeoreumApp(
        controller: restored,
        subscription: SubscriptionService(access: restoredAccess),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        AppStrings(restored.localeController.locale.languageCode).t('캘린더'),
      ),
      findsWidgets,
    );
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('calendar');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
