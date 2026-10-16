// Explicit artwork export, never part of the shipping app or default test suite.
// Uses the production app and ProScreen; store responses are a documented fixture.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/features/pro_screen.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/widget_service.dart';

class _ReviewSubscription extends SubscriptionService {
  _ReviewSubscription(String displayPrice) {
    price = displayPrice;
    available = true;
    active = false;
  }
  @override
  bool get trialActive => false;
  @override
  Future<void> refresh() async {}
  @override
  Future<void> purchase() async =>
      throw StateError('Artwork must not purchase');
  @override
  Future<void> restore() async => throw StateError('Artwork must not restore');
}

void main() {
  if (!const bool.fromEnvironment('PRO_REVIEW_CAPTURE')) {
    test('Explicit Pro review artwork export only', () {}, skip: true);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    // This artwork fixture supplies a device calendar response just like the
    // regular store capture fixture. It does not call a native/store service.
    messenger.setMockMethodCallHandler(WidgetService.channel, (call) async {
      if (call.method == 'getCalendarPreferences') {
        return {'regionCode': 'KR', 'firstDayOfWeek': 0};
      }
      throw MissingPluginException('Native calls are outside review artwork');
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
    testWidgets('$language production Pro review artwork', (tester) async {
      const ratio = 3.0;
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = const Size(393, 852) * ratio;
      tester.view.padding = const FakeViewPadding(
        top: 47 * ratio,
        bottom: 34 * ratio,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      addTearDown(() => AppStrings.current = const AppStrings('ko'));
      final controller = PreviewController(sampleLanguage: language);
      await controller.localeController.setPreference(language);
      final displayPrice = language == 'ko' ? '₩900' : r'US$0.69';
      final subscription = _ReviewSubscription(displayPrice);
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
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(strings.t('설정')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byIcon(Icons.auto_graph));
      await tester.tap(find.byIcon(Icons.auto_graph));
      await tester.pumpAndSettle();
      expect(find.byType(ProScreen), findsOneWidget);
      expect(
        find.text(strings.t('{price} / 1년', args: {'price': displayPrice})),
        findsOneWidget,
      );
      expect(find.text(strings.t('1년에 한 번 결제 · 해지 전까지 자동 갱신')), findsOneWidget);
      expect(tester.takeException(), isNull);

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final picture = await boundary.toImage(pixelRatio: ratio);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final file = File('store/review/$language/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }

      await capture('pro-overview');
      await tester.ensureVisible(find.text(strings.t('구매 복원')));
      await capture('pro-purchase');
      await tester.runAsync(() async {
        await File('store/review/$language/source.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert({
            'source': 'Production HangeoreumApp and ProScreen rendered by Flutter widget test',
            'captured_at': DateTime.now().toUtc().toIso8601String(),
            'language': language,
            'product_id': 'hangeoreum_pro_yearly',
            'display_price_fixture': displayPrice,
            'price_source': 'App Store Connect configured yearly price verified 2026-10-11',
            'native_device_capture': false,
            'live_storekit_response': false,
            'purchase_executed': false,
            'dimensions': [1179, 2556],
            'purpose': 'Explain the subscription offering; not evidence of purchase validation',
            'screens': ['pro-overview.png', 'pro-purchase.png'],
          })}\n',
        );
      });
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
