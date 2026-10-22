import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/statistics_breakdown.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/statistics_panel.dart';
import 'package:hangeoreum/features/visual_tokens.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _now = DateTime(2026, 10, 20, 12);

Occurrence _occurrence(
  String id, {
  DateTime? due,
  DateTime? completed,
  TaskStatus status = TaskStatus.pending,
  String category = '생활',
  int priority = 1,
  bool quotaSkipped = false,
}) {
  final date = due ?? _now.subtract(const Duration(days: 1));
  return Occurrence(
    id: id,
    task: Task(
      id: id,
      title: id,
      created: date,
      due: date,
      category: category,
      priority: priority,
    ),
    originalDue: date,
    reminder: date,
    status: status,
    completed: completed,
    quotaSkipped: quotaSkipped,
  );
}

/// The tabs describe the same 55 targets and 40 completions. Priority rates
/// are 9/12, 24/32 and 7/11; category counts are 9, 15, 8, 6 and 2.
List<Occurrence> _comparisonItems() {
  final completedCategories = [
    for (final entry in const {
      '생활': 9,
      '업무': 15,
      '건강': 8,
      '배움': 6,
      '기타': 2,
    }.entries)
      for (var i = 0; i < entry.value; i++) entry.key,
  ];
  final pendingCategories = [
    for (final entry in const {
      '생활': 5,
      '업무': 6,
      '건강': 1,
      '배움': 2,
      '기타': 1,
    }.entries)
      for (var i = 0; i < entry.value; i++) entry.key,
  ];
  return [
    for (var i = 0; i < completedCategories.length; i++)
      _occurrence(
        'completed-$i',
        completed: _now.subtract(const Duration(hours: 2)),
        status: TaskStatus.completed,
        category: completedCategories[i],
        priority: i < 9 ? 2 : (i < 33 ? 1 : 0),
      ),
    for (var i = 0; i < pendingCategories.length; i++)
      _occurrence(
        'pending-$i',
        category: pendingCategories[i],
        priority: i < 3 ? 2 : (i < 11 ? 1 : 0),
      ),
  ];
}

String _texts(WidgetTester tester, Finder parent) => tester
    .widgetList<Text>(find.descendant(of: parent, matching: find.byType(Text)))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join(' ');

void _expectSummary(
  WidgetTester tester, {
  required int total,
  required int completed,
  String language = 'ko',
}) {
  final strings = AppStrings(language);
  final rate = total == 0 ? '—' : '${(completed / total * 100).round()}%';
  final summary = find.byKey(const Key('statistics-summary'));
  expect(summary, findsOneWidget);
  expect(
    tester.widget<Semantics>(summary).properties.label,
    strings.t(
      '완료율 {rate}, 집계한 회차 {total}개 중 {done}개 완료',
      args: {'rate': rate, 'total': total, 'done': completed},
    ),
  );
  expect(
    _texts(tester, summary),
    strings.t(
      '집계 {total}회 중 {done}회 완료 · {rate}',
      args: {'total': total, 'done': completed, 'rate': rate},
    ),
  );
}

OutlinedButton _resetButton(WidgetTester tester) => tester
    .widget<OutlinedButton>(find.byKey(const Key('statistics-period-reset')));

void _expectCategoryIdentity(
  WidgetTester tester,
  Finder scope,
  String category,
  AppStrings strings,
) {
  final badge = find.descendant(
    of: scope,
    matching: find.byType(CategoryLabel),
  );
  expect(badge, findsOneWidget);
  final identity = tester.widget<CategoryLabel>(badge);
  expect(identity.category, category);
  expect(identity.label, strings.category(category));
  final icon = find.descendant(of: badge, matching: find.byType(Icon));
  final text = find.descendant(of: badge, matching: find.byType(Text));
  expect(tester.widget<Icon>(icon).icon, TaskVisuals.categoryIcon(category));
  expect(tester.widget<Icon>(icon).color, TaskVisuals.categoryInk(category));
  expect(tester.widget<Icon>(icon).size, 16);
  final label = tester.widget<Text>(text);
  expect(label.style?.fontSize, 13);
  expect(label.style?.fontWeight, FontWeight.w500);
  expect(label.style?.color, TaskVisuals.ink);
  expect(
    tester.getRect(text).left - tester.getRect(icon).right,
    closeTo(6, .1),
  );
}

Future<double> _expectDetailAlignment(WidgetTester tester) async {
  double? center;
  for (final field in ['등록한 할 일', '미룬 횟수', '평균 미룬 시간', '자주 완료한 시간대']) {
    final label = find.byKey(Key('stats-detail-label-$field'));
    final value = find.byKey(Key('stats-detail-value-$field'));
    expect(label, findsOneWidget);
    expect(value, findsOneWidget);
    await tester.ensureVisible(value);
    await tester.pumpAndSettle();
    final labelRect = tester.getRect(label);
    final valueRect = tester.getRect(value);
    final largeType =
        MediaQuery.textScalerOf(tester.element(value)).scale(13) > 20;
    if (largeType) {
      expect(labelRect.bottom, lessThan(valueRect.top));
    } else {
      expect(labelRect.right, lessThan(valueRect.left));
      expect(labelRect.center.dy, closeTo(valueRect.center.dy, 1));
    }
    expect(tester.widget<Text>(value).textAlign, TextAlign.center);
    center ??= valueRect.center.dx;
    expect(valueRect.center.dx, closeTo(center, .1));
    expect(tester.takeException(), isNull, reason: field);
  }
  return center!;
}

Future<void> _show(
  WidgetTester tester, {
  required List<Occurrence> items,
  String language = 'ko',
  double scale = 1,
  double width = 375,
  Future<Map<String, Object>> Function(DateTime, DateTime)? loadStatistics,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 812);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(fontFamily: 'Pretendard', useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: StatisticsPanel(
            items: items,
            // Stale aggregate values must not replace the occurrence-based
            // denominator shared by the two interactive charts.
            statistics: const {
              'total': 999,
              'completed': 998,
              'registered': 18,
              'snoozes': 6,
              'average': 15,
              'hour': '19시',
            },
            now: _now,
            loadStatistics: loadStatistics,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

List<Occurrence> _periodItems() => [
  ..._comparisonItems(),
  _occurrence(
    'june-10-done',
    due: DateTime(2026, 6, 10, 9),
    completed: DateTime(2026, 6, 10, 11),
    status: TaskStatus.completed,
    category: '업무',
    priority: 2,
  ),
  _occurrence('june-10-pending', due: DateTime(2026, 6, 10, 10)),
  _occurrence(
    'june-11-done-1',
    due: DateTime(2026, 6, 11, 9),
    completed: DateTime(2026, 6, 11, 11),
    status: TaskStatus.completed,
  ),
  _occurrence(
    'june-11-done-2',
    due: DateTime(2026, 6, 11, 10),
    completed: DateTime(2026, 6, 11, 12),
    status: TaskStatus.completed,
    category: '건강',
  ),
  _occurrence('june-11-pending', due: DateTime(2026, 6, 11, 13)),
];

const _loadedDetails = <String, Object>{
  'registered': 101,
  'snoozes': 7,
  'average': 21,
  'hour': '06시',
};

/// Exercise the public picker using its text-input mode. Fixed frame advances
/// keep pending request spinners from making pumpAndSettle time out.
Future<void> _choosePeriod(
  WidgetTester tester,
  DateTime start,
  DateTime end, {
  bool cancel = false,
  bool settle = true,
}) async {
  final selector = find.byKey(const Key('statistics-period-select'));
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await tester.pump(const Duration(milliseconds: 400));
  final dialog = find.byType(DateRangePickerDialog);
  expect(dialog, findsOneWidget);
  final context = tester.element(dialog);
  final localizations = MaterialLocalizations.of(context);
  final strings = AppStrings.of(context);
  await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
  await tester.pump(const Duration(milliseconds: 400));
  final fields = find.descendant(of: dialog, matching: find.byType(TextField));
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), localizations.formatCompactDate(start));
  await tester.enterText(fields.at(1), localizations.formatCompactDate(end));
  final action = find.descendant(
    of: dialog,
    matching: find.widgetWithText(
      TextButton,
      cancel ? localizations.cancelButtonLabel : strings.t('조회'),
    ),
  );
  await tester.ensureVisible(action);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(action);
  await tester.pump(const Duration(milliseconds: 400));
  if (settle) await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });
  tearDown(() => AppStrings.current = const AppStrings('ko'));

  test('both breakdowns reconcile 40 completions and 55 targets', () {
    final result = StatisticsBreakdown.fromOccurrences(
      _comparisonItems(),
      now: _now,
    );
    expect(result.total, 55);
    expect(result.completed, 40);
    expect(result.from, _now.subtract(const Duration(days: 30)));
    expect(result.until, _now);
    expect(result.priorities[2]!.total, 12);
    expect(result.priorities[2]!.completed, 9);
    expect(result.priorities[2]!.rate, .75);
    expect(result.priorities[1]!.total, 32);
    expect(result.priorities[1]!.completed, 24);
    expect(result.priorities[1]!.rate, .75);
    expect(result.priorities[0]!.total, 11);
    expect(result.priorities[0]!.completed, 7);
    expect(result.priorities[0]!.rate, closeTo(7 / 11, 1e-12));
    expect(result.categoryCompleted, {
      '생활': 9,
      '업무': 15,
      '건강': 8,
      '배움': 6,
      '기타': 2,
    });
    expect(
      result.categoryCompleted.values.fold(0, (sum, n) => sum + n),
      result.completed,
    );
  });

  test('window is inclusive and excludes future completion timestamps', () {
    final from = _now.subtract(const Duration(days: 30));
    final before = from.subtract(const Duration(microseconds: 1));
    final after = _now.add(const Duration(microseconds: 1));
    final result = StatisticsBreakdown.fromOccurrences([
      _occurrence('due-at-start', due: from),
      _occurrence('due-at-end', due: _now),
      _occurrence('due-before-start', due: before),
      _occurrence('due-after-end', due: after),
      _occurrence(
        'late-completion',
        due: before,
        completed: _now,
        status: TaskStatus.completed,
      ),
      _occurrence(
        'early-completion',
        due: after,
        completed: _now,
        status: TaskStatus.completed,
      ),
      _occurrence(
        'completion-at-start',
        due: before,
        completed: from,
        status: TaskStatus.completed,
      ),
      _occurrence(
        'completion-before-start',
        completed: before,
        status: TaskStatus.completed,
      ),
      _occurrence(
        'completion-in-future',
        completed: after,
        status: TaskStatus.completed,
      ),
      _occurrence('completion-missing-time', status: TaskStatus.completed),
      _occurrence('undone-stale-time', due: before, completed: _now),
      _occurrence(
        'skipped-stale-time',
        due: before,
        completed: _now,
        status: TaskStatus.skipped,
      ),
    ], now: _now);
    expect(result.total, 8);
    expect(result.completed, 3);
    expect(result.priorities[1]!.total, 8);
    expect(result.priorities[1]!.completed, 3);
    expect(result.categoryCompleted['생활'], 3);
  });

  test('manual skips stay in the target; weekly-quota skips do not', () {
    final manual = StatisticsBreakdown.fromOccurrences([
      _occurrence('manual-1', status: TaskStatus.skipped, priority: 2),
      _occurrence('manual-2', status: TaskStatus.skipped, priority: 0),
    ], now: _now);
    expect(manual.total, 2);
    expect(manual.completed, 0);
    expect(manual.priorities[2]!.rate, 0);
    expect(manual.priorities[0]!.rate, 0);
    expect(manual.priorities[1]!.rate, isNull);
    for (final items in [
      <Occurrence>[],
      [_occurrence('quota', status: TaskStatus.skipped, quotaSkipped: true)],
      [_occurrence('future', due: _now.add(const Duration(days: 1)))],
    ]) {
      final result = StatisticsBreakdown.fromOccurrences(items, now: _now);
      expect(result.total, 0);
      expect(result.completed, 0);
      expect(
        result.priorities.values.map((count) => count.rate),
        everyElement(isNull),
      );
      expect(result.categoryCompleted.values, everyElement(0));
    }
  });

  test('custom categories remain and invalid priority uses Normal', () {
    const custom = '내가 만든 분류';
    final result = StatisticsBreakdown.fromOccurrences([
      _occurrence(
        'custom',
        category: custom,
        priority: 99,
        completed: _now,
        status: TaskStatus.completed,
      ),
      _occurrence('other', category: '기타', priority: -1),
    ], now: _now);
    expect(result.total, 2);
    expect(result.completed, 1);
    expect(result.categoryCompleted[custom], 1);
    expect(result.categoryCompleted['기타'], 0);
    expect(result.priorities[1]!.total, 2);
    expect(result.priorities[1]!.completed, 1);
    expect(result.priorities[2]!.total, 0);
    expect(result.priorities[0]!.total, 0);
  });

  test('UTC representations count the same instants as local dates', () {
    final local = StatisticsBreakdown.fromOccurrences([
      _occurrence('a', completed: _now, status: TaskStatus.completed),
      _occurrence('b', due: _now.subtract(const Duration(days: 30))),
    ], now: _now);
    final utc = StatisticsBreakdown.fromOccurrences([
      _occurrence(
        'a',
        due: _now.subtract(const Duration(days: 1)).toUtc(),
        completed: _now.toUtc(),
        status: TaskStatus.completed,
      ),
      _occurrence('b', due: _now.subtract(const Duration(days: 30)).toUtc()),
    ], now: _now.toUtc());
    expect(utc.total, local.total);
    expect(utc.completed, local.completed);
    expect(utc.categoryCompleted, local.categoryCompleted);
    expect(utc.from.isAtSameMomentAs(local.from), isTrue);
  });

  test('breakdown totals agree with the real repository SQL', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final repository = await TaskRepository.open(
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(repository.db.close);
    final now = DateTime.now();
    final past = now.subtract(const Duration(days: 5));
    final old = now.subtract(const Duration(days: 40));
    final future = now.add(const Duration(days: 5));
    final fixtures = [
      _occurrence('due', due: past),
      _occurrence(
        'done',
        due: past,
        completed: past,
        status: TaskStatus.completed,
      ),
      _occurrence(
        'done-old-due',
        due: old,
        completed: past,
        status: TaskStatus.completed,
      ),
      _occurrence(
        'done-early',
        due: future,
        completed: past,
        status: TaskStatus.completed,
      ),
      _occurrence('manual-skip', due: past, status: TaskStatus.skipped),
      _occurrence(
        'quota-skip',
        due: past,
        status: TaskStatus.skipped,
        quotaSkipped: true,
      ),
      _occurrence(
        'future-completion',
        due: past,
        completed: future,
        status: TaskStatus.completed,
      ),
      _occurrence(
        'old-completion',
        due: past,
        completed: old,
        status: TaskStatus.completed,
      ),
      _occurrence('future-pending', due: future),
    ];
    for (final item in fixtures) {
      await repository.db.insert('tasks', item.task.toMap());
      await repository.db.insert('occurrences', {
        'id': item.id,
        'task_id': item.task.id,
        'original_due': item.originalDue.toIso8601String(),
        'reminder': item.reminder.toIso8601String(),
        'state': item.status.name,
        'completed': item.completed?.toIso8601String(),
        'quota_skipped': item.quotaSkipped ? 1 : 0,
      });
    }
    final result = StatisticsBreakdown.fromOccurrences(
      await repository.occurrences(),
      now: now,
    );
    final saved = await repository.stats();
    expect(result.total, saved['total']);
    expect(result.completed, saved['completed']);
    expect(result.total, 7);
    expect(result.completed, 3);
  });

  test('custom one-day period includes its full day and excludes adjacent instants', () {
    final from = DateTime(2026, 6, 10);
    final until = DateTime(
      2026,
      6,
      11,
    ).subtract(const Duration(microseconds: 1));
    final result = StatisticsBreakdown.fromOccurrences(
      [
        _occurrence(
          'first-instant',
          due: from,
          completed: from,
          status: TaskStatus.completed,
        ),
        _occurrence(
          'last-instant',
          due: until,
          completed: until,
          status: TaskStatus.completed,
        ),
        _occurrence(
          'previous-day',
          due: from.subtract(const Duration(microseconds: 1)),
          completed: from.subtract(const Duration(microseconds: 1)),
          status: TaskStatus.completed,
        ),
        _occurrence(
          'next-day',
          due: DateTime(2026, 6, 11),
          completed: DateTime(2026, 6, 11),
          status: TaskStatus.completed,
        ),
      ],
      now: _now,
      from: from,
      until: until,
    );
    expect(result.from, from);
    expect(result.until, until);
    expect(result.total, 2);
    expect(result.completed, 2);
    expect(result.priorities[1]!.rate, 1);
  });

  test('historical range replaces the default window for both breakdowns', () {
    final items = _periodItems();
    final recent = StatisticsBreakdown.fromOccurrences(items, now: _now);
    final historical = StatisticsBreakdown.fromOccurrences(
      items,
      now: _now,
      from: DateTime(2026, 6, 10),
      until: DateTime(2026, 6, 11).subtract(const Duration(microseconds: 1)),
    );
    expect(recent.total, 55);
    expect(recent.completed, 40);
    expect(historical.total, 2);
    expect(historical.completed, 1);
    expect(historical.priorities[2]!.completed, 1);
    expect(historical.priorities[2]!.total, 1);
    expect(historical.categoryCompleted['업무'], 1);
    expect(historical.categoryCompleted['생활'], 0);
  });

  for (final language in ['ko', 'en']) {
    for (final scale in [1.0, 2.0]) {
      for (final width in [320.0, 375.0, 402.0]) {
        testWidgets(
          'two statistics tabs fit ${width}px, $language, ${scale}x, empty and filled',
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            for (final empty in [true, false]) {
              await _show(
                tester,
                items: empty ? [] : _comparisonItems(),
                language: language,
                width: width,
                scale: scale,
              );
              final priority = find.byKey(const Key('statistics-tab-priority'));
              final category = find.byKey(const Key('statistics-tab-category'));
              expect(priority, findsOneWidget);
              expect(category, findsOneWidget);
              final reset = find.byKey(const Key('statistics-period-reset'));
              final period = find.byKey(const Key('statistics-period-select'));
              final summary = find.byKey(const Key('statistics-summary'));
              expect(_resetButton(tester).onPressed, isNull);
              expect(
                find.descendant(of: reset, matching: find.byType(Icon)),
                findsOneWidget,
              );
              final resetRect = tester.getRect(reset);
              final periodRect = tester.getRect(period);
              final tabsRect = tester.getRect(priority);
              final summaryRect = tester.getRect(summary);
              expect(resetRect.height, greaterThanOrEqualTo(40));
              expect(resetRect.bottom, lessThanOrEqualTo(periodRect.top));
              expect(resetRect.right, closeTo(periodRect.right, 1));
              expect(periodRect.bottom, lessThanOrEqualTo(tabsRect.top));
              expect(tabsRect.bottom, lessThanOrEqualTo(summaryRect.top));
              _expectSummary(
                tester,
                total: empty ? 0 : 55,
                completed: empty ? 0 : 40,
                language: language,
              );
              expect(tester.takeException(), isNull);
              expect(
                find.byKey(const Key('statistics-category-donut')),
                findsNothing,
              );
              expect(
                find.byKey(const Key('statistics-completion-calendar')),
                findsNothing,
              );
              expect(find.byType(LinearProgressIndicator), findsNothing);
              final detailCenter = await _expectDetailAlignment(tester);
              await _tap(tester, category);
              expect(
                find.byKey(const Key('statistics-category-donut')),
                findsOneWidget,
              );
              final categorySummary = find.byKey(
                const Key('statistics-category-summary'),
              );
              expect(categorySummary, findsOneWidget);
              expect(
                _texts(tester, categorySummary),
                contains(empty ? '0' : '40'),
              );
              _expectSummary(
                tester,
                total: empty ? 0 : 55,
                completed: empty ? 0 : 40,
                language: language,
              );
              expect(tester.takeException(), isNull);
              final countHeading = find.byKey(
                const Key('stats-category-count-heading'),
              );
              final shareHeading = find.byKey(
                const Key('stats-category-share-heading'),
              );
              expect(countHeading, findsOneWidget);
              expect(shareHeading, findsOneWidget);
              final countCenter = tester.getCenter(countHeading).dx;
              final shareCenter = tester.getCenter(shareHeading).dx;
              expect(countCenter, lessThan(shareCenter));
              expect(
                (countCenter + shareCenter) / 2,
                closeTo(detailCenter, .1),
              );
              expect(
                tester.widget<Text>(countHeading).textAlign,
                TextAlign.center,
              );
              expect(
                tester.widget<Text>(shareHeading).textAlign,
                TextAlign.center,
              );
              final strings = AppStrings(language);
              for (final name in taskCategories) {
                final row = find.byKey(Key('stats-category-$name'));
                expect(row, findsOneWidget);
                await tester.ensureVisible(row);
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull, reason: name);
                final rect = tester.getRect(row);
                expect(rect.left, greaterThanOrEqualTo(0));
                expect(rect.right, lessThanOrEqualTo(width));
                expect(rect.height, greaterThanOrEqualTo(48));
                _expectCategoryIdentity(tester, row, name, strings);
                final count = find.byKey(Key('stats-category-count-$name'));
                final share = find.byKey(Key('stats-category-share-$name'));
                expect(tester.widget<Text>(count).textAlign, TextAlign.center);
                expect(tester.widget<Text>(share).textAlign, TextAlign.center);
                final countRect = tester.getRect(count);
                final shareRect = tester.getRect(share);
                expect(countRect.center.dx, closeTo(countCenter, .1));
                expect(shareRect.center.dx, closeTo(shareCenter, .1));
                expect(countRect.right, lessThan(shareRect.left));
                expect(countRect.top, closeTo(shareRect.top, 1));
              }
              await _expectDetailAlignment(tester);
              await _tap(tester, priority);
              expect(
                find.byKey(const Key('statistics-category-donut')),
                findsNothing,
              );
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
            }
          },
        );
      }
    }
  }

  testWidgets(
    'priority rings show each denominator rather than a share of all tasks',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _show(tester, items: _comparisonItems());
      for (final entry in const {
        2: ['9 / 12', '75%'],
        1: ['24 / 32', '75%'],
        0: ['7 / 11', '64%'],
      }.entries) {
        final ring = find.byKey(ValueKey('stats-priority-${entry.key}'));
        expect(ring, findsOneWidget);
        final content = _texts(tester, ring);
        expect(content, contains(entry.value[0]));
        expect(content, contains(entry.value[1]));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category selection shows its completed count and returns to all',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        await _show(tester, items: _comparisonItems());
        await _tap(tester, find.byKey(const Key('statistics-tab-category')));
        final summary = find.byKey(const Key('statistics-category-summary'));
        expect(_texts(tester, summary), contains('40'));
        final work = find.byKey(const Key('stats-category-업무'));
        await _tap(tester, work);
        expect(_texts(tester, summary), contains('15'));
        expect(_texts(tester, summary), contains('업무'));
        expect(_texts(tester, summary), contains('37.5%'));
        expect(
          tester.getSemantics(work).flagsCollection.isSelected,
          Tristate.isTrue,
        );
        await _tap(tester, work);
        expect(_texts(tester, summary), contains('40'));
        expect(tester.takeException(), isNull);
      } finally {
        // testWidgets checks active handles before package:test tearDown runs.
        // Release here even when an assertion fails in the interaction steps.
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'long custom category fits and remains selectable at 320px and 2x',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const custom = 'A long personal category 내가 만든 분류 이름';
      await _show(
        tester,
        items: [
          _occurrence(
            'custom',
            completed: _now,
            status: TaskStatus.completed,
            category: custom,
          ),
        ],
        language: 'en',
        width: 320,
        scale: 2,
      );
      await _tap(tester, find.byKey(const Key('statistics-tab-category')));
      await _tap(tester, find.byKey(const Key('stats-category-$custom')));
      expect(
        _texts(tester, find.byKey(const Key('statistics-category-summary'))),
        contains(custom),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling the period picker preserves counts and makes no query',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var queries = 0;
      await _show(
        tester,
        items: _periodItems(),
        loadStatistics: (from, until) async {
          queries++;
          return _loadedDetails;
        },
      );
      await _choosePeriod(
        tester,
        DateTime(2026, 6, 10),
        DateTime(2026, 6, 10),
        cancel: true,
      );
      expect(queries, 0);
      expect(_resetButton(tester).onPressed, isNull);
      _expectSummary(tester, total: 55, completed: 40);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['ko', 'en']) {
    testWidgets(
      '$language applying a day filters both tabs and reset restores recent data',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final requests = <DateTimeRange>[];
        await _show(
          tester,
          items: _periodItems(),
          language: language,
          width: 320,
          scale: 2,
          loadStatistics: (from, until) async {
            requests.add(DateTimeRange(start: from, end: until));
            return _loadedDetails;
          },
        );
        await _choosePeriod(
          tester,
          DateTime(2026, 6, 10),
          DateTime(2026, 6, 10),
        );
        expect(requests, hasLength(1));
        expect(requests.single.start, DateTime(2026, 6, 10));
        expect(
          requests.single.end,
          DateTime(2026, 6, 11).subtract(const Duration(microseconds: 1)),
        );
        final strings = AppStrings(language);
        _expectSummary(tester, total: 2, completed: 1, language: language);
        expect(_resetButton(tester).onPressed, isNotNull);
        expect(
          _texts(tester, find.byKey(const Key('stats-priority-2'))),
          contains('1 / 1'),
        );
        await _tap(tester, find.byKey(const Key('statistics-tab-category')));
        expect(
          _texts(tester, find.byKey(const Key('statistics-category-summary'))),
          contains('1'),
        );
        final work = find.byKey(const Key('stats-category-업무'));
        expect(_texts(tester, work), contains('100%'));
        expect(find.text(strings.t('{n}개', args: {'n': 101})), findsOneWidget);
        await _tap(tester, find.byKey(const Key('statistics-period-reset')));
        expect(requests, hasLength(2));
        expect(requests.last.start, _now.subtract(const Duration(days: 30)));
        expect(requests.last.end, _now);
        expect(_resetButton(tester).onPressed, isNull);
        _expectSummary(tester, total: 55, completed: 40, language: language);
        expect(
          _texts(tester, find.byKey(const Key('statistics-category-summary'))),
          contains('40'),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'period loading hides old charts and a failed query can retry the same range',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<Map<String, Object>>();
      final requests = <DateTimeRange>[];
      await _show(
        tester,
        items: _periodItems(),
        loadStatistics: (from, until) {
          requests.add(DateTimeRange(start: from, end: until));
          return requests.length == 1
              ? pending.future
              : Future.value(_loadedDetails);
        },
      );
      await _choosePeriod(
        tester,
        DateTime(2026, 6, 10),
        DateTime(2026, 6, 10),
        settle: false,
      );
      expect(
        find.byKey(const Key('statistics-period-loading')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('statistics-summary')), findsNothing);
      expect(find.byKey(const Key('stats-priority-2')), findsNothing);
      expect(_resetButton(tester).onPressed, isNotNull);
      expect(find.text('18개'), findsNothing);
      pending.completeError(StateError('database temporarily unavailable'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('statistics-period-retry')), findsOneWidget);
      expect(find.byKey(const Key('statistics-summary')), findsNothing);
      await _tap(tester, find.byKey(const Key('statistics-period-retry')));
      expect(requests, hasLength(2));
      expect(requests.last, requests.first);
      _expectSummary(tester, total: 2, completed: 1);
      expect(find.text('101개'), findsOneWidget);
      expect(find.byKey(const Key('statistics-period-retry')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late query results cannot overwrite a newer selected period', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = Completer<Map<String, Object>>();
    final second = Completer<Map<String, Object>>();
    var requests = 0;
    await _show(
      tester,
      items: _periodItems(),
      loadStatistics: (from, until) {
        requests++;
        return requests == 1 ? first.future : second.future;
      },
    );
    await _choosePeriod(
      tester,
      DateTime(2026, 6, 10),
      DateTime(2026, 6, 10),
      settle: false,
    );
    await _choosePeriod(
      tester,
      DateTime(2026, 6, 11),
      DateTime(2026, 6, 11),
      settle: false,
    );
    expect(requests, 2);
    second.complete({..._loadedDetails, 'registered': 222});
    await tester.pumpAndSettle();
    _expectSummary(tester, total: 3, completed: 2);
    expect(find.text('222개'), findsOneWidget);
    first.complete({..._loadedDetails, 'registered': 111});
    await tester.pumpAndSettle();
    _expectSummary(tester, total: 3, completed: 2);
    expect(find.text('222개'), findsOneWidget);
    expect(find.text('111개'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    testWidgets('$language statistics remain usable at 320px and 3x text', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _show(
        tester,
        items: _comparisonItems(),
        language: language,
        width: 320,
        scale: 3,
      );
      _expectSummary(tester, total: 55, completed: 40, language: language);
      for (final priority in [2, 1, 0]) {
        await tester.ensureVisible(
          find.byKey(ValueKey('stats-priority-$priority')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await _tap(tester, find.byKey(const Key('statistics-tab-category')));
      for (final category in taskCategories) {
        final row = find.byKey(Key('stats-category-$category'));
        await _tap(tester, row);
        expect(
          _texts(tester, find.byKey(const Key('statistics-category-summary'))),
          contains(AppStrings(language).category(category)),
        );
        expect(tester.takeException(), isNull);
      }
      await _expectDetailAlignment(tester);
    });
  }

  testWidgets('a completed query after leaving statistics is ignored safely', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<Map<String, Object>>();
    await _show(
      tester,
      items: _periodItems(),
      loadStatistics: (_, _) => pending.future,
    );
    await _choosePeriod(
      tester,
      DateTime(2026, 6, 10),
      DateTime(2026, 6, 10),
      settle: false,
    );
    expect(find.byKey(const Key('statistics-period-loading')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(_loadedDetails);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
