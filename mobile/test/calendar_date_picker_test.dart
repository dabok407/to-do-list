import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/features/calendar_date_picker.dart';
import 'package:hangeoreum/features/popup_theme.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/l10n/device_calendar_localizations.dart';

Future<void> openPicker(
  WidgetTester tester, {
  String language = 'en',
  int firstDay = 0,
  DateTime? initial,
  DateTime? minimum,
  required ValueChanged<DateTime?> onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('en'), Locale('ko')],
      localizationsDelegates: [
        AppStrings.delegate,
        DeviceCalendarMaterialDelegate(firstDayOfWeekIndex: firstDay),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: ThemeData(
        useMaterial3: true,
        bottomSheetTheme: TodoniqPopupTheme.bottomSheet,
        datePickerTheme: TodoniqPopupTheme.datePicker,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => onResult(
              await showTodoniqDatePicker(
                context: context,
                initialDate: initial ?? DateTime(2026, 11, 7),
                firstDate: minimum ?? DateTime(2020),
                lastDate: DateTime(2100),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('calendar change is a draft; cancel discards it', (tester) async {
    DateTime? result = DateTime(2020);
    await openPicker(tester, onResult: (value) => result = value);
    await tester.tap(find.text('18'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2020));
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmation returns the selected date without a time component',
    (tester) async {
      DateTime? result;
      await openPicker(
        tester,
        initial: DateTime(2026, 11, 7, 19, 42),
        onResult: (value) => result = value,
      );
      await tester.tap(find.text('18'));
      await tester.tap(find.byKey(const Key('picker-confirm')));
      await tester.pumpAndSettle();
      expect(result, DateTime(2026, 11, 18));
    },
  );

  testWidgets('manual entry validates format and bounds before returning', (
    tester,
  ) async {
    DateTime? result;
    await openPicker(
      tester,
      minimum: DateTime(2026, 11, 7),
      onResult: (value) => result = value,
    );
    await tester.tap(find.byKey(const Key('date-picker-entry-toggle')));
    await tester.pumpAndSettle();
    final field = find.byType(TextFormField);
    for (final invalid in ['wrong', '11/1/2026']) {
      await tester.enterText(field, invalid);
      await tester.tap(find.byKey(const Key('picker-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('date-picker-input')), findsOneWidget);
      expect(result, isNull);
    }
    await tester.enterText(field, '12/25/2026');
    await tester.tap(find.byKey(const Key('picker-confirm')));
    await tester.pumpAndSettle();
    expect(result, DateTime(2026, 12, 25));
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to calendar preserves a valid manually entered date', (
    tester,
  ) async {
    DateTime? result;
    await openPicker(tester, onResult: (value) => result = value);
    final toggle = find.byKey(const Key('date-picker-entry-toggle'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'invalid');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('date-picker-input')), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '12/25/2026');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .initialDate,
      DateTime(2026, 12, 25),
    );
    expect(result, isNull);
    await tester.tap(find.byKey(const Key('picker-confirm')));
    await tester.pumpAndSettle();
    expect(result, DateTime(2026, 12, 25));
  });

  for (final language in ['ko', 'en']) {
    testWidgets(
      '$language date sheet preserves device week start at 320px and large text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await openPicker(
          tester,
          language: language,
          firstDay: 1,
          onResult: (_) {},
        );
        final calendar = find.byType(CalendarDatePicker);
        if (language == 'en') {
          expect(find.text('Nov 2026'), findsOneWidget);
        }
        expect(
          MaterialLocalizations.of(tester.element(calendar))
              .firstDayOfWeekIndex,
          1,
        );
        expect(
          find.byKey(const Key('picker-confirm')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byTooltip(language == 'ko' ? '취소' : 'Cancel').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip(language == 'ko' ? '취소' : 'Cancel'));
        await tester.pumpAndSettle();
      },
    );
  }
}
