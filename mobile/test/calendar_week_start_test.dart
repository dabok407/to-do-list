import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/home_screen.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:sqflite/sqflite.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Calendar fixtures must not access the database');
}

class _CalendarController extends TaskController {
  _CalendarController()
    : super(TaskRepository(_UnusedDatabase()), ReminderScheduler());

  @override
  Future<void> refresh({DateTime? through}) async => notifyListeners();

  @override
  Future<void> reconcile() async => notifyListeners();
}

class _TrialSubscription extends SubscriptionService {
  @override
  bool get hasAccess => true;
  @override
  bool get paidAccess => false;
  @override
  bool get trialActive => true;
  @override
  Future<void> refresh() async {}
}

Future<_CalendarController> _home(
  WidgetTester tester,
  Locale locale, {
  List<DateTime> dueDates = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1100);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = _CalendarController();
  final subscription = _TrialSubscription();
  addTearDown(controller.dispose);
  addTearDown(subscription.dispose);
  for (var index = 0; index < dueDates.length; index++) {
    final due = dueDates[index];
    final task = Task(
      id: 'calendar-$index',
      title: 'Calendar task $index',
      due: due,
      created: DateTime.now(),
    );
    controller.items.add(
      Occurrence(
        id: '${task.id}@${due.toIso8601String()}',
        task: task,
        originalDue: due,
        reminder: due,
      ),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: [locale],
      localizationsDelegates: [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: HomeScreen(controller: controller, subscription: subscription),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

List<DateTime> _renderedDates(WidgetTester tester) => tester
    .widgetList<InkWell>(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byType(InkWell),
      ),
    )
    .map((widget) {
      final key = (widget.key! as ValueKey<String>).value;
      return DateTime.parse(key.substring('calendar-date-'.length));
    })
    .toList();

void main() {
  test('Sunday-first month layouts cover four, five and six rows', () {
    expect(calendarMonthCellCount(DateTime(2026, 2), 0), 28);
    expect(calendarMonthCellCount(DateTime(2026, 10), 0), 35);
    expect(calendarMonthCellCount(DateTime(2026, 8), 0), 42);
    expect(calendarWeekStart(DateTime(2026, 1, 1), 0), DateTime(2025, 12, 28));
    expect(calendarWeekStart(DateTime(2026, 2, 1), 0), DateTime(2026, 2, 1));
    expect(calendarWeekStart(DateTime(2026, 2, 1), 1), DateTime(2026, 1, 26));
  });

  test('every Gregorian month has complete locale-aligned boundary weeks', () {
    // One Gregorian cycle includes leap years and the non-leap century 2100.
    for (var year = 2000; year < 2400; year++) {
      for (var month = 1; month <= 12; month++) {
        final first = DateTime(year, month);
        final last = DateTime(year, month + 1, 0);
        for (final firstDay in [0, 1]) {
          final start = calendarWeekStart(first, firstDay);
          final count = calendarMonthCellCount(first, firstDay);
          final end = DateTime(start.year, start.month, start.day + count - 1);
          expect(start.weekday % 7, firstDay);
          expect(start.isAfter(first), isFalse);
          expect(first.difference(start).inDays, lessThan(7));
          expect(count, anyOf(28, 35, 42));
          expect(end.isBefore(last), isFalse);
          expect(end.difference(last).inDays, lessThan(7));
          expect(end.weekday % 7, (firstDay + 6) % 7);
        }
      }
    }
  });

  test('display weeks do not change the Monday-based recurrence week', () {
    final sunday = DateTime(2026, 10, 11);
    expect(calendarWeekStart(sunday, 0), sunday);
    expect(weekOf(sunday), DateTime(2026, 10, 5));
  });

  for (final (locale, firstDay) in [
    (const Locale('ko'), 0),
    (const Locale('en'), 0),
    (const Locale('en', 'GB'), 1),
  ]) {
    final label = locale.toLanguageTag();
    final strings = AppStrings(locale.languageCode);
    testWidgets('$label headers and month grid use the same week start', (
      tester,
    ) async {
      await _home(tester, locale);
      final today = DateTime.now();
      final month = DateTime(today.year, today.month);
      final start = calendarWeekStart(month, firstDay);
      final headers = List.generate(
        7,
        (index) => (firstDay + index + 6) % 7 + 1,
      );
      var previousX = -double.infinity;
      for (final weekday in headers) {
        final header = find.byKey(Key('calendar-weekday-$weekday'));
        final text = tester.widget<Text>(header);
        expect(text.data, strings.weekday(weekday));
        expect(tester.getCenter(header).dx, greaterThan(previousX));
        previousX = tester.getCenter(header).dx;
        expect(
          text.style!.color,
          weekday == DateTime.sunday ? priorityRed : mutedText,
        );
      }
      final dates = _renderedDates(tester);
      expect(dates.first, start);
      expect(dates.length, calendarMonthCellCount(month, firstDay));
      for (var index = 0; index < dates.length; index++) {
        expect(
          dates[index],
          DateTime(start.year, start.month, start.day + index),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$label selected boundary date opens and navigates its week', (
      tester,
    ) async {
      await _home(tester, locale);
      // The first grid cell may belong to the previous month/year.
      final chosen = _renderedDates(tester).first;
      await tester.tap(find.byKey(Key('calendar-date-${dayKey(chosen)}')));
      await tester.pumpAndSettle();
      expect(find.text(strings.t('월 보기')), findsOneWidget);
      final start = calendarWeekStart(chosen, firstDay);
      expect(_renderedDates(tester).first, start);
      expect(_renderedDates(tester).length, 7);
      await tester.tap(find.byTooltip(strings.t('다음')));
      await tester.pumpAndSettle();
      expect(
        _renderedDates(tester).first,
        DateTime(start.year, start.month, start.day + 7),
      );
      await tester.tap(find.byTooltip(strings.t('이전')));
      await tester.pumpAndSettle();
      expect(_renderedDates(tester).first, start);
      await tester.tap(find.text(strings.t('월 보기')));
      await tester.pumpAndSettle();
      final selectedMonth = DateTime(chosen.year, chosen.month);
      expect(
        _renderedDates(tester).first,
        calendarWeekStart(selectedMonth, firstDay),
      );
      expect(
        _renderedDates(tester).length,
        calendarMonthCellCount(selectedMonth, firstDay),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$label weekly summary includes its first and last days', (
      tester,
    ) async {
      final start = calendarWeekStart(DateTime.now(), firstDay);
      await _home(
        tester,
        locale,
        dueDates: [
          start,
          DateTime(start.year, start.month, start.day + 6),
          DateTime(start.year, start.month, start.day - 1),
        ],
      );
      final summary = find.byTooltip(strings.t('요약 기간'));
      await tester.ensureVisible(summary);
      await tester.tap(summary);
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.t('이번 주')).last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          strings.t('{left}개 남음  ·  {done}개 완료', args: {'left': 2, 'done': 0}),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
