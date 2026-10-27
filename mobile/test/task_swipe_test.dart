import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Swipe UI fixtures do not access the database');
}

class _SettingsRepository extends TaskRepository {
  final settings = <String, String>{};
  _SettingsRepository() : super(_UnusedDatabase());

  @override
  Future<String?> setting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
  }
}

/// Records UI commands and follows the controller's completion contract. The
/// repository's persistence/history behavior is covered by repository tests.
class _SwipeController extends TaskController {
  final actions = <String>[];
  Completer<void>? actionGate;
  Object? nextError;

  _SwipeController(List<Occurrence> occurrences)
    : super(_SettingsRepository(), ReminderScheduler()) {
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
    final index = items.indexWhere((value) => value.id == occurrence.id);
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
  String id = 'swipe-task',
  TaskStatus status = TaskStatus.pending,
  TaskStatus? beforeComplete,
}) {
  final now = DateTime.now();
  final due = DateTime(now.year, now.month, now.day, 23, 59);
  final task = Task(id: id, title: 'Clean the filter', due: due, created: now);
  return Occurrence(
    id: '$id-occurrence',
    task: task,
    originalDue: due,
    reminder: due.add(const Duration(minutes: 20)),
    status: status,
    started: status == TaskStatus.progressing ? now : null,
    completed: status == TaskStatus.completed ? now : null,
    beforeComplete: beforeComplete,
    snoozes: status == TaskStatus.paused ? 2 : 0,
    smallActive: status == TaskStatus.progressing,
  );
}

Future<_SwipeController> _home(
  WidgetTester tester, {
  required List<Occurrence> occurrences,
  String language = 'ko',
  bool largeType = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = largeType
      ? const Size(320, 640)
      : const Size(430, 932);
  tester.platformDispatcher.textScaleFactorTestValue = largeType ? 2 : 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final controller = _SwipeController(occurrences);
  final subscription = _PaidSubscription();
  addTearDown(controller.dispose);
  addTearDown(subscription.dispose);
  await controller.localeController.setPreference(language);
  await tester.pumpWidget(
    HangeoreumApp(controller: controller, subscription: subscription),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('access-notice')), findsNothing);
  return controller;
}

Finder _row(Occurrence occurrence) =>
    find.byKey(ValueKey('task-swipe-${occurrence.id}'));

Future<void> _tab(WidgetTester tester, String language, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(AppStrings(language).t(label)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _swipe(
  WidgetTester tester,
  Occurrence occurrence, {
  required bool right,
  bool settle = true,
}) async {
  final row = _row(occurrence);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  final rect = tester.getRect(row);
  await tester.dragFrom(
    Offset(rect.left + rect.width * (right ? .15 : .85), rect.center.dy),
    Offset(rect.width * (right ? .75 : -.75), 0),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 350));
  }
}

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

  for (final language in ['ko', 'en']) {
    for (final completed in [false, true]) {
      testWidgets(
        '$language ${completed ? 'reopened' : 'completed'} feedback with Undo dismisses after three seconds',
        (tester) async {
          final occurrence = _occurrence(
            status: completed ? TaskStatus.completed : TaskStatus.pending,
          );
          final controller = await _home(
            tester,
            occurrences: [occurrence],
            language: language,
          );
          await _swipe(tester, occurrence, right: !completed);
          final message = AppStrings(language)
              .t(completed ? '완료를 해제했어요.' : '할 일을 완료했어요.');
          final undo = AppStrings(language).t('되돌리기');
          expect(find.text(message), findsOneWidget);
          expect(find.text(undo), findsOneWidget);
          await tester.pump(const Duration(seconds: 2));
          expect(find.text(message), findsOneWidget);
          // Include the short exit animation after the three-second timeout.
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          expect(find.text(message), findsNothing);
          expect(find.text(undo), findsNothing);
          expect(
            controller.items.single.status,
            completed ? TaskStatus.pending : TaskStatus.completed,
          );
          expect(controller.actions, hasLength(1));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets('$language queue swipe completes and Undo restores the row', (
      tester,
    ) async {
      final occurrence = _occurrence();
      final controller = await _home(
        tester,
        occurrences: [occurrence],
        language: language,
      );
      await _tab(tester, language, '예정');
      expect(_row(occurrence), findsOneWidget);
      await _swipe(tester, occurrence, right: true);
      expect(controller.actions, ['${occurrence.id}:complete']);
      expect(controller.items.single.status, TaskStatus.completed);
      expect(_row(occurrence), findsNothing);
      await tester.tap(find.text(AppStrings(language).t('되돌리기')));
      await tester.pumpAndSettle();
      expect(controller.actions.last, '${occurrence.id}:uncomplete');
      expect(controller.items.single.status, TaskStatus.pending);
      expect(_row(occurrence), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      '$language calendar row can complete and uncomplete without deletion',
      (tester) async {
        final occurrence = _occurrence();
        final controller = await _home(
          tester,
          occurrences: [occurrence],
          language: language,
        );
        await _swipe(tester, occurrence, right: true);
        expect(controller.items.single.status, TaskStatus.completed);
        expect(_row(occurrence), findsOneWidget);
        final title = tester.widget<Text>(
          find.descendant(
            of: _row(occurrence),
            matching: find.text(occurrence.task.title),
          ),
        );
        expect(title.style?.decoration, TextDecoration.lineThrough);
        await _swipe(tester, occurrence, right: false);
        expect(controller.items.single.status, TaskStatus.pending);
        expect(controller.items.single.id, occurrence.id);
        expect(controller.actions, [
          '${occurrence.id}:complete',
          '${occurrence.id}:uncomplete',
        ]);
        expect(_row(occurrence), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '$language completed tab left swipe removes only from completed list',
      (tester) async {
        final occurrence = _occurrence(
          status: TaskStatus.completed,
          beforeComplete: TaskStatus.paused,
        );
        final controller = await _home(
          tester,
          occurrences: [occurrence],
          language: language,
        );
        await _tab(tester, language, '완료');
        await _swipe(tester, occurrence, right: false);
        expect(controller.actions, ['${occurrence.id}:uncomplete']);
        expect(controller.items.single.status, TaskStatus.paused);
        expect(_row(occurrence), findsNothing);
        await _tab(tester, language, '예정');
        expect(_row(occurrence), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('$language task swipe fits a 320px screen at 200% text', (
      tester,
    ) async {
      final occurrence = _occurrence();
      final controller = await _home(
        tester,
        occurrences: [occurrence],
        language: language,
        largeType: true,
      );
      await _tab(tester, language, '예정');
      await _swipe(tester, occurrence, right: true);
      expect(controller.items.single.status, TaskStatus.completed);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final state in [
    TaskStatus.pending,
    TaskStatus.progressing,
    TaskStatus.paused,
  ]) {
    testWidgets(
      'swipe complete/uncomplete restores ${state.name} and occurrence identity',
      (tester) async {
        final occurrence = _occurrence(status: state);
        final controller = await _home(tester, occurrences: [occurrence]);
        await _swipe(tester, occurrence, right: true);
        await _swipe(tester, occurrence, right: false);
        final restored = controller.items.single;
        expect(restored.status, state);
        expect(restored.id, occurrence.id);
        expect(restored.task.id, occurrence.task.id);
        expect(restored.originalDue, occurrence.originalDue);
        expect(restored.reminder, occurrence.reminder);
        expect(restored.started, occurrence.started);
        expect(restored.snoozes, occurrence.snoozes);
        expect(restored.smallActive, occurrence.smallActive);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'short drags, vertical drags and the wrong direction do not complete',
    (tester) async {
      final occurrence = _occurrence();
      final controller = await _home(tester, occurrences: [occurrence]);
      await _tab(tester, 'ko', '예정');
      await tester.ensureVisible(_row(occurrence));
      await tester.pumpAndSettle();
      expect(_row(occurrence).hitTestable(), findsOneWidget);
      // Cross touch slop so this is a drag rather than a tap, while remaining
      // below the 35% distance and avoiding a velocity-triggered completion.
      await tester.timedDrag(
        _row(occurrence),
        const Offset(60, 0),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(controller.actions, isEmpty);
      await tester.ensureVisible(_row(occurrence));
      await tester.pumpAndSettle();
      expect(_row(occurrence).hitTestable(), findsOneWidget);
      await tester.timedDrag(
        _row(occurrence),
        const Offset(0, -100),
        const Duration(milliseconds: 400),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(controller.actions, isEmpty);
      await tester.ensureVisible(_row(occurrence));
      await tester.pumpAndSettle();
      expect(_row(occurrence).hitTestable(), findsOneWidget);
      await _swipe(tester, occurrence, right: false);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(controller.actions, isEmpty);
      expect(controller.items.single.status, TaskStatus.pending);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('skipped occurrences cannot be completed or reopened by swipe', (
    tester,
  ) async {
    final occurrence = _occurrence(status: TaskStatus.skipped);
    final controller = await _home(tester, occurrences: [occurrence]);
    await _swipe(tester, occurrence, right: true);
    await _swipe(tester, occurrence, right: false);
    expect(controller.actions, isEmpty);
    expect(controller.items.single.status, TaskStatus.skipped);
    expect(_row(occurrence), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed completion keeps the row and permits a later retry', (
    tester,
  ) async {
    final occurrence = _occurrence();
    final controller = await _home(tester, occurrences: [occurrence]);
    controller.nextError = StateError('storage failure');
    await _tab(tester, 'ko', '예정');
    await _swipe(tester, occurrence, right: true);
    expect(controller.items.single.status, TaskStatus.pending);
    expect(_row(occurrence), findsOneWidget);
    expect(find.text('처리하지 못했습니다. 다시 시도해주세요.'), findsOneWidget);
    await _swipe(tester, occurrence, right: true);
    expect(controller.actions, [
      '${occurrence.id}:complete',
      '${occurrence.id}:complete',
    ]);
    expect(controller.items.single.status, TaskStatus.completed);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'an in-flight swipe blocks repeat swipes and the completion button',
    (tester) async {
      final occurrence = _occurrence();
      final controller = await _home(tester, occurrences: [occurrence]);
      final gate = Completer<void>();
      controller.actionGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await _tab(tester, 'ko', '예정');
      await _swipe(tester, occurrence, right: true, settle: false);
      // Dismissible begins confirmDismiss after its movement animation. Pump
      // bounded frames until the controller command actually enters its gate;
      // pumpAndSettle would wait forever on the intentional busy indicator.
      for (var frame = 0; frame < 20 && controller.actions.isEmpty; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.actions, ['${occurrence.id}:complete']);
      await tester.pump();
      final row = tester.widget<Dismissible>(_row(occurrence));
      expect(row.direction, DismissDirection.none);
      final button = tester.widget<Checkbox>(
        find.descendant(of: _row(occurrence), matching: find.byType(Checkbox)),
      );
      expect(button.onChanged, isNull);
      final rect = tester.getRect(_row(occurrence));
      await tester.dragFrom(rect.center, Offset(rect.width * .7, 0));
      await tester.pump(const Duration(milliseconds: 350));
      expect(controller.actions, hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
      expect(controller.items.single.status, TaskStatus.completed);
      expect(_row(occurrence), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
