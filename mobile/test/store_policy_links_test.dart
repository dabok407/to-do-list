import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/features/store_policy_links.dart';
import 'package:hangeoreum/l10n/app_strings.dart';

void main() {
  for (final language in ['ko', 'en']) {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets(
        'Public links open the correct documents: $language $platform',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final opened = <Uri>[];
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('ko'), Locale('en')],
              localizationsDelegates: const [
                AppStrings.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              home: Scaffold(
                body: StorePolicyLinks(
                  open: (uri) async {
                    opened.add(uri);
                    return true;
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final label
              in language == 'ko'
                  ? ['고객 지원', '개인정보처리방침', '이용약관']
                  : ['Support', 'Privacy policy', 'Terms of use']) {
            final button = find.widgetWithText(TextButton, label);
            expect(button.hitTestable(), findsOneWidget);
            expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
            await tester.tap(button);
            await tester.pumpAndSettle();
          }
          final suffix = language == 'en' ? '-en' : '';
          expect(opened.map((uri) => uri.toString()).toList(), [
            '${StorePolicyLinks.site}/support$suffix.html',
            '${StorePolicyLinks.site}/privacy$suffix.html',
            platform == TargetPlatform.iOS
                ? StorePolicyLinks.appleTerms
                : '${StorePolicyLinks.site}/terms$suffix.html',
          ]);
          expect(
            opened.every((uri) => uri.scheme == 'https' && !uri.hasQuery),
            isTrue,
          );
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }

  testWidgets(
    'Browser failure shows a useful message without losing the screen',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
          home: Scaffold(
            body: StorePolicyLinks(
              open: (_) async => throw StateError('No browser'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Privacy policy'));
      await tester.pump();
      expect(
        find.text('Could not open the browser. Please try again shortly.'),
        findsOneWidget,
      );
      expect(find.text('Support'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
