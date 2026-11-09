import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/features/persistent_time_picker.dart';
import 'package:hangeoreum/features/picker_sheet.dart';
import 'package:hangeoreum/features/popup_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _captureBoundary = GlobalKey();

Future<void> _host(
  WidgetTester tester, {
  String language = 'en',
  bool use24h = true,
  Size size = const Size(375, 812),
  double textScale = 1,
  TimeOfDay initial = const TimeOfDay(hour: 14, minute: 37),
  ValueChanged<TimeOfDay?>? onResult,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureBoundary,
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          fontFamily: 'Pretendard',
          colorScheme: ColorScheme.fromSeed(
            seedColor: TodoniqPopupTheme.ink,
            primary: TodoniqPopupTheme.ink,
            surface: TodoniqPopupTheme.surface,
          ),
          bottomSheetTheme: TodoniqPopupTheme.bottomSheet,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: use24h,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await showPersistentTimePicker(
                  context: context,
                  initialTime: initial,
                );
                onResult?.call(result);
              },
              child: const Text('Pick time'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pick time'));
  await tester.pumpAndSettle();
}

CupertinoPicker _wheel(WidgetTester tester, int index) =>
    tester.widget<CupertinoPicker>(find.byType(CupertinoPicker).at(index));

Future<void> _confirm(WidgetTester tester) async {
  final confirm = find.byKey(const Key('picker-confirm'));
  await tester.ensureVisible(confirm);
  await tester.pumpAndSettle();
  await tester.tap(confirm);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final language in ['ko', 'en']) {
    testWidgets(
      '$language selected wheel digits stay visible below the overlay',
      (tester) async {
        await _host(tester, language: language, use24h: false);
        final boundary =
            _captureBoundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final capture = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final width = image.width;
          image.dispose();
          return (pixels, width);
        });
        final (pixels, width) = capture!;
        for (final wheel in find.byType(CupertinoPicker).evaluate()) {
          final rect = tester.getRect(
            find.byElementPredicate((element) => element == wheel),
          );
          var visibleInk = 0;
          for (
            var y = (rect.center.dy - 20).ceil();
            y < rect.center.dy + 20;
            y++
          ) {
            for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
              final offset = (y * width + x) * 4;
              if (pixels.getUint8(offset) < 110 &&
                  pixels.getUint8(offset + 1) < 110 &&
                  pixels.getUint8(offset + 2) < 110) {
                visibleInk++;
              }
            }
          }
          expect(
            visibleInk,
            greaterThan(30),
            reason: 'Every selected hour, minute and AM/PM value must be visibly painted.',
          );
        }
        await _confirm(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in ['ko', 'en']) {
    for (final use24h in [true, false]) {
      testWidgets('$language picker follows device 24h=$use24h', (
        tester,
      ) async {
        TimeOfDay? saved;
        await _host(
          tester,
          language: language,
          use24h: use24h,
          onResult: (value) => saved = value,
        );
        final picker = tester.widget<CupertinoDatePicker>(
          find.byKey(const Key('time-wheel-picker')),
        );
        expect(picker.use24hFormat, use24h);
        expect(find.byType(CupertinoPicker), findsNWidgets(use24h ? 2 : 3));
        expect(
          find.text(language == 'ko' ? '시간 선택' : 'Choose time'),
          findsOneWidget,
        );
        expect(find.byType(TextFormField), findsNothing);
        await _confirm(tester);
        expect(saved, const TimeOfDay(hour: 14, minute: 37));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('old numeric preference does not reopen obsolete dial UI', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      timePickerEntryModePreference: 'input',
    });
    await _host(tester);
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.byType(TimePickerDialog), findsNothing);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wheel selections commit only when confirmed, including midnight',
    (tester) async {
      TimeOfDay? saved;
      await _host(
        tester,
        initial: const TimeOfDay(hour: 23, minute: 59),
        onResult: (value) => saved = value,
      );
      _wheel(tester, 0).scrollController!.jumpToItem(24);
      _wheel(tester, 1).scrollController!.jumpToItem(60);
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await _confirm(tester);
      expect(saved, const TimeOfDay(hour: 0, minute: 0));
      expect(tester.takeException(), isNull);
    },
  );

  for (final dismiss in ['close', 'barrier', 'back']) {
    testWidgets('$dismiss discards the wheel draft', (tester) async {
      var returned = false;
      TimeOfDay? result = const TimeOfDay(hour: 1, minute: 1);
      await _host(
        tester,
        onResult: (value) {
          returned = true;
          result = value;
        },
      );
      _wheel(tester, 1).scrollController!.jumpToItem(45);
      await tester.pumpAndSettle();
      if (dismiss == 'close') {
        await tester.tap(find.byTooltip('Cancel'));
      } else if (dismiss == 'barrier') {
        await tester.tapAt(const Offset(10, 120));
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result, isNull);
      expect(find.byType(TodoniqPickerSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('confirmation waits until a moving wheel settles', (
    tester,
  ) async {
    TimeOfDay? saved;
    await _host(tester, onResult: (value) => saved = value);
    final minute = find.byType(CupertinoPicker).at(1);
    final gesture = await tester.startGesture(tester.getCenter(minute));
    await gesture.moveBy(const Offset(0, -65));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('picker-confirm')))
          .onPressed,
      isNull,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    final selectedMinute =
        _wheel(tester, 1).scrollController!.selectedItem % 60;
    expect(selectedMinute, isNot(37));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('picker-confirm')))
          .onPressed,
      isNotNull,
    );
    await _confirm(tester);
    expect(saved?.minute, selectedMinute);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancelling during wheel motion leaves no notifier callback error',
    (tester) async {
      await _host(tester);
      await tester.fling(
        find.byType(CupertinoPicker).at(1),
        const Offset(0, -140),
        1500,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(TodoniqPickerSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['ko', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(375, 812),
      const Size(812, 375),
    ]) {
      testWidgets(
        '$language ${size.width}x${size.height} large-text picker remains usable',
        (tester) async {
          await _host(
            tester,
            language: language,
            size: size,
            textScale: 2,
            use24h: false,
          );
          expect(tester.takeException(), isNull);
          final pickerRect = tester.getRect(find.byType(CupertinoDatePicker));
          expect(pickerRect.width, lessThanOrEqualTo(size.width));
          await _confirm(tester);
          expect(find.byType(TodoniqPickerSheet), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
