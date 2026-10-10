import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/task_editor.dart';
import 'package:hangeoreum/l10n/app_strings.dart';

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

Task _fixture({RepeatUnit repeat = RepeatUnit.none, String category = '생활'}) =>
    Task(
      id: 'locale-task',
      title: '안방 대청소',
      note: '바구니에 옷을 모아두기',
      smallStep: '옷 한 벌 정리하기',
      due: DateTime(2026, 10, 10, 19),
      created: DateTime(2026, 10, 1),
      priority: 2,
      category: category,
      repeat: repeat,
      weekdays: const [1],
      end: DateTime(2027, 12, 31),
      overdueDays: 3,
      overdueMinute: 12 * 60,
      countPerWeek: 2,
    );

void _narrowLargeType(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });

  testWidgets(
    'English editor preserves user text and custom category on save',
    (tester) async {
      final task = _fixture(category: '내 분류');
      Task? result;
      await tester.pumpWidget(
        _localized(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await Navigator.push<Task>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TaskEditor(task: task, initialDate: task.due),
                      ),
                    );
                  },
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
          'en',
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      expect(find.text('Edit task'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('내 분류'), findsOneWidget);
      expect(find.text('10/10/2026'), findsOneWidget);
      expect(find.text('7:00 PM'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result?.title, task.title);
      expect(result?.note, task.note);
      expect(result?.smallStep, task.smallStep);
      expect(result?.category, '내 분류');
      expect(result?.priority, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'English editor translates built-in labels without changing keys',
    (tester) async {
      final task = _fixture(repeat: RepeatUnit.weekly);
      await tester.pumpWidget(
        _localized(TaskEditor(task: task, initialDate: task.due), 'en'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Weekly · choose days'), findsOneWidget);
      expect(find.text('Mon'), findsOneWidget);
      final monday = find.widgetWithText(FilterChip, 'Mon');
      await tester.ensureVisible(monday);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(monday).selected, isTrue);
      await tester.tap(monday);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(monday).selected, isFalse);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Choose at least one repeat day'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['ko', 'en']) {
    testWidgets('$language empty-title validation is localized', (
      tester,
    ) async {
      await tester.pumpWidget(
        _localized(TaskEditor(initialDate: DateTime(2026, 10, 10)), language),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(language == 'ko' ? '저장' : 'Save'));
      await tester.pumpAndSettle();
      expect(
        find.text(language == 'ko' ? '제목을 입력해주세요' : 'Enter a task title'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('English date and time dialogs use native English controls', (
    tester,
  ) async {
    final task = _fixture(repeat: RepeatUnit.monthlyWeekday);
    await tester.pumpWidget(
      _localized(TaskEditor(task: task, initialDate: task.due), 'en'),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('10/10/2026'));
    await tester.tap(find.text('10/10/2026'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('7:00 PM'));
    await tester.tap(find.text('7:00 PM'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('English overdue help follows the selected reminder interval', (
    tester,
  ) async {
    final due = DateTime(2026, 10, 10, 12);
    final task = Task(
      id: 'reminder-locale',
      title: 'Filter cleaning',
      due: due,
      created: due,
    );
    await tester.pumpWidget(
      _localized(TaskEditor(task: task, initialDate: due), 'en'),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Overdue reminders'));
    await tester.tap(find.text('Overdue reminders'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reminders start 1 day after'), findsOneWidget);
    final interval = find.byKey(const Key('overdue-interval'));
    await tester.ensureVisible(interval);
    await tester.pumpAndSettle();
    await tester.tap(interval);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every 3 days').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Reminders start 3 days after'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final repeat in RepeatUnit.values) {
    testWidgets('English ${repeat.name} editor fits 320px with 200% text', (
      tester,
    ) async {
      _narrowLargeType(tester);
      final task = _fixture(repeat: repeat);
      await tester.pumpWidget(
        _localized(TaskEditor(task: task, initialDate: task.due), 'en'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final dropdown = find.byType(DropdownButtonFormField<RepeatUnit>);
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Repeat menu');
      final label = switch (repeat) {
        RepeatUnit.none => 'Once',
        RepeatUnit.daily => 'Daily',
        RepeatUnit.weekly => 'Weekly · choose days',
        RepeatUnit.monthly => 'Monthly · same date',
        RepeatUnit.monthlyWeekday => 'Monthly · weekday',
        RepeatUnit.weeklyGoal => 'Weekly goal · any day',
      };
      final item = find.text(label).last;
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
      if (repeat != RepeatUnit.none) {
        await tester.ensureVisible(find.text('Clear end date'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'End-date section');
      }
      await tester.ensureVisible(find.text('Overdue reminders'));
      await tester.tap(find.text('Overdue reminders'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('overdue-interval')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Overdue section');
      expect(find.text('Save').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
