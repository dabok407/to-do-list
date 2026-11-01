import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/task_completion_checkbox.dart';
import 'package:hangeoreum/features/task_timeline_row.dart';
import 'package:hangeoreum/features/visual_tokens.dart';
import 'package:hangeoreum/l10n/app_strings.dart';

Occurrence _item({
  TaskStatus status = TaskStatus.pending,
  DateTime? due,
  DateTime? completed,
  DateTime? reminder,
  String category = '배움',
  RepeatUnit repeat = RepeatUnit.weekly,
  String title =
      '긴 제목을 가진 에어컨 필터 청소 · A long task title that must remain readable',
}) {
  final scheduled = due ?? DateTime(2026, 10, 20, 9, 5);
  return Occurrence(
    id: 'timeline',
    task: Task(
      id: 'timeline-task',
      title: title,
      due: scheduled,
      created: DateTime(2026, 10, 1),
      category: category,
      priority: 2,
      repeat: repeat,
    ),
    originalDue: scheduled,
    reminder: reminder ?? DateTime(2026, 10, 22, 15, 10),
    status: status,
    completed: completed,
  );
}

Future<void> _render(
  WidgetTester tester,
  Occurrence item, {
  double width = 375,
  double scale = 1,
  String language = 'ko',
  bool busy = false,
  bool premium = true,
  bool useScheduledTime = false,
  bool showScheduleDate = false,
  VoidCallback? onTap,
  VoidCallback? onToggle,
  VoidCallback? onStart,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 812);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  AppStrings.current = AppStrings(language);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TaskTimelineRow(
              occurrence: item,
              busy: busy,
              hasProAccess: premium,
              useScheduledTime: useScheduledTime,
              showScheduleDate: showScheduleDate,
              onTap: onTap ?? () {},
              onToggle: onToggle ?? () {},
              onStart: onStart ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });
  tearDown(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.clearTextScaleFactorTestValue();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
    AppStrings.current = const AppStrings('ko');
  });

  for (final language in ['ko', 'en']) {
    for (final width in [320.0, 375.0, 402.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          '$language timeline clock, title and metadata fit ${width}px at ${scale}x',
          (tester) async {
            final strings = AppStrings(language);
            for (final completed in [false, true]) {
              final item = _item(
                status: completed ? TaskStatus.completed : TaskStatus.pending,
                completed: completed ? DateTime(2026, 10, 21, 14, 35) : null,
              );
              await _render(
                tester,
                item,
                width: width,
                scale: scale,
                language: language,
              );
              final clock = find.byKey(const Key('task-time-timeline'));
              final title = find.text(item.task.title);
              expect(
                tester.widget<Text>(clock).data,
                strings.time(completed ? item.completed! : item.originalDue),
              );
              final titleRect = tester.getRect(title);
              final clockRect = tester.getRect(clock);
              final category = find.byType(CategoryLabel);
              final badge = tester.widget<CategoryLabel>(category);
              expect(badge.category, '배움');
              expect(badge.label, strings.category('배움'));
              final metadataRect = tester.getRect(
                find.byKey(const Key('task-metadata-timeline')),
              );
              final contentRect = tester.getRect(
                find.byKey(const Key('task-content-timeline')),
              );
              final indicatorRect = tester.getRect(
                find.byKey(const Key('task-completion-indicator')),
              );
              final titleWidget = tester.widget<Text>(title);
              if (titleWidget.maxLines == 1) {
                // The compact row keeps time, title, metadata and indicator
                // visually centered; only the task title may be ellipsized.
                expect(titleWidget.overflow, TextOverflow.ellipsis);
                expect(clockRect.right, lessThanOrEqualTo(titleRect.left));
                expect(titleRect.right, lessThan(metadataRect.left));
                for (final rect in [titleRect, metadataRect, indicatorRect]) {
                  expect(rect.center.dy, closeTo(clockRect.center.dy, .01));
                }
              } else {
                expect(
                  metadataRect.top,
                  greaterThanOrEqualTo(titleRect.bottom),
                );
                expect(
                  tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
                  isFalse,
                );
                if (clockRect.right <= contentRect.left) {
                  expect(
                    clockRect.center.dy,
                    closeTo(contentRect.center.dy, .01),
                  );
                  expect(
                    indicatorRect.center.dy,
                    closeTo(contentRect.center.dy, .01),
                  );
                } else {
                  expect(clockRect.bottom, lessThanOrEqualTo(titleRect.top));
                  expect(
                    indicatorRect.bottom,
                    lessThanOrEqualTo(titleRect.top),
                  );
                }
              }
              expect(find.text(strings.t('높음')), findsOneWidget);
              expect(find.byTooltip(strings.t('반복')), findsOneWidget);
              final toggle = find.byKey(const Key('task-completion-target'));
              final targetRect = tester.getRect(toggle);
              final caption = find.byKey(const Key('task-completion-caption'));
              final captionRect = tester.getRect(caption);
              expect(targetRect.width, greaterThanOrEqualTo(48));
              expect(targetRect.height, greaterThanOrEqualTo(56));
              expect(indicatorRect.size, const Size(24, 24));
              expect(
                captionRect.bottom,
                lessThanOrEqualTo(targetRect.bottom + .01),
              );
              expect(
                tester.renderObject<RenderParagraph>(caption).didExceedMaxLines,
                isFalse,
              );
              for (final rect in [
                clockRect,
                titleRect,
                metadataRect,
                targetRect,
              ]) {
                expect(rect.left, greaterThanOrEqualTo(15.99));
                expect(rect.right, lessThanOrEqualTo(width - 15.99));
              }
              expect(
                find.byKey(const ValueKey('start-timeline')),
                findsNothing,
              );
              final arrow = find.byIcon(Icons.swap_horiz_rounded);
              expect(arrow, findsOneWidget);
              expect(
                tester.getRect(arrow).top,
                greaterThanOrEqualTo(clockRect.bottom),
              );
              expect(
                tester.widget<Text>(caption).data,
                strings.t(completed ? '완료됨' : '완료'),
              );
              expect(
                tester.takeException(),
                isNull,
                reason: 'completed=$completed',
              );
            }
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }

  for (final language in ['ko', 'en']) {
    testWidgets(
      '$language calendar completion keeps scheduled clock without duplicate copy',
      (tester) async {
        final strings = AppStrings(language);
        final item = _item(
          status: TaskStatus.completed,
          completed: DateTime(2026, 10, 21, 14, 35),
        );
        await _render(
          tester,
          item,
          language: language,
          useScheduledTime: true,
          showScheduleDate: true,
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('task-time-timeline'))).data,
          strings.time(item.originalDue),
        );
        expect(
          find.byKey(const Key('task-original-schedule-timeline')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('task-schedule-date-timeline')),
          findsOneWidget,
        );
        final scheduledSemantics = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  strings.t(
                    '예정 시각 {time}',
                    args: {
                      'time':
                          '${strings.date(item.originalDue)} ${strings.time(item.originalDue)}',
                    },
                  ),
        );
        expect(scheduledSemantics, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$language completed row distinguishes actual and planned clock',
      (tester) async {
        final strings = AppStrings(language);
        final due = DateTime.utc(2026, 10, 20, 22, 5);
        final done = DateTime.utc(2026, 10, 22, 1, 35);
        await _render(
          tester,
          _item(status: TaskStatus.completed, due: due, completed: done),
          language: language,
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('task-time-timeline'))).data,
          strings.time(done.toLocal()),
        );
        final original = find.byKey(
          const Key('task-original-schedule-timeline'),
        );
        expect(original, findsOneWidget);
        expect(
          find.descendant(
            of: original,
            matching: find.text(
              strings.t(
                '원래 예정 {date} {time}',
                args: {
                  'date': strings.date(due.toLocal()),
                  'time': strings.time(due.toLocal()),
                },
              ),
            ),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('start-timeline')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('$language legacy completion never invents a completion time', (
      tester,
    ) async {
      final item = _item(status: TaskStatus.completed);
      final strings = AppStrings(language);
      await _render(tester, item, language: language);
      expect(find.text(strings.t('완료 시각 기록 없음')), findsOneWidget);
      expect(
        find.byKey(const Key('task-original-schedule-timeline')),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('task-time-timeline'))).data,
        strings.time(item.originalDue),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'same-minute completion avoids redundant original-schedule copy',
    (tester) async {
      final due = DateTime(2026, 10, 21, 14, 35, 1);
      await _render(
        tester,
        _item(
          status: TaskStatus.completed,
          due: due,
          completed: due.add(const Duration(seconds: 20)),
        ),
      );
      expect(
        find.byKey(const Key('task-original-schedule-timeline')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'compact row preserves height and position during completion feedback',
    (tester) async {
      final item = _item(title: '필터 청소', repeat: RepeatUnit.none);
      await _render(tester, item);
      final row = find.byKey(const Key('task-row-layout-timeline'));
      final target = find.byKey(const Key('task-completion-target'));
      final pendingRect = tester.getRect(row);
      final pendingTarget = tester.getRect(target);
      final pendingTime = tester.getRect(
        find.byKey(const Key('task-time-timeline')),
      );
      expect(pendingRect.height, 64);
      expect(pendingTarget.size, const Size(48, 56));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('task-time-timeline')))
            .style!
            .fontSize,
        18,
      );
      await _render(
        tester,
        _item(
          title: '필터 청소',
          repeat: RepeatUnit.none,
          status: TaskStatus.completed,
          completed: DateTime(2026, 10, 21, 14, 35),
        ),
        useScheduledTime: true,
      );
      expect(tester.getRect(row), pendingRect);
      expect(tester.getRect(target), pendingTarget);
      expect(
        tester.getRect(find.byKey(const Key('task-time-timeline'))),
        pendingTime,
      );
      expect(find.text('완료됨'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('필터 청소')).style!.decoration,
        TextDecoration.lineThrough,
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'row detail and right completion control remain separate actions',
    (tester) async {
      var taps = 0;
      var toggles = 0;
      var starts = 0;
      final item = _item(title: 'Filter');
      await _render(
        tester,
        item,
        onTap: () => taps++,
        onToggle: () => toggles++,
        onStart: () => starts++,
      );
      await tester.tap(find.text('Filter'));
      await tester.tap(find.byKey(const Key('task-completion-indicator')));
      await tester.tap(find.byKey(const Key('task-completion-caption')));
      expect([taps, toggles, starts], [1, 2, 0]);
      expect(find.byKey(const ValueKey('start-timeline')), findsNothing);
      final checkbox = tester.widget<TaskCompletionCheckbox>(
        find.byType(TaskCompletionCheckbox),
      );
      expect(checkbox.semanticLabel, 'Filter, 완료 처리');
      expect(checkbox.enabled, isTrue);
      await _render(
        tester,
        item,
        busy: true,
        onTap: () => taps++,
        onToggle: () => toggles++,
        onStart: () => starts++,
      );
      expect(
        tester
            .widget<TaskCompletionCheckbox>(find.byType(TaskCompletionCheckbox))
            .enabled,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('task-completion-caption')));
      await tester.tap(find.text('Filter'));
      expect([taps, toggles, starts], [1, 2, 0]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long custom category remains readable at accessibility size', (
    tester,
  ) async {
    const customCategory = '나의 새로운 아주 긴 분류';
    await _render(
      tester,
      _item(category: customCategory),
      width: 320,
      scale: 2,
    );
    final categoryText = find.text(customCategory);
    expect(categoryText, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(categoryText).didExceedMaxLines,
      isFalse,
    );
    expect(tester.getRect(categoryText).right, lessThanOrEqualTo(304));
    expect(tester.takeException(), isNull);
  });

  testWidgets('skipped occurrence cannot be completed', (tester) async {
    var toggles = 0;
    await _render(
      tester,
      _item(status: TaskStatus.skipped),
      onToggle: () => toggles++,
    );
    expect(
      tester
          .widget<TaskCompletionCheckbox>(find.byType(TaskCompletionCheckbox))
          .enabled,
      isFalse,
    );
    expect(find.byIcon(Icons.swap_horiz_rounded), findsNothing);
    await tester.tap(find.byKey(const Key('task-completion-indicator')));
    expect(toggles, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'paused row preserves reminder clock; progressing has no start duplicate',
    (tester) async {
      final paused = _item(status: TaskStatus.paused);
      await _render(tester, paused);
      expect(
        find.text(
          AppStrings.current.t(
            '· {time} 재알림',
            args: {
              'time':
                  '${AppStrings.current.date(paused.reminder.toLocal())} ${AppStrings.current.time(paused.reminder.toLocal())}',
            },
          ),
        ),
        findsOneWidget,
      );
      await _render(tester, _item(status: TaskStatus.progressing));
      expect(find.byKey(const ValueKey('start-timeline')), findsNothing);
      expect(find.byTooltip('완료 처리'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['ko', 'en']) {
    testWidgets(
      '$language reminder labels distinguish another day at large type',
      (tester) async {
        final strings = AppStrings(language);
        final due = DateTime(2026, 12, 31, 12);
        final tomorrow = DateTime(2027, 1, 1, 12);
        final item = _item(
          status: TaskStatus.paused,
          due: due,
          reminder: tomorrow,
        );
        await _render(tester, item, width: 320, scale: 2, language: language);
        expect(
          find.text(
            strings.t(
              '· {time} 재알림',
              args: {
                'time': '${strings.date(tomorrow)} ${strings.time(tomorrow)}',
              },
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        final sameDay = _item(
          status: TaskStatus.paused,
          due: due,
          reminder: due.add(const Duration(hours: 1)),
        );
        expect(
          taskReminderLabel(sameDay, strings),
          strings.t(
            '· {time} 재알림',
            args: {'time': strings.time(sameDay.reminder)},
          ),
        );
      },
    );
  }
}
