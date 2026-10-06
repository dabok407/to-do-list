import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hangeoreum/main.dart' as app;
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('실제 기기 CRUD·알림 예약·완료 해제·DB 재연결', (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    final controller = tester
        .widget<app.HangeoreumApp>(find.byType(app.HangeoreumApp))
        .controller;
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
    final occurrence = controller.items.single;
    expect(occurrence.task.title, '안방 대청소 통합 테스트');
    expect(
      (await controller.reminders.plugin.pendingNotificationRequests()).any(
        (n) => n.payload == occurrence.id,
      ),
      true,
    );
    await controller.act(occurrence, 'snooze', minutes: 30);
    await tester.pumpAndSettle();
    expect(controller.items.single.status, TaskStatus.paused);
    expect(
      (await controller.reminders.plugin.pendingNotificationRequests())
          .where((n) => n.payload == occurrence.id)
          .length,
      3,
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
    await Future<void>.delayed(const Duration(seconds: 12));
    expect(
      (await controller.reminders.plugin.getActiveNotifications()).any(
        (n) => n.id == 100000,
      ),
      true,
    );
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
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('calendar');
  });
}
