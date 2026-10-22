// Explicit local design review only. These are production widgets rendered by
// Flutter with PreviewController's fictional sample data, not device photos.
// No shipping code, store artwork, native services, or private records are used.
// Run from mobile/: flutter test tool/capture_design_polish_test.dart
//   --dart-define=DESIGN_POLISH_CAPTURE=true --reporter=expanded
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/widget_service.dart';

const _enabled = bool.fromEnvironment('DESIGN_POLISH_CAPTURE');
const _outputRoot = '../.tools/design-polish-review-2026-10-20/captures';
const _devices = [
  (name: 'mini', size: Size(375, 812), top: 50.0),
  (name: 'pro', size: Size(402, 874), top: 62.0),
];
const _ratio = 2.0;

class _PaidReviewSubscription extends SubscriptionService {
  _PaidReviewSubscription() {
    active = true;
    available = true;
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> purchase() async =>
      throw StateError('Design review must not purchase');

  @override
  Future<void> restore() async =>
      throw StateError('Design review must not restore');

  @override
  Future<void> manage() async =>
      throw StateError('Design review must not change a subscription');
}

Finder _navigation(AppStrings strings, String korean) => find.descendant(
  of: find.byType(NavigationBar),
  matching: find.text(strings.t(korean)),
);

Future<Map<String, Object?>> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String prefix,
  String scene,
) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: '$prefix / $scene layout');
  final text = find
      .byType(Text)
      .evaluate()
      .map((element) {
        final widget = element.widget as Text;
        return widget.data ?? widget.textSpan?.toPlainText() ?? '';
      })
      .where((value) => value.isNotEmpty)
      .toList();
  final fileName = '$prefix-$scene.png';
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _ratio);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final output = File('$_outputRoot/$fileName');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
  return {
    'file': fileName,
    'scene': scene,
    'captured_at': DateTime.now().toUtc().toIso8601String(),
    'rendered_text': text,
  };
}

void main() {
  if (!_enabled) {
    test(
      'Local design capture runs only when explicitly requested',
      () {},
      skip: true,
    );
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(WidgetService.channel, (call) async {
      if (call.method == 'getCalendarPreferences') {
        return {'regionCode': 'KR', 'firstDayOfWeek': 0};
      }
      throw MissingPluginException(
        'Native service calls are outside local design review',
      );
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(WidgetService.channel, null),
  );
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final language in ['ko', 'en']) {
    for (final device in _devices) {
      testWidgets('$language ${device.name} production design review', (
        tester,
      ) async {
        tester.view.devicePixelRatio = _ratio;
        tester.view.physicalSize = device.size * _ratio;
        tester.view.padding = FakeViewPadding(
          top: device.top * _ratio,
          bottom: 34 * _ratio,
        );
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetPadding);
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        addTearDown(() => AppStrings.current = const AppStrings('ko'));

        // Use the existing, explicitly fictional preview data unchanged. All
        // chart figures and totals come from the app's own statistics code.
        final controller = PreviewController(sampleLanguage: language);
        await controller.localeController.setPreference(language);
        await controller.refresh();
        final subscription = _PaidReviewSubscription();
        addTearDown(controller.dispose);
        addTearDown(subscription.dispose);
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: HangeoreumApp(
              controller: controller,
              subscription: subscription,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final strings = AppStrings(language);
        final prefix = '$language-${device.name}';
        final scenes = <Map<String, Object?>>[];
        scenes.add(await _capture(tester, boundaryKey, prefix, 'calendar'));

        await tester.tap(_navigation(strings, '예정'));
        scenes.add(await _capture(tester, boundaryKey, prefix, 'upcoming'));

        await tester.tap(_navigation(strings, '완료'));
        scenes.add(await _capture(tester, boundaryKey, prefix, 'completed'));

        await tester.tap(_navigation(strings, '통계'));
        scenes.add(
          await _capture(tester, boundaryKey, prefix, 'statistics-top'),
        );
        await tester.tap(find.byKey(const Key('statistics-tab-category')));
        scenes.add(
          await _capture(tester, boundaryKey, prefix, 'statistics-category'),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('stats-category-기타')),
        );
        scenes.add(
          await _capture(
            tester,
            boundaryKey,
            prefix,
            'statistics-category-records',
          ),
        );
        await tester.ensureVisible(
          find.byKey(const Key('statistics-tab-priority')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('statistics-tab-priority')));

        // Statistics lives in HomeScreen's real body ListView. Jump that
        // scrollable to its actual end rather than depending on changing copy.
        final statisticsList = find.byType(ListView).first;
        final statisticsScroll = find
            .descendant(of: statisticsList, matching: find.byType(Scrollable))
            .first;
        final position = tester
            .state<ScrollableState>(statisticsScroll)
            .position;
        position.jumpTo(position.maxScrollExtent);
        scenes.add(
          await _capture(tester, boundaryKey, prefix, 'statistics-bottom'),
        );

        await tester.runAsync(() async {
          final output = File('$_outputRoot/$prefix-source.json');
          await output.writeAsString(
            '${const JsonEncoder.withIndent('  ').convert({
              'source': 'Production HangeoreumApp rendered by Flutter widget test',
              'fixture': 'Unmodified PreviewController fictional tasks',
              'purpose': 'Local UI design review, not store submission artwork',
              'native_device_capture': false,
              'native_or_external_services_called': false,
              'subscription': 'Explicit paid fixture; no StoreKit call',
              'language': language,
              'device_size_label': device.name,
              'logical_width': device.size.width.toInt(),
              'logical_height': device.size.height.toInt(),
              'pixel_ratio': _ratio,
              'png_width': (device.size.width * _ratio).toInt(),
              'png_height': (device.size.height * _ratio).toInt(),
              'fonts': ['PretendardVariable.ttf', 'MaterialIcons-Regular.otf'],
              'calendar_preferences': {'regionCode': 'KR', 'firstDayOfWeek': 0},
              'statistics_from_preview': controller.statistics,
              'scenes': scenes,
            })}\n',
          );
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        debugDefaultTargetPlatformOverride = null;
        expect(tester.takeException(), isNull);
      });
    }
  }
}
