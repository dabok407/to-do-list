// Actual production widget captures with fictional preview data.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/widget_service.dart';

class _Paid extends SubscriptionService {
  _Paid() {
    active = true;
    available = true;
  }
  @override
  Future<void> refresh() async {}
}

void main() {
  const enabled = bool.fromEnvironment('STATS_PERIOD_CAPTURE');
  const variant = String.fromEnvironment(
    'STATS_PERIOD_VARIANT',
    defaultValue: 'after',
  );
  if (!enabled) {
    test('Period capture is opt-in', () {}, skip: true);
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
  for (final device in [
    (name: 'mini', size: const Size(375, 812), top: 50.0),
    (name: 'pro', size: const Size(402, 874), top: 62.0),
  ]) {
    for (final language in ['ko', 'en']) {
      testWidgets('${device.name} $language $variant statistics', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = device.size * 2;
        tester.view.padding = FakeViewPadding(top: device.top * 2, bottom: 68);
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetPadding);
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(WidgetService.channel, (call) async {
          if (call.method == 'getCalendarPreferences') {
            return {'regionCode': 'KR', 'firstDayOfWeek': 0};
          }
          throw MissingPluginException();
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(WidgetService.channel, null),
        );
        final controller = PreviewController(sampleLanguage: language);
        await controller.localeController.setPreference(language);
        await controller.refresh();
        final subscription = _Paid();
        addTearDown(controller.dispose);
        addTearDown(subscription.dispose);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: HangeoreumApp(
              controller: controller,
              subscription: subscription,
              initialPage: 3,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await boundary.toImage(pixelRatio: 2);
          final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List();
          final file = File(
            '../.tools/statistics-period-2026-10-26/${device.name}-$language-$variant.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
          img.dispose();
        });
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
