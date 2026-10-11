import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/features/persistent_time_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _host(
  WidgetTester tester, {
  String language = 'en',
  ValueChanged<TimeOfDay?>? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await showPersistentTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 14, minute: 37),
              );
              onResult?.call(result);
            },
            child: const Text('Pick time'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Pick time'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final stored in [null, 'dial', 'invalid']) {
    testWidgets('default dial when stored mode is $stored', (tester) async {
      SharedPreferences.setMockInitialValues(
        stored == null ? {} : {timePickerEntryModePreference: stored},
      );
      await _host(tester);
      await _open(tester);
      expect(
        tester
            .widget<TimePickerDialog>(find.byType(TimePickerDialog))
            .initialEntryMode,
        TimePickerEntryMode.dial,
      );
      expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in ['ko', 'en']) {
    testWidgets('$language remembers numeric input after fresh app mount', (
      tester,
    ) async {
      TimeOfDay? saved;
      await _host(
        tester,
        language: language,
        onResult: (value) => saved = value,
      );
      await _open(tester);
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(2));
      await tester.tap(find.text(language == 'ko' ? '확인' : 'OK'));
      await tester.pumpAndSettle();
      expect(saved, const TimeOfDay(hour: 14, minute: 37));
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(timePickerEntryModePreference), 'input');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _host(tester, language: language);
      await _open(tester);
      expect(
        tester
            .widget<TimePickerDialog>(find.byType(TimePickerDialog))
            .initialEntryMode,
        TimePickerEntryMode.input,
      );
      expect(find.byIcon(Icons.access_time), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancel preserves mode choice without saving a selected time', (
    tester,
  ) async {
    var completed = false;
    TimeOfDay? saved = const TimeOfDay(hour: 1, minute: 1);
    await _host(
      tester,
      onResult: (value) {
        completed = true;
        saved = value;
      },
    );
    await _open(tester);
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(saved, isNull);
    await _open(tester);
    expect(find.byIcon(Icons.access_time), findsOneWidget);
    await tester.tap(find.byIcon(Icons.access_time));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(saved, const TimeOfDay(hour: 14, minute: 37));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(timePickerEntryModePreference), 'dial');
    await _open(tester);
    expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
