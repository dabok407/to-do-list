import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task_list_sections.dart';
import 'package:hangeoreum/features/task_list_sort_control.dart';
import 'package:hangeoreum/l10n/app_strings.dart';

Future<void> _showControl(
  WidgetTester tester, {
  String language = 'ko',
  double width = 375,
  double textScale = 1,
  bool completed = false,
  TaskListOrder initialOrder = TaskListOrder.latest,
  ValueChanged<TaskListOrder>? onChanged,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var order = initialOrder;
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: StatefulBuilder(
            builder: (context, setState) => TaskListSortControl(
              completed: completed,
              order: order,
              onChanged: (value) {
                setState(() => order = value);
                onChanged?.call(value);
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _menu(bool completed) =>
    find.byKey(Key('task-sort-menu-${completed ? 'completed' : 'upcoming'}'));

void main() {
  for (final completed in [false, true]) {
    testWidgets(
      '${completed ? 'completed' : 'upcoming'} menu changes order only after selection',
      (tester) async {
        final changes = <TaskListOrder>[];
        await _showControl(
          tester,
          completed: completed,
          onChanged: changes.add,
        );
        expect(find.text(completed ? '완료일 기준' : '예정일 기준'), findsOneWidget);
        expect(find.text('최신순'), findsOneWidget);
        expect(
          tester.getSize(_menu(completed)).height,
          greaterThanOrEqualTo(44),
        );
        await tester.tap(_menu(completed));
        await tester.pumpAndSettle();
        expect(changes, isEmpty);
        expect(
          find.byKey(const Key('task-sort-option-latest')),
          findsOneWidget,
        );
        final oldest = find.byKey(const Key('task-sort-option-oldest'));
        expect(oldest, findsOneWidget);
        expect(tester.getSize(oldest).height, greaterThanOrEqualTo(44));
        await tester.tap(oldest);
        await tester.pumpAndSettle();
        expect(changes, [TaskListOrder.oldest]);
        expect(find.text('오래된순'), findsOneWidget);
        await tester.tap(_menu(completed));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('task-sort-option-latest')));
        await tester.pumpAndSettle();
        expect(changes, [TaskListOrder.oldest, TaskListOrder.latest]);
        expect(find.text('최신순'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('dismissing the popup does not change the selected order', (
    tester,
  ) async {
    final changes = <TaskListOrder>[];
    await _showControl(
      tester,
      initialOrder: TaskListOrder.oldest,
      onChanged: changes.add,
    );
    await tester.tap(_menu(false));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 800));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.text('오래된순'), findsOneWidget);
    expect(find.byKey(const Key('task-sort-option-latest')), findsNothing);
  });

  for (final language in ['ko', 'en']) {
    for (final width in [320.0, 375.0, 402.0]) {
      for (final textScale in [1.0, 2.0]) {
        for (final completed in [false, true]) {
          testWidgets(
            '$language $width at ${textScale}x ${completed ? 'completed' : 'upcoming'} control and options fit',
            (tester) async {
              final strings = AppStrings(language);
              await _showControl(
                tester,
                language: language,
                width: width,
                textScale: textScale,
                completed: completed,
              );
              expect(
                find.text(strings.t(completed ? '완료일 기준' : '예정일 기준')),
                findsOneWidget,
              );
              expect(find.text(strings.t('최신순')), findsOneWidget);
              final rect = tester.getRect(_menu(completed));
              expect(rect.height, greaterThanOrEqualTo(44));
              expect(rect.left, greaterThanOrEqualTo(16));
              expect(rect.right, lessThanOrEqualTo(width - 16));
              expect(tester.takeException(), isNull);
              await tester.tap(_menu(completed));
              await tester.pumpAndSettle();
              for (final order in TaskListOrder.values) {
                final option = find.byKey(
                  Key('task-sort-option-${order.name}'),
                );
                expect(option, findsOneWidget);
                expect(tester.getSize(option).height, greaterThanOrEqualTo(44));
                final label = strings.t(
                  order == TaskListOrder.latest ? '최신순' : '오래된순',
                );
                expect(
                  find.descendant(of: option, matching: find.text(label)),
                  findsOneWidget,
                );
              }
              expect(tester.takeException(), isNull);
              await tester.tap(
                find.byKey(const Key('task-sort-option-oldest')),
              );
              await tester.pumpAndSettle();
              expect(find.text(strings.t('오래된순')), findsOneWidget);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }
}
