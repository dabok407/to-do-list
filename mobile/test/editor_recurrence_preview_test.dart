import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/task_editor.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Task _task({
  RepeatUnit repeat = RepeatUnit.weekly,
  int interval = 2,
  DateTime? end,
}) => Task(
  id: 'repeat-preview',
  title: '주간 정리',
  due: DateTime(2090, 10, 27, 12), // Friday; safely future for clock-based UI.
  created: DateTime(2090, 10, 1),
  repeat: repeat,
  interval: interval,
  weekdays: const [5],
  end: end,
  countPerWeek: 2,
);

Widget _app(Task task, {String language = 'ko'}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: const [Locale('ko'), Locale('en')],
  localizationsDelegates: const [
    AppStrings.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: ThemeData(fontFamily: 'Pretendard'),
  home: TaskEditor(task: task, initialDate: task.due),
);

Finder get _preview => find.byKey(const Key('recurrence-preview'));
Finder _previewText(String text) =>
    find.descendant(of: _preview, matching: find.text(text));

void _size(WidgetTester tester, double width, double scale) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 812);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });

  for (final language in ['ko', 'en']) {
    for (final width in [375.0, 402.0]) {
      testWidgets('$language $width repeat days fit one row and preview fits', (
        tester,
      ) async {
        _size(tester, width, 1);
        await tester.pumpWidget(_app(_task(), language: language));
        await tester.pumpAndSettle();
        final weekdays = find.byKey(const Key('repeat-weekdays-single-row'));
        await tester.ensureVisible(weekdays);
        await tester.pumpAndSettle();
        expect(weekdays, findsOneWidget);
        final top = tester
            .getTopLeft(find.byKey(const Key('repeat-weekday-1')))
            .dy;
        for (var day = 1; day <= 7; day++) {
          final chip = find.byKey(Key('repeat-weekday-$day'));
          expect(tester.getTopLeft(chip).dy, top);
          expect(tester.getSize(chip).width, greaterThanOrEqualTo(44));
        }
        await tester.ensureVisible(_preview);
        await tester.pumpAndSettle();
        expect(
          _previewText(language == 'ko' ? '다음 3회' : 'Next 3 occurrences'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('recurrence-preview-date-2')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
    for (final scale in [2.0, 3.0]) {
      testWidgets(
        '$language ${scale}x large text remains readable without overflow',
        (tester) async {
          _size(tester, 320, scale);
          await tester.pumpWidget(_app(_task(), language: language));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const Key('repeat-weekday-7')));
          await tester.pumpAndSettle();
          for (var day = 1; day <= 7; day++) {
            final chip = find.byKey(Key('repeat-weekday-$day'));
            final label = find.descendant(
              of: chip,
              matching: find.byType(Text),
            );
            final paragraph = tester.renderObject<RenderParagraph>(label);
            final text = tester.widget<Text>(label).data!;
            final bounds = tester.getRect(chip);
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: text.length),
            );
            expect(boxes, isNotEmpty);
            for (final box in boxes) {
              final top = paragraph.localToGlobal(Offset(box.left, box.top));
              final bottom = paragraph.localToGlobal(
                Offset(box.right, box.bottom),
              );
              expect(top.dy, greaterThanOrEqualTo(bounds.top));
              expect(bottom.dy, lessThanOrEqualTo(bounds.bottom));
            }
          }
          await tester.ensureVisible(_preview);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('repeat-weekday-7')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('interval and weekday edits immediately update actual dates', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_task()));
    await tester.pumpAndSettle();
    expect(_previewText('2090년 11월 10일 (금)'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('editor-interval')));
    await tester.enterText(find.byKey(const Key('editor-interval')), '3');
    await tester.pumpAndSettle();
    expect(_previewText('2090년 11월 17일 (금)'), findsOneWidget);
    expect(_previewText('2090년 11월 10일 (금)'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('repeat-weekday-5')));
    await tester.tap(find.byKey(const Key('repeat-weekday-5')));
    await tester.pumpAndSettle();
    expect(_previewText('반복할 요일을 선택해주세요'), findsOneWidget);
    expect(find.byKey(const Key('recurrence-preview-date-0')), findsNothing);
    await tester.tap(find.byKey(const Key('repeat-weekday-6')));
    await tester.pumpAndSettle();
    expect(_previewText('2090년 10월 28일 (토)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid interval removes misleading preview dates', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_task()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('editor-interval')));
    await tester.enterText(find.byKey(const Key('editor-interval')), '0');
    await tester.pumpAndSettle();
    expect(_previewText('1~365를 입력해주세요'), findsOneWidget);
    expect(find.byKey(const Key('recurrence-preview-date-0')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inclusive end date and clear end date update preview count', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_task(end: DateTime(2090, 11, 10))));
    await tester.pumpAndSettle();
    expect(_previewText('다음 2회'), findsOneWidget);
    expect(find.byKey(const Key('recurrence-preview-date-2')), findsNothing);
    await tester.ensureVisible(find.text('종료 날짜 해제'));
    await tester.tap(find.text('종료 날짜 해제'));
    await tester.pumpAndSettle();
    expect(_previewText('다음 3회'), findsOneWidget);
    expect(find.byKey(const Key('recurrence-preview-date-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('date and time picker changes refresh all preview rows', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_task(), language: 'en'));
    await tester.pumpAndSettle();
    final dateField = find.byKey(const Key('editor-date'));
    await tester.ensureVisible(dateField);
    await tester.tap(dateField);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final dateInput = find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(dateInput, '11/3/2090');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(_previewText('Fri, Nov 3, 2090'), findsOneWidget);
    expect(_previewText('Fri, Nov 17, 2090'), findsOneWidget);
    expect(_previewText('Fri, Dec 1, 2090'), findsOneWidget);

    final timeField = find.byKey(const Key('editor-time'));
    await tester.ensureVisible(timeField);
    await tester.tap(timeField);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final inputs = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(inputs.at(0), '2');
    await tester.enterText(inputs.at(1), '45');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(_previewText('2:45 PM'), findsNWidgets(3));
    expect(_previewText('12:00 PM'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly goal labels possible days and once has no preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_task(repeat: RepeatUnit.weeklyGoal), language: 'en'),
    );
    await tester.pumpAndSettle();
    expect(_previewText('Next available days'), findsOneWidget);
    expect(
      _previewText(
        'Available days for your goal of 2 per week. Reminders stop for the rest of the week once you reach it.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(_task(repeat: RepeatUnit.none)));
    await tester.pumpAndSettle();
    expect(_preview, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
