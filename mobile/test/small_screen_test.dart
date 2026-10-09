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
  final actions = <String>[];

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

  @override
  Future<void> act(
    Occurrence occurrence,
    String action, {
    int minutes = 10,
  }) async {
    actions.add(action);
    items = [
      Occurrence(
        id: occurrence.id,
        task: occurrence.task,
        originalDue: occurrence.originalDue,
        reminder: occurrence.reminder,
        status: action == 'complete'
            ? TaskStatus.completed
            : action == 'start'
            ? TaskStatus.progressing
            : TaskStatus.pending,
      ),
    ];
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
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButtonFormField<RepeatUnit>);
      await Scrollable.ensureVisible(tester.element(dropdown), alignment: .3);
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
    await tester.scrollUntilVisible(
      day,
      140,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(day), alignment: .3);
    await tester.pumpAndSettle();
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining(RegExp(r'^\d+월 15일$')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('날짜 선택 후 스크롤·상세 진입 없이 시작·완료·해제 가능', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _LayoutController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(HangeoreumApp(controller: controller));
    await tester.pumpAndSettle();
    final day = find
        .descendant(
          of: find.byType(GridView),
          matching: find.text('${DateTime.now().day}'),
        )
        .first;
    expect(
      day.hitTestable(),
      findsOneWidget,
      reason: '날짜를 찾기 위해 스크롤할 필요가 없어야 한다',
    );
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(find.text('월 보기'), findsOneWidget);
    final start = find.byTooltip('${controller.items.single.task.title} 지금 시작');
    expect(
      start.hitTestable(),
      findsOneWidget,
      reason: '날짜 선택 한 번으로 시작 버튼이 보여야 한다',
    );
    expect(tester.getSize(start).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(start).height, greaterThanOrEqualTo(48));
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(controller.actions, ['start']);
    await tester.tap(find.byTooltip('완료 처리'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('완료 해제').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('완료 해제'));
    await tester.pumpAndSettle();
    expect(controller.actions, ['start', 'complete', 'uncomplete']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('기한 지난 할 일은 첫 화면 상단에서 찾고 완료하면 사라짐', (tester) async {
    _smallScreen(tester);
    final controller = _LayoutController();
    addTearDown(controller.dispose);
    final task = controller.items.single.task;
    final due = DateTime.now().subtract(const Duration(days: 2));
    controller.items = [
      Occurrence(id: 'old', task: task, originalDue: due, reminder: due),
    ];
    await tester.pumpWidget(HangeoreumApp(controller: controller));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overdue-banner')).hitTestable(),
      findsOneWidget,
    );
    expect(
      tester.getBottomLeft(find.byKey(const Key('overdue-banner'))).dy,
      lessThan(tester.getTopLeft(find.byType(AppBar)).dy),
      reason: '남은 일 배너가 년월 제목보다 위에 있어야 한다',
    );
    await tester.tap(find.byKey(const Key('overdue-banner')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('완료 처리').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('완료 처리'));
    await tester.pumpAndSettle();
    expect(find.text('남은 일을 모두 마쳤어요.'), findsOneWidget);
    expect(controller.overdue, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('미완료 배너와 하루 여러 일정이 있어도 작은 달력 셀이 넘치지 않음', (tester) async {
    _smallScreen(tester);
    final controller = _LayoutController();
    addTearDown(controller.dispose);
    final task = controller.items.single.task;
    final now = DateTime.now();
    controller.items = List.generate(4, (i) {
      final due = DateTime(now.year, now.month, now.day - 1, 12 + i);
      return Occurrence(
        id: 'dense-$i',
        task: task,
        originalDue: due,
        reminder: due,
      );
    });
    await tester.pumpWidget(HangeoreumApp(controller: controller));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overdue-banner')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('작은 화면에서 미완료 재알림을 끄고 저장 가능', (tester) async {
    _smallScreen(tester);
    final controller = _LayoutController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(HangeoreumApp(controller: controller));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '필터 청소');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('미완료 재알림'),
      180,
      scrollable: find
          .descendant(
            of: find.byType(TaskEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('미완료 재알림'));
    await tester.pumpAndSettle();
    final interval = find.byKey(const Key('overdue-interval'));
    await tester.ensureVisible(interval);
    await tester.pumpAndSettle();
    await tester.tap(interval);
    await tester.pumpAndSettle();
    await tester.tap(find.text('알리지 않음').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(controller.savedTask?.overdueDays, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('새 할 일은 제목 입력 후 아래 고정 저장 버튼으로 완료', (tester) async {
    _smallScreen(tester);
    final controller = _LayoutController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(HangeoreumApp(controller: controller));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '분리수거');
    expect(
      find.text('저장').hitTestable(),
      findsOneWidget,
      reason: '폼 아래로 스크롤하지 않아도 저장할 수 있어야 한다',
    );
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(controller.savedTask?.title, '분리수거');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
