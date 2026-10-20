import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class _NoDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Focus fixtures must not access platform storage');
}

class _FocusRepository extends TaskRepository {
  final settings = <String, String>{};
  _FocusRepository() : super(_NoDatabase());

  @override
  Future<String?> setting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
  }

  @override
  Future<List<Task>> tasks() async => [];
}

class _FocusController extends TaskController {
  final saved = <Task>[];
  _FocusController() : super(_FocusRepository(), ReminderScheduler());

  @override
  Future<void> reconcile() async {}

  @override
  Future<void> save(Task task) async => saved.add(task);
}

class _PaidSubscription extends SubscriptionService {
  @override
  bool get paidAccess => true;
  @override
  bool get hasAccess => true;
  @override
  Future<void> refresh() async {}
}

Future<_FocusController> _openQuickAdd(
  WidgetTester tester, {
  Size size = const Size(375, 812),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = _FocusController();
  await controller.localeController.setPreference('ko');
  final subscription = _PaidSubscription();
  addTearDown(controller.dispose);
  addTearDown(subscription.dispose);
  await tester.pumpWidget(
    HangeoreumApp(controller: controller, subscription: subscription),
  );
  await tester.pumpAndSettle();
  final header = find.byKey(const Key('quick-add'));
  await tester.ensureVisible(header);
  await tester.pumpAndSettle();
  await tester.tap(header);
  await tester.pumpAndSettle();
  return controller;
}

Finder get _title => find.byKey(const Key('quick-add-title'));
Finder get _fab => find.byType(FloatingActionButton);

Future<void> _focusTitle(WidgetTester tester, {String? draft}) async {
  await tester.ensureVisible(_title);
  await tester.pumpAndSettle();
  await tester.tap(_title);
  if (draft != null) await tester.enterText(_title, draft);
  await tester.pumpAndSettle();
}

void _expectFocused(WidgetTester tester, bool focused) {
  expect(tester.widget<TextField>(_title).focusNode!.hasFocus, focused);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  for (final size in [const Size(375, 812), const Size(402, 874)]) {
    testWidgets(
      'quick title focus hides FAB and outside tap restores it $size',
      (tester) async {
        await _openQuickAdd(tester, size: size);
        expect(_fab, findsOneWidget);

        // Focus alone should remove the competing add control, including when
        // a hardware keyboard is used and there is no software keyboard inset.
        await _focusTitle(tester);
        _expectFocused(tester, true);
        expect(_fab, findsNothing);
        await tester.enterText(_title, '입력 중인 할 일');
        await tester.pumpAndSettle();
        expect(_fab, findsNothing);

        final hint = find.byKey(const Key('quick-add-time-hint'));
        await tester.ensureVisible(hint);
        await tester.pumpAndSettle();
        await tester.tap(hint);
        await tester.pumpAndSettle();
        _expectFocused(tester, false);
        expect(_fab, findsOneWidget);
        expect(tester.widget<TextField>(_title).controller!.text, '입력 중인 할 일');

        // Restoring focus must hide the button again; blur must remain reusable.
        await _focusTitle(tester);
        expect(_fab, findsNothing);
        await tester.tap(hint);
        await tester.pumpAndSettle();
        expect(_fab, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'keyboard submission restores FAB and empty validation hides it',
    (tester) async {
      final controller = await _openQuickAdd(tester);
      await _focusTitle(tester, draft: '등록할 일');
      expect(_fab, findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.saved.single.title, '등록할 일');
      _expectFocused(tester, false);
      expect(_fab, findsOneWidget);

      // An invalid add returns focus to the same field instead of exposing a
      // second add action while the user is correcting the empty draft.
      final arrow = find.byTooltip('빠른 추가');
      await tester.ensureVisible(arrow);
      await tester.pumpAndSettle();
      await tester.tap(arrow);
      await tester.pumpAndSettle();
      expect(find.text('할 일을 입력해주세요.'), findsOneWidget);
      _expectFocused(tester, true);
      expect(_fab, findsNothing);
      expect(controller.saved, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'opening and cancelling time picker restores FAB without draft loss',
    (tester) async {
      await _openQuickAdd(tester);
      await _focusTitle(tester, draft: '시간을 바꿀 일');
      expect(_fab, findsNothing);
      final time = find.byKey(const Key('quick-add-time'));
      await tester.ensureVisible(time);
      await tester.pumpAndSettle();
      await tester.tap(time);
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      _expectFocused(tester, false);
      expect(_fab, findsOneWidget);
      expect(tester.widget<TextField>(_title).controller!.text, '시간을 바꿀 일');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
