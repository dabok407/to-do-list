import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/task_completion_checkbox.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Completion feedback fixtures do not use native storage',
  );
}

class _Repository extends TaskRepository {
  final settings = <String, String>{};
  _Repository() : super(_UnusedDatabase());

  @override
  Future<String?> setting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
  }
}

/// Only the command/presentation boundary is faked. Database transactions and
/// reminder cancellation remain the responsibility of controller/repository
/// tests; these cases ensure visual feedback never delays the command itself.
class _Controller extends TaskController {
  final actions = <String>[];
  Completer<void>? actionGate;
  Object? nextError;

  _Controller(List<Occurrence> occurrences)
    : super(_Repository(), ReminderScheduler()) {
    items = List.of(occurrences);
  }

  @override
  Future<void> act(
    Occurrence occurrence,
    String action, {
    int minutes = 10,
  }) async {
    actions.add('${occurrence.id}:$action');
    if (actionGate != null) await actionGate!.future;
    if (nextError != null) {
      final error = nextError!;
      nextError = null;
      throw error;
    }
    final index = items.indexWhere((item) => item.id == occurrence.id);
    final current = items[index];
    final completing = action == 'complete';
    items[index] = Occurrence(
      id: current.id,
      task: current.task,
      originalDue: current.originalDue,
      reminder: current.reminder,
      status: completing
          ? TaskStatus.completed
          : current.beforeComplete ?? TaskStatus.pending,
      started: current.started,
      completed: completing ? DateTime.now() : null,
      snoozes: current.snoozes,
      smallActive: current.smallActive,
      beforeComplete: completing ? current.status : null,
    );
    notifyListeners();
  }

  @override
  Future<void> undoCompletion(Occurrence before, Occurrence after) async {
    actions.add('${before.id}:undoCompletion');
    if (actionGate != null) await actionGate!.future;
    if (nextError != null) {
      final error = nextError!;
      nextError = null;
      throw error;
    }
    final index = items.indexWhere((item) => item.id == before.id);
    items[index] = before;
    notifyListeners();
  }

  @override
  Future<void> refresh({DateTime? through}) async => notifyListeners();

  @override
  Future<void> reconcile() async => notifyListeners();
}

class _PaidSubscription extends SubscriptionService {
  @override
  bool get hasAccess => true;
  @override
  bool get paidAccess => true;
  @override
  bool get trialActive => false;
  @override
  Future<void> refresh() async {}
}

Occurrence _occurrence({
  String id = 'filter',
  TaskStatus status = TaskStatus.pending,
  TaskStatus? beforeComplete,
  int daysFromToday = 0,
  RepeatUnit repeat = RepeatUnit.none,
}) {
  final now = DateTime.now();
  final due = DateTime(now.year, now.month, now.day + daysFromToday, 23, 59);
  return Occurrence(
    id: '$id-occurrence',
    task: Task(
      id: id,
      title: '할 일 $id',
      due: due,
      created: now,
      repeat: repeat,
    ),
    originalDue: due,
    reminder: due.add(const Duration(minutes: 20)),
    status: status,
    beforeComplete: beforeComplete,
    completed: status == TaskStatus.completed ? now : null,
    snoozes: status == TaskStatus.paused ? 2 : 0,
  );
}

Future<_Controller> _home(
  WidgetTester tester, {
  required List<Occurrence> occurrences,
  int page = 1,
  String language = 'ko',
  double width = 375,
  double height = 1050,
  double textScale = 1,
  double bottomPadding = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  tester.view.padding = FakeViewPadding(bottom: bottomPadding);
  tester.view.viewPadding = FakeViewPadding(bottom: bottomPadding);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final controller = _Controller(occurrences);
  final subscription = _PaidSubscription();
  addTearDown(controller.dispose);
  addTearDown(subscription.dispose);
  await controller.localeController.setPreference(language);
  await tester.pumpWidget(
    HangeoreumApp(
      controller: controller,
      subscription: subscription,
      initialPage: page,
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Finder _row(Occurrence occurrence) =>
    find.byKey(ValueKey('task-swipe-${occurrence.id}'));

Finder _check(Occurrence occurrence) => find.descendant(
  of: _row(occurrence),
  matching: find.byType(TaskCompletionCheckbox),
);

Future<void> _tapCheck(WidgetTester tester, Occurrence occurrence) async {
  await tester.ensureVisible(_row(occurrence));
  await tester.tap(_check(occurrence));
  await tester.pump();
}

Future<void> _finishRemoval(WidgetTester tester) async {
  // Advance the success hold and then the collapse in separate frames. A
  // timer does not keep pumpAndSettle running, so relying on it alone misses
  // the interval during which the saved row deliberately stays visible.
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pump();
}

Future<void> _openRemaining(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('overdue-banner')));
  await tester.pumpAndSettle();
}

Future<void> _openDetail(WidgetTester tester, Occurrence occurrence) async {
  final row = find.byKey(ValueKey('task-row-${occurrence.id}'));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Finder _sheetUndo() => find.descendant(
  of: find.byKey(const Key('sheet-feedback')),
  matching: find.text('되돌리기'),
);

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WidgetService.channel, (call) async {
          if (call.method == 'getCalendarPreferences') {
            return {'regionCode': 'KR', 'firstDayOfWeek': 0};
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WidgetService.channel, null);
    AppStrings.current = const AppStrings('ko');
  });

  for (final gesture in ['checkbox', 'left', 'right']) {
    testWidgets(
      'remaining sheet $gesture holds its saved row and date before showing empty state',
      (tester) async {
        final occurrence = _occurrence(daysFromToday: -2);
        final controller = await _home(
          tester,
          occurrences: [occurrence],
          page: 0,
        );
        await _openRemaining(tester);
        final date = const AppStrings('ko').t(
          '{date} 예정',
          args: {'date': const AppStrings('ko').date(occurrence.originalDue)},
        );
        expect(find.text(date), findsOneWidget);
        if (gesture == 'checkbox') {
          await _tapCheck(tester, occurrence);
        } else {
          final rect = tester.getRect(_row(occurrence));
          final right = gesture == 'right';
          await tester.dragFrom(
            Offset(
              rect.left + rect.width * (right ? .15 : .85),
              rect.center.dy,
            ),
            Offset(rect.width * (right ? .75 : -.75), 0),
          );
          for (
            var frame = 0;
            frame < 12 && controller.actions.isEmpty;
            frame++
          ) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pump();
        }
        expect(controller.actions, ['${occurrence.id}:complete']);
        expect(controller.items.single.status, TaskStatus.completed);
        expect(_row(occurrence), findsOneWidget);
        expect(
          tester.widget<TaskCompletionCheckbox>(_check(occurrence)).completed,
          isTrue,
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(_row(occurrence), findsOneWidget);
        expect(find.text(date), findsOneWidget);
        expect(find.text('남은 일을 모두 마쳤어요.'), findsNothing);
        expect(_sheetUndo().hitTestable(), findsOneWidget);
        await _finishRemoval(tester);
        expect(_row(occurrence), findsNothing);
        expect(find.text(date), findsNothing);
        expect(find.text('남은 일을 모두 마쳤어요.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('remaining sheet Undo restores the row after it has moved away', (
    tester,
  ) async {
    final occurrence = _occurrence(
      daysFromToday: -2,
      status: TaskStatus.paused,
    );
    final controller = await _home(tester, occurrences: [occurrence], page: 0);
    await _openRemaining(tester);
    await _tapCheck(tester, occurrence);
    await _finishRemoval(tester);
    expect(_row(occurrence), findsNothing);
    expect(_sheetUndo().hitTestable(), findsOneWidget);
    await tester.tap(_sheetUndo());
    await tester.pumpAndSettle();
    expect(controller.items.single, same(occurrence));
    expect(_row(occurrence), findsOneWidget);
    expect(find.text('남은 일을 모두 마쳤어요.'), findsNothing);
    expect(controller.actions, [
      '${occurrence.id}:complete',
      '${occurrence.id}:undoCompletion',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'remaining sheet save failure stays visible without false success or Undo',
    (tester) async {
      final occurrence = _occurrence(daysFromToday: -2);
      final controller = await _home(
        tester,
        occurrences: [occurrence],
        page: 0,
      );
      await _openRemaining(tester);
      controller.nextError = StateError('storage failure');
      await _tapCheck(tester, occurrence);
      await _finishRemoval(tester);
      expect(controller.items.single.status, TaskStatus.pending);
      expect(_row(occurrence), findsOneWidget);
      expect(
        tester.widget<TaskCompletionCheckbox>(_check(occurrence)).completed,
        isFalse,
      );
      expect(find.text('할 일을 완료했어요.'), findsNothing);
      expect(_sheetUndo(), findsNothing);
      expect(
        find
            .descendant(
              of: find.byKey(const Key('sheet-feedback')),
              matching: find.text('처리하지 못했습니다. 다시 시도해주세요.'),
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final completed in [false, true]) {
    testWidgets(
      'detail ${completed ? 'reopens' : 'completes'} in place and Undo restores its original state',
      (tester) async {
        final occurrence = _occurrence(
          status: completed ? TaskStatus.completed : TaskStatus.paused,
          beforeComplete: completed ? TaskStatus.paused : null,
        );
        final controller = await _home(
          tester,
          occurrences: [occurrence],
          page: completed ? 2 : 1,
        );
        await _openDetail(tester, occurrence);
        await tester.tap(
          find.widgetWithText(OutlinedButton, completed ? '완료 해제' : '완료했어요'),
        );
        await tester.pump();
        expect(
          controller.items.single.status,
          completed ? TaskStatus.paused : TaskStatus.completed,
        );
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text(occurrence.task.title).hitTestable(), findsOneWidget);
        expect(_sheetUndo().hitTestable(), findsOneWidget);
        await tester.tap(_sheetUndo());
        await tester.pumpAndSettle();
        expect(controller.items.single, same(occurrence));
        expect(controller.items.single.completed, occurrence.completed);
        expect(controller.items.single.reminder, occurrence.reminder);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(controller.actions, [
          '${occurrence.id}:${completed ? 'uncomplete' : 'complete'}',
          '${occurrence.id}:undoCompletion',
        ]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'detail blocks duplicate completion while saving and safely closes before completion',
    (tester) async {
      final occurrence = _occurrence();
      final controller = await _home(tester, occurrences: [occurrence]);
      await _openDetail(tester, occurrence);
      final gate = Completer<void>();
      controller.actionGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final button = find.widgetWithText(OutlinedButton, '완료했어요');
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      await tester.tap(button);
      await tester.pump();
      expect(controller.actions, ['${occurrence.id}:complete']);
      expect(controller.items.single.status, TaskStatus.pending);
      expect(find.text('할 일을 완료했어요.'), findsNothing);
      await tester.tap(find.byTooltip('닫기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BottomSheet), findsNothing);
      gate.complete();
      await tester.pump();
      await _finishRemoval(tester);
      expect(controller.items.single.status, TaskStatus.completed);
      expect(controller.actions, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [320.0, 375.0]) {
    for (final language in ['ko', 'en']) {
      testWidgets(
        'detail feedback fits $width px $language at 200% text above the bottom safe area and expires',
        (tester) async {
          const bottomInset = 34.0;
          const height = 812.0;
          final occurrence = _occurrence(status: TaskStatus.completed);
          final controller = await _home(
            tester,
            occurrences: [occurrence],
            page: 2,
            language: language,
            width: width,
            height: height,
            textScale: 2,
            bottomPadding: bottomInset,
          );
          final strings = AppStrings(language);
          await _openDetail(tester, occurrence);
          final reopen = find.widgetWithText(
            OutlinedButton,
            strings.t('완료 해제'),
          );
          await tester.ensureVisible(reopen);
          await tester.tap(reopen);
          await tester.pump();
          final feedback = find.byKey(const Key('sheet-feedback'));
          final undo = find.descendant(
            of: feedback,
            matching: find.text(strings.t('되돌리기')),
          );
          expect(controller.items.single.status, TaskStatus.pending);
          expect(undo.hitTestable(), findsOneWidget);
          final rect = tester.getRect(feedback);
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.bottom, lessThanOrEqualTo(height - bottomInset));
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(milliseconds: 2200));
          expect(undo.hitTestable(), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 900));
          expect(feedback, findsNothing);
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'repeat edit scope is exclusive and selected radio cannot be unchecked',
    (tester) async {
      final occurrence = _occurrence(repeat: RepeatUnit.daily);
      await _home(tester, occurrences: [occurrence]);
      await _openDetail(tester, occurrence);
      final edit = find.widgetWithText(TextButton, '수정');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final continueButton = find.widgetWithText(FilledButton, '계속');
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
      final onlyThis = find.widgetWithText(RadioListTile<bool>, '이번 일정만');
      final future = find.widgetWithText(RadioListTile<bool>, '이번부터 앞으로');
      await tester.tap(onlyThis);
      await tester.pump();
      expect(
        tester
            .widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>))
            .groupValue,
        isTrue,
      );
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
      await tester.tap(future);
      await tester.pump();
      expect(
        tester
            .widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>))
            .groupValue,
        isFalse,
      );
      await tester.tap(future);
      await tester.pump();
      expect(
        tester
            .widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>))
            .groupValue,
        isFalse,
      );
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final completed in [false, true]) {
    testWidgets(
      'checkbox ${completed ? 'reopens' : 'completes'} immediately but holds the saved state before removal',
      (tester) async {
        final occurrence = _occurrence(
          status: completed ? TaskStatus.completed : TaskStatus.pending,
          beforeComplete: completed ? TaskStatus.paused : null,
        );
        final controller = await _home(
          tester,
          occurrences: [occurrence],
          page: completed ? 2 : 1,
        );
        await _tapCheck(tester, occurrence);
        expect(controller.actions, [
          '${occurrence.id}:${completed ? 'uncomplete' : 'complete'}',
        ]);
        expect(
          controller.items.single.status,
          completed ? TaskStatus.paused : TaskStatus.completed,
        );
        expect(_row(occurrence), findsOneWidget);
        expect(
          tester.widget<TaskCompletionCheckbox>(_check(occurrence)).completed,
          !completed,
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(_row(occurrence), findsOneWidget);
        expect(find.text('되돌리기'), findsOneWidget);
        await _finishRemoval(tester);
        expect(_row(occurrence), findsNothing);
        expect(controller.items.single.id, occurrence.id);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    for (final right in [false, true]) {
      testWidgets(
        '${completed ? 'completed' : 'upcoming'} ${right ? 'right' : 'left'} swipe shares the saved-state feedback',
        (tester) async {
          final occurrence = _occurrence(
            status: completed ? TaskStatus.completed : TaskStatus.pending,
          );
          final controller = await _home(
            tester,
            occurrences: [occurrence],
            page: completed ? 2 : 1,
          );
          final rect = tester.getRect(_row(occurrence));
          await tester.dragFrom(
            Offset(
              rect.left + rect.width * (right ? .15 : .85),
              rect.center.dy,
            ),
            Offset(rect.width * (right ? .75 : -.75), 0),
          );
          for (
            var frame = 0;
            frame < 12 && controller.actions.isEmpty;
            frame++
          ) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pump();
          expect(controller.actions, [
            '${occurrence.id}:${completed ? 'uncomplete' : 'complete'}',
          ]);
          expect(_row(occurrence), findsOneWidget);
          expect(
            tester.widget<TaskCompletionCheckbox>(_check(occurrence)).completed,
            !completed,
          );
          expect(find.text('되돌리기'), findsOneWidget);
          await _finishRemoval(tester);
          expect(_row(occurrence), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('success hold starts only after the save has succeeded', (
    tester,
  ) async {
    final occurrence = _occurrence();
    final controller = await _home(tester, occurrences: [occurrence]);
    final gate = Completer<void>();
    controller.actionGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await _tapCheck(tester, occurrence);
    expect(controller.actions, ['${occurrence.id}:complete']);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(controller.items.single.status, TaskStatus.pending);
    expect(_row(occurrence), findsOneWidget);
    expect(
      tester.widget<TaskCompletionCheckbox>(_check(occurrence)).completed,
      false,
    );
    expect(
      tester.widget<TaskCompletionCheckbox>(_check(occurrence)).enabled,
      false,
    );
    expect(find.text('할 일을 완료했어요.'), findsNothing);
    gate.complete();
    await tester.pump();
    expect(controller.items.single.status, TaskStatus.completed);
    expect(
      tester.widget<TaskCompletionCheckbox>(_check(occurrence)).completed,
      true,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(_row(occurrence), findsOneWidget);
    await _finishRemoval(tester);
    expect(_row(occurrence), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a saved row stays full height for one second then collapses', (
    tester,
  ) async {
    final occurrence = _occurrence();
    await _home(tester, occurrences: [occurrence]);
    final feedback = find.byKey(ValueKey('task-feedback-${occurrence.id}'));
    final originalHeight = tester.getSize(feedback).height;
    expect(originalHeight, greaterThan(0));
    await _tapCheck(tester, occurrence);
    await tester.pump(const Duration(milliseconds: 950));
    expect(tester.getSize(feedback).height, closeTo(originalHeight, .5));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 90));
    final shrinkingHeight = tester.getSize(feedback).height;
    expect(shrinkingHeight, greaterThan(0));
    expect(shrinkingHeight, lessThan(originalHeight));
    await tester.pump(const Duration(milliseconds: 120));
    expect(_row(occurrence), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Undo during the hold prevents delayed removal of the restored row',
    (tester) async {
      final occurrence = _occurrence(status: TaskStatus.paused);
      final controller = await _home(tester, occurrences: [occurrence]);
      await _tapCheck(tester, occurrence);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('되돌리기'));
      await tester.pump();
      expect(controller.items.single.status, TaskStatus.paused);
      await _finishRemoval(tester);
      expect(_row(occurrence), findsOneWidget);
      expect(
        tester.widget<TaskCompletionCheckbox>(_check(occurrence)).completed,
        false,
      );
      expect(controller.actions, [
        '${occurrence.id}:complete',
        '${occurrence.id}:undoCompletion',
      ]);
      expect(controller.items.single.originalDue, occurrence.originalDue);
      expect(controller.items.single.reminder, occurrence.reminder);
      expect(controller.items.single.snoozes, occurrence.snoozes);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Undo after removal restores the original completed occurrence', (
    tester,
  ) async {
    final occurrence = _occurrence(
      status: TaskStatus.completed,
      beforeComplete: TaskStatus.paused,
    );
    final controller = await _home(tester, occurrences: [occurrence], page: 2);
    await _tapCheck(tester, occurrence);
    await _finishRemoval(tester);
    expect(_row(occurrence), findsNothing);
    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    expect(_row(occurrence), findsOneWidget);
    expect(controller.items.single, same(occurrence));
    expect(controller.items.single.completed, occurrence.completed);
    expect(controller.actions, [
      '${occurrence.id}:uncomplete',
      '${occurrence.id}:undoCompletion',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed save keeps the original row and can be retried', (
    tester,
  ) async {
    final occurrence = _occurrence();
    final controller = await _home(tester, occurrences: [occurrence]);
    controller.nextError = StateError('storage failure');
    await _tapCheck(tester, occurrence);
    await _finishRemoval(tester);
    expect(controller.items.single.status, TaskStatus.pending);
    expect(_row(occurrence), findsOneWidget);
    expect(
      tester.widget<TaskCompletionCheckbox>(_check(occurrence)).completed,
      false,
    );
    expect(find.text('되돌리기'), findsNothing);
    expect(find.text('처리하지 못했습니다. 다시 시도해주세요.'), findsOneWidget);
    await _tapCheck(tester, occurrence);
    expect(controller.items.single.status, TaskStatus.completed);
    await _finishRemoval(tester);
    expect(_row(occurrence), findsNothing);
    expect(controller.actions, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'failed Undo does not restore an unsaved row or leave its feedback stuck',
    (tester) async {
      final occurrence = _occurrence();
      final controller = await _home(tester, occurrences: [occurrence]);
      await _tapCheck(tester, occurrence);
      await tester.pump(const Duration(milliseconds: 250));
      controller.nextError = StateError('undo storage failure');
      await tester.tap(find.text('되돌리기'));
      await tester.pump();
      expect(controller.items.single.status, TaskStatus.completed);
      await _finishRemoval(tester);
      expect(_row(occurrence), findsNothing);
      expect(find.text('처리하지 못했습니다. 다시 시도해주세요.'), findsOneWidget);
      expect(controller.actions, [
        '${occurrence.id}:complete',
        '${occurrence.id}:undoCompletion',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'rapid input does not duplicate a command or block another row during its visual hold',
    (tester) async {
      final first = _occurrence(id: 'first');
      final second = _occurrence(id: 'second');
      final controller = await _home(tester, occurrences: [first, second]);
      await tester.tap(_check(first));
      await tester.tap(_check(first));
      await tester.pump();
      expect(controller.actions, ['${first.id}:complete']);
      expect(_row(first), findsOneWidget);
      expect(
        tester.widget<TaskCompletionCheckbox>(_check(first)).enabled,
        false,
      );
      expect(
        tester.widget<TaskCompletionCheckbox>(_check(second)).enabled,
        true,
      );
      await _tapCheck(tester, second);
      expect(controller.actions, [
        '${first.id}:complete',
        '${second.id}:complete',
      ]);
      expect(
        controller.items.every((item) => item.status == TaskStatus.completed),
        isTrue,
      );
      await _finishRemoval(tester);
      expect(_row(first), findsNothing);
      expect(_row(second), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('calendar retains the completed row instead of collapsing it', (
    tester,
  ) async {
    final occurrence = _occurrence();
    final controller = await _home(tester, occurrences: [occurrence], page: 0);
    await _tapCheck(tester, occurrence);
    expect(controller.items.single.status, TaskStatus.completed);
    await _finishRemoval(tester);
    expect(_row(occurrence), findsOneWidget);
    expect(
      tester.widget<TaskCompletionCheckbox>(_check(occurrence)).completed,
      true,
    );
    await _tapCheck(tester, occurrence);
    await _finishRemoval(tester);
    expect(controller.items.single.status, TaskStatus.pending);
    expect(_row(occurrence), findsOneWidget);
    expect(
      tester.widget<TaskCompletionCheckbox>(_check(occurrence)).completed,
      false,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Undo waits for another save instead of dropping the action', (
    tester,
  ) async {
    final first = _occurrence(id: 'first');
    final second = _occurrence(id: 'second');
    final controller = await _home(tester, occurrences: [first, second]);
    await _tapCheck(tester, first);
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    controller.actionGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await _tapCheck(tester, second);
    await tester.tap(find.text('되돌리기'));
    await tester.pump();
    expect(controller.actions, [
      '${first.id}:complete',
      '${second.id}:complete',
    ]);
    gate.complete();
    await tester.pump();
    await _finishRemoval(tester);
    expect(controller.actions.last, '${first.id}:undoCompletion');
    expect(controller.items.first.status, TaskStatus.pending);
    expect(controller.items.last.status, TaskStatus.completed);
    expect(_row(first), findsOneWidget);
    expect(_row(second), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final deleted in [false, true]) {
    testWidgets(
      'external ${deleted ? 'deletion' : 'state change'} cancels stale feedback and Undo',
      (tester) async {
        final occurrence = _occurrence();
        final controller = await _home(tester, occurrences: [occurrence]);
        await _tapCheck(tester, occurrence);
        await tester.pumpAndSettle();
        controller.items = deleted ? [] : [occurrence];
        await controller.refresh();
        await tester.pump();
        await tester.tap(find.text('되돌리기'));
        await _finishRemoval(tester);
        expect(controller.actions, ['${occurrence.id}:complete']);
        expect(_row(occurrence), deleted ? findsNothing : findsOneWidget);
        if (!deleted) {
          expect(controller.items.single.status, TaskStatus.pending);
          expect(
            tester.widget<TaskCompletionCheckbox>(_check(occurrence)).enabled,
            true,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'changing tabs during feedback uses saved state without duplicate rows',
    (tester) async {
      final occurrence = _occurrence();
      final controller = await _home(tester, occurrences: [occurrence]);
      await _tapCheck(tester, occurrence);
      await _tab(tester, '완료');
      expect(_row(occurrence), findsOneWidget);
      expect(
        tester.widget<TaskCompletionCheckbox>(_check(occurrence)).completed,
        true,
      );
      await _finishRemoval(tester);
      expect(_row(occurrence), findsOneWidget);
      await _tab(tester, '예정');
      await tester.pumpAndSettle();
      expect(_row(occurrence), findsNothing);
      expect(controller.actions, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'sorting during the hold preserves other rows and the saved completion',
    (tester) async {
      final near = _occurrence(id: 'near', daysFromToday: 1);
      final completing = _occurrence(id: 'middle', daysFromToday: 2);
      final far = _occurrence(id: 'far', daysFromToday: 3);
      final controller = await _home(
        tester,
        occurrences: [near, completing, far],
      );
      await _tapCheck(tester, completing);
      await tester.tap(find.byKey(const Key('task-sort-menu-upcoming')));
      await tester.pumpAndSettle();
      expect(_row(completing), findsOneWidget);
      await tester.tap(find.byKey(const Key('task-sort-option-oldest')));
      await tester.pump();
      await _finishRemoval(tester);
      expect(_row(completing), findsNothing);
      expect(_row(near), findsOneWidget);
      expect(_row(far), findsOneWidget);
      expect(
        tester.getTopLeft(_row(near)).dy,
        lessThan(tester.getTopLeft(_row(far)).dy),
      );
      expect(
        controller.items
            .where((item) => item.status == TaskStatus.completed)
            .single
            .id,
        completing.id,
      );
      expect(controller.actions, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final saving in [false, true]) {
    testWidgets(
      'disposing during ${saving ? 'save' : 'feedback'} leaves no callback on the removed screen',
      (tester) async {
        final occurrence = _occurrence();
        final controller = await _home(tester, occurrences: [occurrence]);
        final gate = saving ? Completer<void>() : null;
        controller.actionGate = gate;
        addTearDown(() {
          if (gate != null && !gate.isCompleted) gate.complete();
        });
        await _tapCheck(tester, occurrence);
        await tester.pumpWidget(const SizedBox.shrink());
        gate?.complete();
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        expect(controller.items.single.status, TaskStatus.completed);
        expect(controller.actions, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'English checkbox feedback offers Undo and disappears after three seconds',
    (tester) async {
      final occurrence = _occurrence();
      await _home(tester, occurrences: [occurrence], language: 'en');
      await _tapCheck(tester, occurrence);
      final message = const AppStrings('en').t('할 일을 완료했어요.');
      final undo = const AppStrings('en').t('되돌리기');
      // The snackbar's three-second timer starts once its entrance completes.
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.text(undo), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(message), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      expect(find.text(undo), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
