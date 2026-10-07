import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/task_editor.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:sqflite/sqflite.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Layout fixtures must not access the database');
}

class _LayoutController extends TaskController {
  Task? savedTask;

  _LayoutController()
    : super(TaskRepository(_UnusedDatabase()), ReminderScheduler()) {
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day, 19);
    final task = Task(
      id: 'layout',
      title: '안방을 정리하고 내일 입을 옷을 준비하기',
      due: due,
      created: now,
      smallStep: '의자에 놓인 옷 한 벌만 정리하기',
    );
    items = [
      Occurrence(
        id: 'layout@${due.toIso8601String()}',
        task: task,
        originalDue: due,
        reminder: due,
      ),
    ];
  }

  @override
  Future<void> refresh({DateTime? through}) async => notifyListeners();

  @override
  Future<void> reconcile() async => notifyListeners();

  @override
  Future<void> save(Task task) async {
    savedTask = task;
    notifyListeners();
  }
}

void _smallScreen(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  tester.platformDispatcher.textScaleFactorTestValue = 1.5;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  setUpAll(() async {
    // Use the shipped font so overflow reports represent the production UI.
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });

  for (final repeat in [
    RepeatUnit.none,
    RepeatUnit.weekly,
    RepeatUnit.monthlyWeekday,
    RepeatUnit.weeklyGoal,
  ]) {
    testWidgets('320px · 글꼴 1.5배 ${repeat.name} 폼에서 저장 가능', (tester) async {
      _smallScreen(tester);
      final controller = _LayoutController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(HangeoreumApp(controller: controller));
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.enterText(
        find.byType(TextFormField).first,
        '좁은 화면에서도 저장하는 할 일',
      );
      final dropdown = find.byType(DropdownButtonFormField<RepeatUnit>);
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      if (repeat != RepeatUnit.none) {
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        final label = switch (repeat) {
          RepeatUnit.weekly => '매주 · 요일 선택',
          RepeatUnit.monthlyWeekday => '매월 특정 번째 요일',
          RepeatUnit.weeklyGoal => '요일 자유 · 주 N회',
          _ => '한 번',
        };
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);

      final scrollable = find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('저장'),
        180,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('저장').hitTestable(), findsOneWidget);
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.savedTask?.title, '좁은 화면에서도 저장하는 할 일');
      expect(controller.savedTask?.repeat, repeat);
      expect(find.byType(TaskEditor), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('320px · 글꼴 1.5배 캘린더에서 월·주 전환과 날짜 선택 가능', (tester) async {
    _smallScreen(tester);
    final controller = _LayoutController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(HangeoreumApp(controller: controller));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('주 보기'));
    await tester.tap(find.text('주 보기'));
    await tester.pumpAndSettle();
    expect(find.text('월 보기'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('월 보기'));
    await tester.pumpAndSettle();
    expect(find.text('주 보기'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final day = find
        .descendant(of: find.byType(GridView), matching: find.text('15'))
        .first;
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining(RegExp(r'^\d+월 15일$')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
