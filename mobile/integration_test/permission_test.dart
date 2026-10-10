import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/l10n/app_strings.dart';

import 'bootstrap.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('OS 알림 권한을 거부해도 저장·완료·해제·삭제가 동작한다', (tester) async {
    final controller = await launchApplication(tester);
    final strings = AppStrings(controller.localeController.locale.languageCode);
    expect(await controller.reminders.enabled(), false);
    for (final task in controller.items.map((o) => o.task).toList()) {
      await controller.delete(task);
    }
    await controller.save(
      Task(
        id: 'denied-permission',
        title: '권한 없는 로컬 할 일',
        due: DateTime.now().add(const Duration(minutes: 30)),
        created: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.items.single.task.title, '권한 없는 로컬 할 일');
    expect(
      controller.warning,
      strings.t('알림이 꺼져 있어요. 설정에서 알림을 켜면 예정된 시간에 알려드릴 수 있어요.'),
    );
    await controller.act(controller.items.single, 'complete');
    expect(controller.items.single.status, TaskStatus.completed);
    await controller.act(controller.items.single, 'uncomplete');
    expect(controller.items.single.status, TaskStatus.pending);
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('permission-denied');
    await controller.delete(controller.items.single.task);
    expect(controller.items, isEmpty);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await controller.repository.db.close();
    controller.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
