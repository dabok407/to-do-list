import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hangeoreum/main.dart' as app;
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';

import 'bootstrap.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('실제 기기 CRUD·알림 예약·완료 해제·DB 재연결', (tester) async {
    final controller = await launchApplication(tester);
    await tester.tap(find.byTooltip('할 일 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '안방 대청소 통합 테스트');
    await tester.enterText(find.byType(TextFormField).at(2), '바닥 물건 5개 치우기');
    await tester.scrollUntilVisible(
      find.text('저장'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('저장'));
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
        matching: find.text('완료'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('완료 해제'));
    await tester.pumpAndSettle();
    expect(controller.items.single.status, TaskStatus.paused);
    await controller.reminders.testNotification();
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
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await controller.repository.db.close();
    final reopened = await TaskRepository.open();
    expect((await reopened.occurrences()).single.status, TaskStatus.paused);
    final reminders = ReminderScheduler();
    await reminders.initialize();
    final restored = TaskController(reopened, reminders);
    await restored.reconcile();
    await tester.pumpWidget(app.HangeoreumApp(controller: restored));
    await tester.pumpAndSettle();
    expect(find.text('캘린더'), findsWidgets);
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('calendar');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
