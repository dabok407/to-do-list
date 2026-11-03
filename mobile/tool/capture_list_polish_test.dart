// Actual Flutter UI, fictional local data, and mocked native services only.
// flutter test tool/capture_list_polish_test.dart --dart-define=LIST_POLISH_CAPTURE=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart';
import 'package:hangeoreum/services/widget_service.dart';

import 'capture_seed_comparison_test.dart' as baseline;

const _output = '../.tools/list-polish-2026-11-03';

Future<PreviewController> _fixture(String language) async {
  final c = PreviewController(sampleLanguage: language);
  await c.localeController.setPreference(language);
  await c.refresh();
  for (final task in await c.repository.tasks()) {
    await c.deleteOccurrence(
      Occurrence(
        id: '${task.id}@${task.due.toIso8601String()}',
        task: task,
        originalDue: task.due,
        reminder: task.due,
      ),
      scope: 'series',
    );
  }
  final now = DateTime.now();
  final english = language == 'en';
  DateTime at(int offset, int hour, [int minute = 0]) =>
      DateTime(now.year, now.month, now.day + offset, hour, minute);
  final pending = [
    Task(
      id: 'polish-overdue-two-days',
      title: english ? 'Clean the air conditioner filter' : '에어컨 필터 청소',
      due: at(-2, 12),
      created: at(-3, 9),
      category: '생활',
      priority: 1,
    ),
    Task(
      id: 'polish-overdue-yesterday',
      title: english ? 'Prepare the weekly report' : '이번 주 업무 정리',
      due: at(-1, 15, 30),
      created: at(-3, 10),
      category: '업무',
      priority: 2,
    ),
    Task(
      id: 'polish-today',
      title: english ? 'A few minutes of stretching' : '가볍게 스트레칭',
      due: at(0, 23, 59),
      created: at(-1, 10),
      category: '건강',
      priority: 0,
    ),
    Task(
      id: 'polish-tomorrow',
      title: english ? 'Finish the next book chapter' : '읽던 책 한 챕터 마무리',
      due: at(1, 9),
      created: at(-1, 10),
      category: '배움',
      priority: 1,
    ),
  ];
  for (final task in pending) {
    await c.save(task);
    // Preview fixtures normally complete past dates; keep these as overdue.
    await c.act(c.items.firstWhere((o) => o.task.id == task.id), 'uncomplete');
  }
  final completed = [
    ('생활', english ? 'Water the plants' : '화분에 물 주기'),
    ('업무', english ? 'Send the meeting notes' : '회의 내용 정리하기'),
    ('건강', english ? 'Take a walk after lunch' : '점심 먹고 산책하기'),
    ('배움', english ? 'Read ten pages' : '책 열 페이지 읽기'),
    ('기타', english ? 'Book a haircut' : '미용실 예약하기'),
  ];
  for (var i = 0; i < completed.length; i++) {
    final (category, title) = completed[i];
    final task = Task(
      id: 'polish-completed-$i',
      title: title,
      due: at(-3, 9 + i),
      created: at(-4, 9),
      category: category,
      priority: i % 3,
    );
    await c.save(task);
    await c.act(c.items.firstWhere((o) => o.task.id == task.id), 'complete');
  }
  return c;
}

Future<void> _chooseCustomPeriod(WidgetTester tester) async {
  final selector = find.byKey(const Key('statistics-period-select'));
  await tester.ensureVisible(selector);
  await tester.pumpAndSettle();
  await tester.tap(selector);
  await tester.pumpAndSettle();
  final dialog = find.byType(DateRangePickerDialog);
  expect(dialog, findsOneWidget);
  final context = tester.element(dialog);
  final localizations = MaterialLocalizations.of(context);
  final strings = AppStrings.of(context);
  await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
  await tester.pumpAndSettle();
  final fields = find.descendant(of: dialog, matching: find.byType(TextField));
  expect(fields, findsNWidgets(2));
  final now = DateTime.now();
  await tester.enterText(
    fields.at(0),
    localizations.formatCompactDate(now.subtract(const Duration(days: 14))),
  );
  await tester.enterText(fields.at(1), localizations.formatCompactDate(now));
  final apply = find.descendant(
    of: dialog,
    matching: find.widgetWithText(TextButton, strings.t('조회')),
  );
  await tester.ensureVisible(apply);
  await tester.pumpAndSettle();
  await tester.tap(apply);
  await tester.pumpAndSettle();
  expect(dialog, findsNothing);
}

void main() {
  if (!const bool.fromEnvironment('LIST_POLISH_CAPTURE')) {
    test(
      'List polish actual-screen capture requires opt-in',
      () {},
      skip: true,
    );
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  final configurations = [
    (375.0, 'ko', 1.0),
    for (final width in [320.0, 375.0])
      for (final language in ['ko', 'en']) (width, language, 2.0),
  ];
  for (final (width, language, scale) in configurations) {
    final tag = '${width.toInt()}-$language-${scale.toInt()}x';
    testWidgets('capture list polish and validate responsive screens $tag', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = Size(width * 2, 1624);
      tester.view.padding = const FakeViewPadding(top: 100, bottom: 68);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      final previousPlatform = debugDefaultTargetPlatformOverride;
      final previousShadows = debugDisableShadows;
      final previousStrings = AppStrings.current;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      debugDisableShadows = false;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);
      addTearDown(() => debugDisableShadows = previousShadows);
      addTearDown(() => AppStrings.current = previousStrings);
      try {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(WidgetService.channel, (call) async {
          return call.method == 'getCalendarPreferences'
              ? {'regionCode': 'KR', 'firstDayOfWeek': 0}
              : null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(WidgetService.channel, null),
        );
        final c = await _fixture(language);
        final subscription = baseline.PaidFixture();
        addTearDown(c.dispose);
        addTearDown(subscription.dispose);
        final boundary = GlobalKey();
        Future<void> mount(int page) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: HangeoreumApp(
                controller: c,
                subscription: subscription,
                initialPage: page,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$tag page $page');
        }

        Future<void> capture(String name) async {
          if (name.contains('statistics')) {
            final scrollable = tester.state<ScrollableState>(
              find.byType(Scrollable).first,
            );
            scrollable.position.jumpTo(scrollable.position.minScrollExtent);
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$tag $name');
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('$_output/$tag-$name.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
            } finally {
              image.dispose();
            }
          });
        }

        await mount(1);
        await capture('01-upcoming');
        final overdueFilter = find.byKey(const Key('upcoming-overdue-summary'));
        await tester.ensureVisible(overdueFilter);
        await tester.tap(overdueFilter);
        await tester.pumpAndSettle();
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scrollable.position.jumpTo(scrollable.position.minScrollExtent);
        await capture('01b-upcoming-filtered');
        expect(
          find.text(language == 'en' ? 'No overdue tasks' : '기한 지난 일이 없어요'),
          findsNothing,
        );
        await tester.ensureVisible(overdueFilter);
        await tester.tap(overdueFilter);
        await tester.pumpAndSettle();
        if (scale > 1) {
          final future = c.items.firstWhere(
            (o) => o.task.id == 'polish-tomorrow',
          );
          final futureRow = find.byKey(ValueKey('task-row-${future.id}'));
          // ListView does not build distant rows until they enter the cache area.
          await tester.scrollUntilVisible(
            futureRow,
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await capture('02-upcoming-later');
        }
        if (scale == 1) {
          await mount(0);
          await capture('08-calendar');
        }
        await mount(2);
        await capture('03-completed');
        await mount(3);
        final reset = find.byKey(const Key('statistics-period-reset'));
        expect(tester.widget<OutlinedButton>(reset).onPressed, isNull);
        await capture('04-statistics-priority-reset-disabled');
        await tester.tap(find.byKey(const Key('statistics-tab-category')));
        await capture('05-statistics-category-reset-disabled');
        await _chooseCustomPeriod(tester);
        expect(tester.widget<OutlinedButton>(reset).onPressed, isNotNull);
        await capture('06-statistics-category-reset-enabled');
        await tester.tap(find.byKey(const Key('statistics-tab-priority')));
        await capture('07-statistics-priority-reset-enabled');
        await tester.tap(reset);
        await tester.pumpAndSettle();
        expect(tester.widget<OutlinedButton>(reset).onPressed, isNull);
        expect(tester.takeException(), isNull, reason: '$tag reset to 30 days');
      } finally {
        // Flutter verifies global debug flags before addTearDown is executed.
        debugDefaultTargetPlatformOverride = previousPlatform;
        debugDisableShadows = previousShadows;
        AppStrings.current = previousStrings;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }
}
