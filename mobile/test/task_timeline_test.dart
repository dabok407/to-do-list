import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/task_timeline_row.dart';
import 'package:hangeoreum/features/visual_tokens.dart';
import 'package:hangeoreum/l10n/app_strings.dart';

Occurrence _item({
  TaskStatus status = TaskStatus.pending,
  DateTime? due,
  DateTime? completed,
  DateTime? reminder,
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
      category: '배움',
      priority: 2,
      repeat: RepeatUnit.weekly,
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
      for (final scale in [1.0, 2.0]) {
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
              if (scale == 1) {
                expect(clockRect.right, lessThanOrEqualTo(titleRect.left));
              } else {
                expect(clockRect.bottom, lessThanOrEqualTo(titleRect.top));
              }
              final category = find.byType(CategoryLabel);
              final badge = tester.widget<CategoryLabel>(category);
              expect(badge.category, '배움');
              expect(badge.label, strings.category('배움'));
              expect(
                tester.getRect(category).top,
                greaterThanOrEqualTo(titleRect.bottom),
              );
              expect(find.text(strings.t('높음')), findsOneWidget);
              expect(find.byTooltip(strings.t('반복')), findsOneWidget);
              final paragraph = tester.renderObject<RenderParagraph>(title);
              expect(paragraph.didExceedMaxLines, isFalse);
              expect(titleRect.right, lessThanOrEqualTo(width - 15));
              final toggle = find.byTooltip(
                strings.t(completed ? '완료 해제' : '완료 처리'),
              );
              expect(tester.getSize(toggle).width, greaterThanOrEqualTo(44));
              expect(tester.getSize(toggle).height, greaterThanOrEqualTo(44));
              if (!completed) {
                final start = find.byKey(const ValueKey('start-timeline'));
                expect(tester.getSize(start).width, greaterThanOrEqualTo(44));
                expect(tester.getSize(start).height, greaterThanOrEqualTo(44));
              }
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

  testWidgets('tap, toggle and start remain separate reachable actions', (
    tester,
  ) async {
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
    await tester.tap(find.byTooltip('완료 처리'));
    await tester.tap(find.byKey(const ValueKey('start-timeline')));
    expect([taps, toggles, starts], [1, 1, 1]);
    await _render(
      tester,
      item,
      busy: true,
      onToggle: () => toggles++,
      onStart: () => starts++,
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('start-timeline')))
          .onPressed,
      isNull,
    );
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
