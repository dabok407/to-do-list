import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/home_screen.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:sqflite/sqflite.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Quick add fixtures must not access the database');
}

class _QuickRepository extends TaskRepository {
  final stored = <Task>[];
  final settings = <String, String>{};
  var reads = 0;
  Completer<void>? readGate;
  Object? readError;
  _QuickRepository() : super(_UnusedDatabase());

  @override
  Future<List<Task>> tasks() async {
    reads++;
    if (readGate != null) await readGate!.future;
    if (readError != null) throw readError!;
    return List.of(stored);
  }

  @override
  Future<String?> setting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
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
  String language = 'ko',
  List<Task> tasks = const [],
  GlobalKey? pixelBoundary,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final controller = _QuickController(_QuickRepository());
  await controller.localeController.setPreference(language);
  final subscription = _TrialSubscription();
  for (final task in tasks) {
    controller.seed(task);
  }
  addTearDown(controller.dispose);
  addTearDown(subscription.dispose);
  final app = HangeoreumApp(controller: controller, subscription: subscription);
  await tester.pumpWidget(
    pixelBoundary == null
        ? app
        : RepaintBoundary(key: pixelBoundary, child: app),
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

Future<TimeOfDay> _chooseTime(
  WidgetTester tester, {
  bool accept = true,
  TimeOfDay? value,
}) async {
  final time = find.byKey(const Key('quick-add-time'));
  await tester.ensureVisible(time);
  await tester.pumpAndSettle();
  await tester.tap(time);
  await tester.pumpAndSettle();
  final initial = tester
      .widget<TimePickerDialog>(find.byType(TimePickerDialog))
      .initialTime;
  if (value != null) {
    if (find.byIcon(Icons.keyboard_outlined).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
    }
    final uses12HourClock = find.text('오후').evaluate().isNotEmpty;
    final hour = uses12HourClock
        ? (value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod)
        : value.hour;
    await tester.enterText(find.byType(TextFormField).at(0), '$hour');
    await tester.enterText(find.byType(TextFormField).at(1), '${value.minute}');
    if (uses12HourClock) {
      await tester.tap(find.text(value.hour >= 12 ? '오후' : '오전'));
    }
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(accept ? '확인' : '취소'));
  await tester.pumpAndSettle();
  expect(find.byType(TimePickerDialog), findsNothing);
  return initial;
}

void _expectDefaultDue(DateTime due, DateTime before, DateTime after) {
  DateTime toMinute(DateTime value) =>
      DateTime(value.year, value.month, value.day, value.hour, value.minute);
  expect(due.isBefore(toMinute(before.add(const Duration(hours: 1)))), isFalse);
  expect(due.isAfter(toMinute(after.add(const Duration(hours: 1)))), isFalse);
}

void _expectDueHint(WidgetTester tester, DateTime due) {
  final finder = find.byKey(const Key('quick-add-time-hint'));
  final strings = AppStrings.of(tester.element(finder));
  final hint = tester.widget<Text>(finder);
  expect(hint.data, contains(strings.dateShort(due)));
  expect(hint.data, contains(strings.time(due)));
  expect(hint.semanticsLabel, isNull);
}

Task _task(String id, String title, DateTime due) =>
    Task(id: id, title: title, due: due, created: DateTime.now());

Future<void> _expectCardBordersAtLayout(
  WidgetTester tester,
  GlobalKey boundary,
  String frame,
) async {
  // Capture the whole Scaffold, since a ListTile's shape can paint into an
  // ancestor Material outside the tile's own bounds. Rect-only checks miss it.
  final pixels = await tester.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    final height = image.height;
    image.dispose();
    return (bytes!, width, height);
  });
  final (bytes, width, height) = pixels!;
  final noticeTile = find.descendant(
    of: find.byKey(const Key('access-notice')),
    matching: find.byType(ListTile),
  );
  for (final card in [find.byKey(const Key('quick-add-card')), noticeTile]) {
    final rect = tester.getRect(card);
    expect(
      rect.top,
      greaterThanOrEqualTo(0),
      reason: '$frame: card is visible',
    );
    expect(rect.bottom, lessThan(height), reason: '$frame: card is visible');
    final left = (rect.left + 20).ceil();
    final right = (rect.right - 20).floor();
    var largestBorderRun = 0;
    // A one-pixel outline may cover two rows because of fractional layout.
    for (var y = rect.top.floor() - 1; y <= rect.top.ceil() + 1; y++) {
      if (y < 0 || y >= height) continue;
      var borderPixels = 0;
      for (var x = left; x < right; x++) {
        final offset = (y * width + x) * 4;
        final r = bytes.getUint8(offset);
        final g = bytes.getUint8(offset + 1);
        final b = bytes.getUint8(offset + 2);
        // Neutral light-gray outline, including anti-aliasing with white.
        if (r >= 205 &&
            r <= 250 &&
            g >= r &&
            b >= g &&
            b - r <= 12 &&
            bytes.getUint8(offset + 3) == 255) {
          borderPixels++;
        }
      }
      if (borderPixels > largestBorderRun) largestBorderRun = borderPixels;
    }
    expect(
      largestBorderRun,
      greaterThan((right - left) * .8),
      reason:
          '$frame: painted outline must follow layout at y=${rect.top}; '
          'scrolling must not be needed to repair it',
    );
  }
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          WidgetService.channel,
          (call) async => call.method == 'getCalendarPreferences'
              ? {'regionCode': 'KR', 'firstDayOfWeek': 0}
              : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WidgetService.channel, null);
  });
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('quick default is one hour later with minute precision', () {
    final now = DateTime(2026, 10, 17, 13, 23, 45, 200);
    expect(
      defaultQuickDue(DateTime(2026, 10, 17), now),
      DateTime(2026, 10, 17, 14, 23),
    );
  });

  test('quick default moves to the following day across midnight', () {
    final now = DateTime(2026, 12, 31, 23, 40);
    expect(
      defaultQuickDue(DateTime(2026, 12, 31), now),
      DateTime(2027, 1, 1, 0, 40),
    );
  });

  test('another selected day keeps its date and uses the next-hour clock', () {
    expect(
      defaultQuickDue(DateTime(2026, 11, 2), DateTime(2026, 10, 17, 15, 18)),
      DateTime(2026, 11, 2, 16, 18),
    );
    expect(
      defaultQuickDue(DateTime(2026, 10, 1), DateTime(2026, 10, 17, 23, 40)),
      DateTime(2026, 10, 1, 0, 40),
    );
  });

  testWidgets('month date selection opens its week and updates the day list', (
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
    expect(find.text('월 보기'), findsOneWidget);
    expect(find.text('주 보기'), findsNothing);
    expect(find.byKey(Key('calendar-date-${dayKey(chosen)}')), findsOneWidget);
    expect(
      tester
          .widget<GridView>(find.byType(GridView))
          .childrenDelegate
          .estimatedChildCount,
      7,
    );
    final row = find.widgetWithText(
      ListTile,
      controller.items.single.task.title,
    );
    await tester.ensureVisible(row);
    expect(row, findsOneWidget);
    await tester.ensureVisible(find.text('월 보기'));
    await tester.tap(find.text('월 보기'));
    await tester.pumpAndSettle();
    expect(find.text('주 보기'), findsOneWidget);
    expect(find.text('월 보기'), findsNothing);
    expect(
      tester
          .widget<GridView>(find.byType(GridView))
          .childrenDelegate
          .estimatedChildCount,
      greaterThan(7),
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
    final before = DateTime.now();
    await _expand(tester);
    final field = find.byKey(const Key('quick-add-title'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '키보드로 추가하는 일');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.saved.single.title, '키보드로 추가하는 일');
    _expectDefaultDue(controller.saved.single.due, before, DateTime.now());
    expect(controller.saved.single.priority, 0);
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
      await _chooseTime(tester);
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
      await _chooseTime(tester);
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
    await _chooseTime(tester);
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

  for (final action in ['arrow', 'keyboard done']) {
    testWidgets(
      '$action uses the displayed next-hour default without opening the picker',
      (tester) async {
        final controller = await _home(tester);
        final before = DateTime.now();
        await _expand(tester);
        final initialReads = controller.fixture.reads;
        expect(find.text('시간 선택'), findsNothing);
        expect(find.text('시간을 먼저 선택해주세요.'), findsNothing);
        if (action == 'arrow') {
          await _add(tester, '기본 시간으로 등록하는 일');
        } else {
          final field = find.byKey(const Key('quick-add-title'));
          await tester.ensureVisible(field);
          await tester.enterText(field, '기본 시간으로 등록하는 일');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
        }
        expect(controller.fixture.reads, initialReads + 1);
        expect(controller.saved.single.title, '기본 시간으로 등록하는 일');
        expect(controller.saved.single.priority, 0);
        _expectDefaultDue(controller.saved.single.due, before, DateTime.now());
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('quick-add-title')))
              .controller!
              .text,
          isEmpty,
        );
        expect(find.text('할 일을 등록했어요.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'cancelled time picker keeps the displayed default and permits add',
    (tester) async {
      final controller = await _home(tester);
      final before = DateTime.now();
      await _expand(tester);
      final previousHint = tester
          .widget<Text>(find.byKey(const Key('quick-add-time-hint')))
          .data;
      await _chooseTime(tester, accept: false);
      expect(
        tester.widget<Text>(find.byKey(const Key('quick-add-time-hint'))).data,
        previousHint,
      );
      await _add(tester, '취소해도 기본 시간은 유지');
      expect(controller.saved, hasLength(1));
      _expectDefaultDue(controller.saved.single.due, before, DateTime.now());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('cancelled replacement keeps a previously selected manual time', (
    tester,
  ) async {
    final controller = await _home(tester);
    await _expand(tester);
    await _chooseTime(tester, value: const TimeOfDay(hour: 16, minute: 42));
    final previousHint = tester
        .widget<Text>(find.byKey(const Key('quick-add-time-hint')))
        .data;
    await _chooseTime(
      tester,
      accept: false,
      value: const TimeOfDay(hour: 9, minute: 8),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('quick-add-time-hint'))).data,
      previousHint,
    );
    await _add(tester, '시간 변경 취소');
    expect(controller.saved.single.due.hour, 16);
    expect(controller.saved.single.due.minute, 42);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'each successful registration resets the next draft to the next-hour default',
    (tester) async {
      final controller = await _home(tester);
      await _expand(tester);
      const manual = TimeOfDay(hour: 22, minute: 47);
      await _chooseTime(tester, value: manual);
      final beforeSave = DateTime.now();
      await _add(tester, '첫 번째 등록');
      expect(controller.saved, hasLength(1));
      expect(controller.saved.single.due.hour, manual.hour);
      expect(controller.saved.single.due.minute, manual.minute);
      expect(find.text('시간 선택'), findsNothing);
      final nextInitial = await _chooseTime(tester, accept: false);
      await _add(tester, '두 번째 등록');
      expect(controller.saved.map((task) => task.title), [
        '첫 번째 등록',
        '두 번째 등록',
      ]);
      final next = controller.saved.last;
      _expectDefaultDue(next.due, beforeSave, DateTime.now());
      expect(TimeOfDay.fromDateTime(next.due), nextInitial);
      expect(next.priority, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'reopening quick add preserves the manually selected draft time',
    (tester) async {
      final controller = await _home(tester);
      await _expand(tester);
      const manual = TimeOfDay(hour: 3, minute: 17);
      await _chooseTime(tester, value: manual);
      await _expand(tester);
      await _expand(tester);
      final reopenedTime = await _chooseTime(tester, accept: false);
      expect(reopenedTime, manual);
      await _add(tester, '다시 펼쳐도 수동 시간 유지');
      expect(controller.saved.single.due.hour, manual.hour);
      expect(controller.saved.single.due.minute, manual.minute);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('reopening an automatic draft uses the next-hour default', (
    tester,
  ) async {
    final controller = await _home(tester);
    await _expand(tester);
    await _chooseTime(tester, accept: false);
    await _expand(tester);
    final beforeReopen = DateTime.now();
    await _expand(tester);
    await _add(tester, '다시 펼친 기본 시간');
    _expectDefaultDue(
      controller.saved.single.due,
      beforeReopen,
      DateTime.now(),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('changing the calendar date keeps the manually chosen clock', (
    tester,
  ) async {
    final controller = await _home(tester);
    await _expand(tester);
    const manual = TimeOfDay(hour: 17, minute: 26);
    await _chooseTime(tester, value: manual);
    final now = DateTime.now();
    final chosen = DateTime(now.year, now.month, now.day == 16 ? 17 : 16);
    final date = find.byKey(Key('calendar-date-${dayKey(chosen)}'));
    await Scrollable.ensureVisible(tester.element(date), alignment: .5);
    await tester.pumpAndSettle();
    expect(date.hitTestable(), findsOneWidget);
    await tester.tap(date.hitTestable());
    await tester.pumpAndSettle();
    final due = chosen.add(const Duration(hours: 17, minutes: 26));
    _expectDueHint(tester, due);
    await _add(tester, '날짜만 바꿔도 선택한 시간 유지');
    expect(controller.saved.single.due, due);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('another calendar day uses its date and the next-hour default', (
    tester,
  ) async {
    final controller = await _home(tester);
    final now = DateTime.now();
    final chosen = DateTime(now.year, now.month, now.day == 16 ? 17 : 16);
    final date = find.byKey(Key('calendar-date-${dayKey(chosen)}'));
    await tester.ensureVisible(date);
    await tester.tap(date);
    await tester.pumpAndSettle();
    final before = DateTime.now();
    await _expand(tester);
    await _add(tester, '다른 날짜 기본 시간');
    final due = controller.saved.single.due;
    expect(dayOf(due), chosen);
    expect(
      TimeOfDay.fromDateTime(due),
      isIn([
        TimeOfDay.fromDateTime(before.add(const Duration(hours: 1))),
        TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))),
      ]),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in ['ko', 'en']) {
    testWidgets(
      '$language quick Other selection saves its stable category key',
      (tester) async {
        final controller = await _home(tester, language: language);
        await _expand(tester);
        final other = find.widgetWithText(
          ChoiceChip,
          language == 'en' ? 'Other' : '기타',
        );
        await tester.ensureVisible(other);
        await tester.tap(other);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(other).selected, isTrue);
        final title = find.byKey(const Key('quick-add-title'));
        await tester.ensureVisible(title);
        await tester.enterText(title, 'Other category task');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(controller.saved.single.category, '기타');
        expect(controller.saved.single.priority, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final language in ['ko', 'en']) {
    testWidgets(
      '$language 320px at 2x text places time, hint and category before the title',
      (tester) async {
        await _home(
          tester,
          size: const Size(320, 2200),
          scale: 2,
          language: language,
        );
        await _expand(tester);
        final time = tester.getRect(find.byKey(const Key('quick-add-time')));
        final hint = tester.getRect(
          find.byKey(const Key('quick-add-time-hint')),
        );
        final title = tester.getRect(find.byKey(const Key('quick-add-title')));
        final categories = find.descendant(
          of: find.byKey(const Key('quick-add-card')),
          matching: find.byType(ChoiceChip),
        );
        expect(time.bottom, lessThanOrEqualTo(hint.top));
        for (final category in categories.evaluate()) {
          final rect = tester.getRect(find.byWidget(category.widget));
          expect(hint.bottom, lessThanOrEqualTo(rect.top));
          expect(rect.bottom, lessThanOrEqualTo(title.top));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
        }
        expect(time.height, greaterThanOrEqualTo(48));
        expect(time.left, greaterThanOrEqualTo(0));
        expect(time.right, lessThanOrEqualTo(320));
        expect(title.left, greaterThanOrEqualTo(0));
        expect(title.right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final (size, scale) in [
      (const Size(430, 1600), 1.0),
      (const Size(320, 2200), 2.0),
    ]) {
      testWidgets(
        '${platform.name} ${scale}x pixels follow quick expansion and inline error without scrolling',
        (tester) async {
          final boundary = GlobalKey();
          // Keep both cards visible throughout. No scroll events may repair the
          // ancestor Ink position while this repaint regression is exercised.
          await _home(
            tester,
            size: size,
            scale: scale,
            pixelBoundary: boundary,
          );
          await _expectCardBordersAtLayout(tester, boundary, 'collapsed');
          for (var cycle = 0; cycle < 2; cycle++) {
            await tester.tap(find.byKey(const Key('quick-add')));
            await tester.pump();
            await _expectCardBordersAtLayout(
              tester,
              boundary,
              'expanded $cycle',
            );
            await tester.tap(find.byTooltip('빠른 추가'));
            await tester.pump();
            expect(find.text('할 일을 입력해주세요.'), findsOneWidget);
            await _expectCardBordersAtLayout(tester, boundary, 'error $cycle');
            await tester.enterText(
              find.byKey(const Key('quick-add-title')),
              '청소',
            );
            await tester.pump();
            expect(find.text('할 일을 입력해주세요.'), findsNothing);
            await _expectCardBordersAtLayout(
              tester,
              boundary,
              'cleared $cycle',
            );
            await tester.enterText(
              find.byKey(const Key('quick-add-title')),
              '',
            );
            await tester.pump();
            await tester.tap(find.byKey(const Key('quick-add')));
            await tester.pump();
            await _expectCardBordersAtLayout(
              tester,
              boundary,
              'collapsed $cycle',
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }

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
