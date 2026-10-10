import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/features/privacy_card.dart';
import 'package:hangeoreum/features/pro_screen.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/services/subscription_service.dart';

class _LocaleSubscription extends SubscriptionService {
  final bool trial;
  int purchases = 0, restores = 0, manages = 0, refreshes = 0;
  _LocaleSubscription({this.trial = false, bool paid = false}) {
    active = paid;
    available = true;
    price = r'US$0.70';
  }
  @override
  bool get trialActive => trial;
  @override
  Future<void> refresh() async => refreshes++;
  @override
  Future<void> purchase() async => purchases++;
  @override
  Future<void> restore() async => restores++;
  @override
  Future<void> manage() async => manages++;
}

Widget _localized(Widget home, String language) => MaterialApp(
  locale: Locale(language),
  supportedLocales: const [Locale('ko'), Locale('en')],
  localizationsDelegates: const [
    AppStrings.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: ThemeData(fontFamily: 'Pretendard'),
  home: home,
);

void _narrowLargeType(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 180, maxScrolls: 100);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });

  testWidgets(
    'English Pro uses store price and keeps billing actions functional',
    (tester) async {
      final subscription = _LocaleSubscription();
      addTearDown(subscription.dispose);
      await tester.pumpWidget(
        _localized(ProScreen(subscription: subscription), 'en'),
      );
      await tester.pumpAndSettle();
      expect(find.text('첫칸 Pro'), findsOneWidget);
      expect(find.text('Always free'), findsOneWidget);
      await _show(tester, find.text(r'US$0.70 / year'));
      expect(
        find.text('Billed once a year · Renews automatically until canceled'),
        findsOneWidget,
      );
      await _show(tester, find.text(r'Subscribe for US$0.70 / year'));
      await tester.tap(find.text(r'Subscribe for US$0.70 / year'));
      await _show(tester, find.text('Restore purchases'));
      await tester.tap(find.text('Restore purchases'));
      await _show(tester, find.text('Manage or cancel subscription'));
      await tester.tap(find.text('Manage or cancel subscription'));
      expect(subscription.purchases, 1);
      expect(subscription.restores, 1);
      expect(subscription.manages, 1);
      await _show(tester, find.text('Terms and privacy information'));
      await tester.tap(find.text('Terms and privacy information'));
      await tester.pumpAndSettle();
      expect(find.text('Terms and privacy'), findsOneWidget);
      expect(
        find.textContaining(
          'The trial does not turn into an automatic payment.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final paid in [false, true]) {
    testWidgets('English Pro fits 320px with 200% text, paid=$paid', (
      tester,
    ) async {
      _narrowLargeType(tester);
      final subscription = _LocaleSubscription(trial: !paid, paid: paid);
      subscription.autoRenewing = false;
      subscription.expires = DateTime(2027, 10, 10);
      addTearDown(subscription.dispose);
      await tester.pumpWidget(
        _localized(ProScreen(subscription: subscription), 'en'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _show(tester, find.byType(FilledButton));
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        paid ? isNull : isNotNull,
      );
      await _show(tester, find.text('Terms and privacy information'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Terms and privacy information'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Terms dialog');
      expect(find.text('Close').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final language in ['ko', 'en']) {
    testWidgets(
      'Privacy card is localized at 320px with 200% text: $language',
      (tester) async {
        _narrowLargeType(tester);
        await tester.pumpWidget(
          _localized(
            const Scaffold(body: SingleChildScrollView(child: PrivacyCard())),
            language,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            language == 'ko'
                ? '나의 일정은, 나의 기기에만'
                : 'Your plans stay on your device',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
