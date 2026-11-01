// Opt-in screenshots of the production HomeScreen with fictional local data.
// flutter test tool/capture_completion_feedback_test.dart --dart-define=COMPLETION_CAPTURE=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/widget_service.dart';

import 'capture_seed_comparison_test.dart' as baseline;

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('../.tools/completion-feedback-2026-10-30/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  if (!const bool.fromEnvironment('COMPLETION_CAPTURE')) {
    test('Production completion capture requires opt-in', () {}, skip: true);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('Actual mini screen before, during and after completion', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 1624);
    tester.view.padding = const FakeViewPadding(top: 100, bottom: 68);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WidgetService.channel, (call) async {
          if (call.method == 'getCalendarPreferences') {
            return {'regionCode': 'KR', 'firstDayOfWeek': 0};
          }
          return null;
        });
    final controller = await baseline.fixture();
    final learning = baseline.fixtures.last;
    await controller.save(
      Task.fromMap({
        ...learning.toMap(),
        'title': '읽던 책 한 챕터를 마무리하고 인상 깊은 문장을 기록하기',
      }),
    );
    final subscription = baseline.PaidFixture();
    addTearDown(controller.dispose);
    addTearDown(subscription.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: HangeoreumApp(
          controller: controller,
          subscription: subscription,
          initialPage: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, key, '01-before');
    final work = controller.items.firstWhere((o) => o.task.id == 'seed-work');
    final row = find.byKey(ValueKey('task-swipe-${work.id}'));
    await tester.ensureVisible(row);
    await tester.tap(
      find.descendant(
        of: row,
        matching: find.byKey(const Key('task-completion-target')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      controller.items.firstWhere((o) => o.id == work.id).status,
      TaskStatus.completed,
    );
    expect(row, findsOneWidget);
    await capture(tester, key, '02-held-success');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump();
    expect(row, findsNothing);
    await capture(tester, key, '03-after-collapse');
    await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
  });
}
