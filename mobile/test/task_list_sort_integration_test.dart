import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/home_screen.dart';
import 'package:hangeoreum/features/task_list_section_header.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:sqflite/sqflite.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Sorting must not access platform storage');
}

class _Repository extends TaskRepository {
  _Repository() : super(_UnusedDatabase());
}

class _Subscription extends SubscriptionService {
  @override
  bool get hasAccess => true;
  @override
  bool get paidAccess => true;
  @override
  Future<void> refresh() async {}
}

Occurrence _row(
  String id,
  DateTime due, {
  DateTime? completed,
  TaskStatus? status,
}) => Occurrence(
  id: id,
  task: Task(
    id: 'task-$id',
    title: id,
    created: due.subtract(const Duration(days: 10)),
    due: due,
  ),
  originalDue: due,
  reminder: due,
  status:
      status ?? (completed == null ? TaskStatus.pending : TaskStatus.completed),
  completed: completed,
);

class _Controller extends TaskController {
  _Controller() : super(_Repository(), ReminderScheduler()) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    items = [
      _row('upcoming-near', today.add(const Duration(days: 1))),
      _row(
        'done-old',
        today.add(const Duration(days: 2)),
        completed: today.subtract(const Duration(days: 2)),
      ),
      _row('upcoming-far', today.add(const Duration(days: 2))),
      _row(
        'done-new',
        today.subtract(const Duration(days: 5)),
        completed: today.subtract(const Duration(days: 1)),
      ),
    ];
  }

  @override
  Future<void> refresh({DateTime? through}) async => notifyListeners();
  @override
  Future<void> reconcile() async => notifyListeners();
}

Finder _navigation(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void _expectBefore(WidgetTester tester, String first, String second) {
  final firstRow = find.byKey(ValueKey('task-row-$first'));
  final secondRow = find.byKey(ValueKey('task-row-$second'));
  expect(firstRow, findsOneWidget);
  expect(secondRow, findsOneWidget);
  expect(
    tester.getTopLeft(firstRow).dy,
    lessThan(tester.getTopLeft(secondRow).dy),
  );
}

Future<void> _chooseOldest(WidgetTester tester, String pane) async {
  await tester.tap(find.byKey(Key('task-sort-menu-$pane')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('task-sort-option-oldest')));
  await tester.pumpAndSettle();
}

Future<void> _mountHome(
  WidgetTester tester,
  _Controller controller,
  _Subscription subscription,
) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomeScreen(
        controller: controller,
        subscription: subscription,
        initialPage: 1,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Home keeps independent upcoming and completion sort choices', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 1100);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _Controller();
    final subscription = _Subscription();
    addTearDown(controller.dispose);
    addTearDown(subscription.dispose);
    final original = List<Occurrence>.of(controller.items);
    final originalDue = original.map((item) => item.originalDue).toList();
    final originalReminders = original.map((item) => item.reminder).toList();
    final originalCompletions = original.map((item) => item.completed).toList();
    await _mountHome(tester, controller, subscription);
    _expectBefore(tester, 'upcoming-far', 'upcoming-near');
    expect(find.byKey(const Key('upcoming-overdue-summary')), findsNothing);
    expect(find.byKey(const Key('upcoming-overdue-boundary')), findsNothing);
    expect(find.text('최신순'), findsOneWidget);
    await _chooseOldest(tester, 'upcoming');
    _expectBefore(tester, 'upcoming-near', 'upcoming-far');
    expect(find.text('오래된순'), findsOneWidget);

    await tester.tap(_navigation('완료'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upcoming-overdue-summary')), findsNothing);
    expect(find.byKey(const Key('upcoming-overdue-boundary')), findsNothing);
    expect(find.text('최신순'), findsOneWidget);
    _expectBefore(tester, 'done-new', 'done-old');
    await _chooseOldest(tester, 'completed');
    _expectBefore(tester, 'done-old', 'done-new');

    await tester.tap(_navigation('예정'));
    await tester.pumpAndSettle();
    expect(find.text('오래된순'), findsOneWidget);
    _expectBefore(tester, 'upcoming-near', 'upcoming-far');
    await tester.tap(_navigation('완료'));
    await tester.pumpAndSettle();
    expect(find.text('오래된순'), findsOneWidget);
    _expectBefore(tester, 'done-old', 'done-new');

    expect(controller.items, orderedEquals(original));
    for (var i = 0; i < original.length; i++) {
      expect(identical(controller.items[i], original[i]), isTrue);
    }
    expect(controller.items.map((item) => item.originalDue), originalDue);
    expect(controller.items.map((item) => item.reminder), originalReminders);
    expect(controller.items.map((item) => item.completed), originalCompletions);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Upcoming summarizes overdue dates once without counting progressing tasks',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      // Keep every group mounted; responsive sizing is covered by screen tests.
      tester.view.physicalSize = const Size(375, 1700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _Controller();
      final subscription = _Subscription();
      addTearDown(controller.dispose);
      addTearDown(subscription.dispose);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      controller.items = [
        _row(
          'progressing',
          today.subtract(const Duration(days: 3)),
          status: TaskStatus.progressing,
        ),
        _row('overdue-old-early', today.subtract(const Duration(days: 2))),
        _row(
          'overdue-old-late',
          today.subtract(const Duration(days: 2)).add(const Duration(hours: 1)),
        ),
        _row('overdue-new', today.subtract(const Duration(days: 1))),
        _row('future', today.add(const Duration(days: 1))),
        _row(
          'done',
          today.subtract(const Duration(days: 4)),
          completed: today.subtract(const Duration(days: 1)),
        ),
      ];
      await _mountHome(tester, controller, subscription);
      final summary = find.byKey(const Key('upcoming-overdue-summary'));
      final boundary = find.byKey(const Key('upcoming-overdue-boundary'));
      void expectSummary() {
        expect(summary, findsOneWidget);
        expect(find.text('기한 지난 일'), findsOneWidget);
        expect(
          find.descendant(of: summary, matching: find.text('3개')),
          findsOneWidget,
        );
      }

      expectSummary();
      expect(boundary, findsOneWidget);
      _expectBefore(tester, 'progressing', 'overdue-new');
      _expectBefore(tester, 'overdue-new', 'overdue-old-late');
      _expectBefore(tester, 'overdue-old-late', 'overdue-old-early');
      _expectBefore(tester, 'overdue-old-early', 'future');
      expect(
        tester.getTopLeft(summary).dy,
        greaterThan(
          tester
              .getBottomLeft(find.byKey(const ValueKey('task-row-progressing')))
              .dy,
        ),
      );
      expect(
        tester.getTopLeft(boundary).dy,
        greaterThanOrEqualTo(
          tester
              .getBottomLeft(
                find.byKey(const ValueKey('task-row-overdue-old-early')),
              )
              .dy,
        ),
      );

      await _chooseOldest(tester, 'upcoming');
      expectSummary();
      expect(boundary, findsOneWidget);
      _expectBefore(tester, 'progressing', 'overdue-old-early');
      _expectBefore(tester, 'overdue-old-early', 'overdue-old-late');
      _expectBefore(tester, 'overdue-old-late', 'overdue-new');
      _expectBefore(tester, 'overdue-new', 'future');

      // Without a following scheduled group, no trailing separator remains.
      controller.items = controller.items
          .where((item) => item.id != 'future')
          .toList();
      await controller.refresh();
      await tester.pumpAndSettle();
      expectSummary();
      expect(boundary, findsNothing);

      await tester.tap(_navigation('완료'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-row-done')), findsOneWidget);
      expect(summary, findsNothing);
      expect(boundary, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Overdue toggle filters presentation and keeps sorting and tab state without changing tasks',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 1500);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _Controller();
      final subscription = _Subscription();
      addTearDown(controller.dispose);
      addTearDown(subscription.dispose);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      controller.items = [
        _row('overdue-new', today.subtract(const Duration(days: 1))),
        _row('overdue-old', today.subtract(const Duration(days: 2))),
        _row(
          'progressing',
          today.subtract(const Duration(days: 3)),
          status: TaskStatus.progressing,
        ),
        _row('future', today.add(const Duration(days: 1))),
        _row('done', today, completed: today),
      ];
      final original = List<Occurrence>.of(controller.items);
      await _mountHome(tester, controller, subscription);
      final summary = find.byKey(const Key('upcoming-overdue-summary'));
      expect(tester.widget<TaskListOverdueHeader>(summary).selected, isFalse);
      await _chooseOldest(tester, 'upcoming');
      await tester.tap(summary);
      await tester.pumpAndSettle();
      expect(tester.widget<TaskListOverdueHeader>(summary).selected, isTrue);
      expect(find.byKey(const ValueKey('task-row-progressing')), findsNothing);
      expect(find.byKey(const ValueKey('task-row-future')), findsNothing);
      expect(find.byKey(const ValueKey('task-row-done')), findsNothing);
      expect(find.text('오래된순'), findsOneWidget);
      _expectBefore(tester, 'overdue-old', 'overdue-new');

      await tester.tap(find.byKey(const Key('task-sort-menu-upcoming')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-sort-option-latest')));
      await tester.pumpAndSettle();
      _expectBefore(tester, 'overdue-new', 'overdue-old');
      await tester.tap(_navigation('완료'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-row-done')), findsOneWidget);
      expect(summary, findsNothing);
      await tester.tap(_navigation('예정'));
      await tester.pumpAndSettle();
      expect(tester.widget<TaskListOverdueHeader>(summary).selected, isTrue);
      expect(find.byKey(const ValueKey('task-row-future')), findsNothing);
      await tester.tap(summary);
      await tester.pumpAndSettle();
      expect(tester.widget<TaskListOverdueHeader>(summary).selected, isFalse);
      _expectBefore(tester, 'progressing', 'overdue-new');
      _expectBefore(tester, 'overdue-new', 'overdue-old');
      _expectBefore(tester, 'overdue-old', 'future');
      expect(controller.items, orderedEquals(original));
      for (var i = 0; i < original.length; i++) {
        expect(identical(controller.items[i], original[i]), isTrue);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
