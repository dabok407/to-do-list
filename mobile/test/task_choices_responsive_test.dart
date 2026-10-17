import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/equal_choice_row.dart';
import 'package:hangeoreum/features/task_editor.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _capture = bool.fromEnvironment('CAPTURE_RESPONSIVE_CHOICES');

void _verifyRow(WidgetTester tester, Finder group, String prefix) {
  final row = find.descendant(
    of: group,
    matching: find.byType(EqualChoiceRow<String>),
  );
  final available = tester.getRect(row);
  final rectangles = <Rect>[];
  for (final category in taskCategories) {
    final choice = find.byKey(Key('$prefix-$category'));
    final rect = tester.getRect(choice);
    rectangles.add(rect);
    final label = find.descendant(of: choice, matching: find.byType(Text));
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(paragraph.didExceedMaxLines, isFalse, reason: category);
    final labelRect = tester.getRect(label);
    expect(labelRect.left, greaterThanOrEqualTo(rect.left - .01));
    expect(labelRect.right, lessThanOrEqualTo(rect.right + .01));
    expect(labelRect.top, greaterThanOrEqualTo(rect.top - .01));
    expect(labelRect.bottom, lessThanOrEqualTo(rect.bottom + .01));
  }
  expect(rectangles.first.left, closeTo(available.left, .01));
  expect(rectangles.last.right, closeTo(available.right, .01));
  for (final rect in rectangles) {
    expect(rect.top, closeTo(rectangles.first.top, .01));
    expect(rect.width, closeTo(rectangles.first.width, .01));
    expect(rect.height, closeTo(rectangles.first.height, .01));
    expect(rect.height, greaterThanOrEqualTo(48));
  }
}

Future<void> _captureScreen(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  await tester.runAsync(() async {
    final renderer =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await renderer.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = File('build/responsive-choices/$name.png');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          WidgetService.channel,
          (call) async => call.method == 'getCalendarPreferences'
              ? {'regionCode': 'KR', 'firstDayOfWeek': 0}
              : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WidgetService.channel, null);
  });

  for (final width in [320.0, 375.0, 402.0, 440.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final language in ['ko', 'en']) {
        testWidgets(
          'production quick add and editor fill one row: $width $language ${scale}x',
          (tester) async {
            debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
            try {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = Size(width, width == 375 ? 812 : 874);
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue,
              );
              final controller = PreviewController(sampleLanguage: language);
              final subscription = PreviewSubscription();
              addTearDown(controller.dispose);
              addTearDown(subscription.dispose);
              await controller.localeController.setPreference(language);
              final boundary = GlobalKey();
              await tester.pumpWidget(
                RepaintBoundary(
                  key: boundary,
                  child: HangeoreumApp(
                    controller: controller,
                    subscription: subscription,
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final header = find.byKey(const Key('quick-add'));
              await tester.ensureVisible(header);
              await tester.pumpAndSettle();
              await tester.tap(header);
              await tester.pumpAndSettle();
              _verifyRow(
                tester,
                find.byKey(const Key('quick-add-card')),
                'quick-category-option',
              );
              final captureThis =
                  _capture &&
                  language == 'ko' &&
                  scale == 1 &&
                  (width == 375 || width == 402);
              if (captureThis) {
                await Scrollable.ensureVisible(
                  tester.element(header),
                  alignment: .1,
                );
                await tester.pumpAndSettle();
                await _captureScreen(
                  tester,
                  boundary,
                  'quick-${width.toInt()}',
                );
              }
              Navigator.of(tester.element(header)).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      TaskEditor(initialDate: DateTime(2026, 10, 17)),
                ),
              );
              await tester.pumpAndSettle();
              _verifyRow(
                tester,
                find.byKey(const Key('editor-category')),
                'editor-category-option',
              );
              expect(
                tester
                    .widget<ChoiceChip>(
                      find.byKey(const Key('editor-priority-option-1')),
                    )
                    .selected,
                isTrue,
              );
              if (captureThis) {
                await _captureScreen(
                  tester,
                  boundary,
                  'editor-${width.toInt()}',
                );
              }
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            } finally {
              debugDefaultTargetPlatformOverride = null;
            }
          },
        );
      }
    }
  }
}
