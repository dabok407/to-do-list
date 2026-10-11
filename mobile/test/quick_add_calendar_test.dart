import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Quick add fixtures must not access the database');
}

class _QuickRepository extends TaskRepository {
  final stored = <Task>[];
  Completer<void>? readGate;
  Object? readError;
  _QuickRepository() : super(_UnusedDatabase());

  @override
  Future<List<Task>> tasks() async {
    if (readGate != null) await readGate!.future;
    if (readError != null) throw readError!;
    return List.of(stored);
  }
}

class _QuickController extends TaskController {
  final _QuickRepository fixture;
  final saved = <Task>[];
  _QuickController(this.fixture) : super(fixture, ReminderScheduler());

  void seed(Task task) {
    fixture.stored.add(task);
    items.add(
      Occurrence(
        id: '${task.id}@${task.due.toIso8601String()}',
        task: task,
        originalDue: task.due,
        reminder: task.due,
      ),
    );
  }

  @override
  Future<void> save(Task task) async {
    saved.add(task);
    seed(task);
    notifyListeners();
  }

  @override
  Future<void> refresh({DateTime? through}) async => notifyListeners();
  @override
  Future<void> reconcile() async => notifyListeners();
}

class _TrialSubscription extends SubscriptionService {
  @override
  bool get hasAccess => true;
  @override
  bool get paidAccess => false;
  @override
  bool get trialActive => true;
  @override
  Future<void> refresh() async {}
}

Future<_QuickController> _home(
  WidgetTester tester, {
  Size size = const Size(430, 932),
  double scale = 1,
  List<Task> tasks = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final controller = _QuickController(_QuickRepository());
  final subscription = _TrialSubscription();
  for (final task in tasks) {
    controller.seed(task);
  }
  addTearDown(controller.dispose);
  addTearDown(subscription.dispose);
  await tester.pumpWidget(
    HangeoreumApp(controller: controller, subscription: subscription),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _expand(WidgetTester tester) async {
  final header = find.byKey(const Key('quick-add'));
  await tester.ensureVisible(header);
  await tester.pumpAndSettle();
  await tester.tap(header);
  await tester.pump();
}

Future<void> _add(WidgetTester tester, String title) async {
  final field = find.byKey(const Key('quick-add-title'));
  await tester.ensureVisible(field);
  await tester.enterText(field, title);
  // Let EditableText's own caret scroll finish before moving the suffix button.
  // Otherwise its delayed scroll can invalidate the button position mid-tap.
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(
    tester.element(find.byTooltip('빠른 추가')),
    alignment: .5,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('빠른 추가'));
  await tester.pump(const Duration(milliseconds: 300));
  // The in-flight save indicator intentionally remains active while the user
  // decides whether a duplicate is allowed; wait for the dialog, not infinity.
  if (find.byType(AlertDialog).evaluate().isEmpty) await tester.pumpAndSettle();
}

Task _task(String id, String title, DateTime due) =>
    Task(id: id, title: title, due: due, created: DateTime.now());

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('month date selection preserves month and updates the day list', (
    tester,
  ) async {
    final now = DateTime.now();
    final chosen = DateTime(now.year, now.month, 16);
    final controller = await _home(
      tester,
      tasks: [
        _task('on16', '선택한 날짜에서만 보이는 일', chosen.add(const Duration(hours: 19))),
      ],
    );
    final date = find.byKey(Key('calendar-date-${dayKey(chosen)}'));
    await tester.ensureVisible(date);
    await tester.tap(date);
    await tester.pumpAndSettle();
    expect(find.text('주 보기'), findsOneWidget);
    expect(find.text('월 보기'), findsNothing);
    expect(
      find.byKey(
        Key('calendar-date-${dayKey(DateTime(now.year, now.month, 1))}'),
      ),
      findsOneWidget,
    );
    final row = find.widgetWithText(
      ListTile,
      controller.items.single.task.title,
    );
    await tester.ensureVisible(row);
    expect(row, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('manually selected week view remains week after a date tap', (
    tester,
  ) async {
    await _home(tester);
    await tester.tap(find.text('주 보기'));
    await tester.pumpAndSettle();
    final chosen = weekOf(DateTime.now()).add(const Duration(days: 1));
    await tester.tap(find.byKey(Key('calendar-date-${dayKey(chosen)}')));
    await tester.pumpAndSettle();
    expect(find.text('월 보기'), findsOneWidget);
    expect(find.text('주 보기'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'arrow registers the selected calendar day and explicitly chosen time',
    (tester) async {
      final controller = await _home(tester);
      final now = DateTime.now();
      final chosen = DateTime(now.year, now.month, 16);
      final date = find.byKey(Key('calendar-date-${dayKey(chosen)}'));
      await tester.ensureVisible(date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      await _expand(tester);
      final time = find.byKey(const Key('quick-add-time'));
      await tester.ensureVisible(time);
      await tester.tap(time);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final inputs = find.byType(TextFormField);
      final uses12HourClock = find.text('오후').evaluate().isNotEmpty;
      await tester.enterText(inputs.at(0), uses12HourClock ? '2' : '14');
      await tester.enterText(inputs.at(1), '37');
      if (uses12HourClock) await tester.tap(find.text('오후'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(
        find.byType(TimePickerDialog),
        findsNothing,
        reason: 'The accepted 2:37 PM / 14:37 time must close the picker before adding a task.',
      );
      await _add(tester, '  에어컨 필터 청소  ');
      expect(controller.saved.single.title, '에어컨 필터 청소');
      expect(
        controller.saved.single.due,
        chosen.add(const Duration(hours: 14, minutes: 37)),
      );
      expect(find.text('할 일을 등록했어요.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('quick-add-title')))
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('empty arrow submission shows validation and saves nothing', (
    tester,
  ) async {
    final controller = await _home(tester);
    await _expand(tester);
    await _add(tester, '   ');
    expect(find.text('할 일을 입력해주세요.'), findsOneWidget);
    expect(controller.saved, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keyboard done registers once, not only the arrow', (
    tester,
  ) async {
    final controller = await _home(tester);
    await _expand(tester);
    final field = find.byKey(const Key('quick-add-title'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '키보드로 추가하는 일');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.saved.single.title, '키보드로 추가하는 일');
    expect(dayOf(controller.saved.single.due), dayOf(DateTime.now()));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'duplicate cancellation keeps the draft, explicit approval creates another ID',
    (tester) async {
      final now = DateTime.now();
      final controller = await _home(
        tester,
        tasks: [
          _task(
            'already-there',
            'FILTER   Clean',
            now.add(const Duration(hours: 4)),
          ),
        ],
      );
      await _expand(tester);
      await _add(tester, '  filter clean ');
      expect(find.text('중복된 내용입니다.'), findsOneWidget);
      expect(controller.saved, isEmpty);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('quick-add-title')))
            .controller!
            .text,
        '  filter clean ',
      );
      await tester.tap(find.byTooltip('빠른 추가'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('그래도 등록'));
      await tester.pumpAndSettle();
      expect(controller.saved.single.title, 'filter clean');
      expect(controller.saved.single.id, isNot('already-there'));
      expect(controller.fixture.stored, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'two rapid arrow taps cannot register twice during duplicate lookup',
    (tester) async {
      final controller = await _home(tester);
      controller.fixture.readGate = Completer<void>();
      await _expand(tester);
      final field = find.byKey(const Key('quick-add-title'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '한 번만 등록');
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('빠른 추가')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('빠른 추가'));
      // Exercise two deliveries before the disabled button is rendered.
      await tester.tap(find.byTooltip('빠른 추가'));
      await tester.pump();
      expect(controller.saved, isEmpty);
      controller.fixture.readGate!.complete();
      await tester.pumpAndSettle();
      expect(controller.saved, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failed lookup keeps the title and allows retry', (tester) async {
    final controller = await _home(tester);
    controller.fixture.readError = StateError('read failed');
    await _expand(tester);
    await _add(tester, '오류 후 다시 등록');
    expect(controller.saved, isEmpty);
    expect(find.text('처리하지 못했습니다. 다시 시도해주세요.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('quick-add-title')))
          .controller!
          .text,
      '오류 후 다시 등록',
    );
    controller.fixture.readError = null;
    await tester.tap(find.byTooltip('빠른 추가'));
    await tester.pumpAndSettle();
    expect(controller.saved.single.title, '오류 후 다시 등록');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        '${platform.name} 320px ${scale}x expansion leaves the trial card separated on every frame',
        (tester) async {
          await _home(tester, size: const Size(320, 640), scale: scale);
          final card = find.byKey(const Key('quick-add-card'));
          final notice = find.byKey(const Key('access-notice'));
          for (var cycle = 0; cycle < 3; cycle++) {
            await _expand(tester);
            for (final duration in [0, 16, 80, 200]) {
              await tester.pump(Duration(milliseconds: duration));
              expect(
                tester.getRect(notice).top - tester.getRect(card).bottom,
                greaterThanOrEqualTo(16),
              );
              expect(tester.takeException(), isNull);
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }
}
