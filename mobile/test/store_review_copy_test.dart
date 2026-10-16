import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/features/privacy_card.dart';
import 'package:hangeoreum/features/pro_screen.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/services/subscription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const billing = MethodChannel('com.dabok407.hangeoreum/billing');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(billing, null);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final language in ['ko', 'en']) {
      testWidgets(
        '$platform $language Pro keeps billing disclosures without other platform names',
        (tester) async {
          messenger.setMockMethodCallHandler(
            billing,
            (_) async => {
              'active': false,
              'available': true,
              'price': language == 'ko' ? '₩900' : r'$0.69',
            },
          );
          final subscription = SubscriptionService();
          addTearDown(subscription.dispose);
          await tester.pumpWidget(
            _localized(language, ProScreen(subscription: subscription)),
          );
          await tester.pumpAndSettle();

          final content = StringBuffer();
          final scrollable = find.byType(Scrollable).first;
          for (var step = 0; step < 30; step++) {
            content.writeln(_visibleText(tester));
            final position = tester.state<ScrollableState>(scrollable).position;
            if (position.pixels >= position.maxScrollExtent) break;
            await tester.drag(find.byType(ListView), const Offset(0, -350));
            await tester.pumpAndSettle();
          }
          content.writeln(_visibleText(tester));

          final copy = content.toString();
          expect(copy, isNot(matches(RegExp(r'Android|Google|Google Play'))));
          if (language == 'ko') {
            expect(copy, contains('₩900 / 1년'));
            expect(copy, contains('해지 전까지 자동 갱신'));
            expect(copy, contains('구매 복원'));
            expect(copy, contains('구독 관리·해지'));
            expect(copy, contains('구매한 스토어의 같은 계정'));
            expect(copy, contains('스토어와 통신합니다'));
            expect(copy, contains('기록이 사라질 수 있어요'));
          } else {
            expect(copy, contains(r'$0.69 / year'));
            expect(copy, contains('Renews automatically until canceled'));
            expect(copy, contains('Restore purchases'));
            expect(copy, contains('Manage or cancel subscription'));
            expect(
              copy,
              contains('same account in the store where you purchased'),
            );
            expect(copy, contains('connect to the store on your device'));
            expect(copy, contains('may erase your records'));
            expect(copy, isNot(matches(RegExp('[가-힣]'))));
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: TargetPlatformVariant({platform}),
      );

      testWidgets(
        '$platform $language standalone privacy card is store-neutral',
        (tester) async {
          await tester.pumpWidget(
            _localized(
              language,
              const Scaffold(body: SingleChildScrollView(child: PrivacyCard())),
            ),
          );
          await tester.pumpAndSettle();
          final copy = _visibleText(tester);
          expect(copy, isNot(matches(RegExp(r'Android|Google|Google Play'))));
          expect(
            copy,
            contains(
              language == 'ko' ? '운영자 서버로 보내지 않아요' : 'not sent to our servers',
            ),
          );
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({platform}),
      );
    }
  }
}

Widget _localized(String language, Widget home) => MaterialApp(
  locale: Locale(language),
  supportedLocales: const [Locale('ko'), Locale('en')],
  localizationsDelegates: const [
    AppStrings.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

String _visibleText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
    .join('\n');
