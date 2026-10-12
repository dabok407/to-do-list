import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/features/persistent_time_picker.dart';
import 'package:hangeoreum/features/pro_screen.dart';
import 'package:hangeoreum/features/task_editor.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart'
    show PreviewController, PreviewSubscription;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hangeoreum/services/widget_service.dart';

Future<PreviewController> _app(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 932);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = PreviewController();
  final subscription = PreviewSubscription();
  addTearDown(controller.dispose);
  addTearDown(subscription.dispose);
  await controller.setLanguage('ko');
  // The browser preview and the native entry point use this same app shell.
  await tester.pumpWidget(
    HangeoreumApp(controller: controller, subscription: subscription),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _touch(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target, kind: PointerDeviceKind.touch);
  await tester.pumpAndSettle();
}

Finder _editable(Finder field) =>
    find.descendant(of: field, matching: find.byType(EditableText));

EditableText _input(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(_editable(field));

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await _touch(tester, field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
  expect(_input(tester, field).focusNode.hasFocus, isTrue);
  expect(tester.testTextInput.isVisible, isTrue);
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
  setUp(
    () => SharedPreferences.setMockInitialValues({
      timePickerEntryModePreference: 'input',
    }),
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('${platform.name} 손가락 외부 터치는 초안을 유지하고 분류·Pro 버튼도 실행한다', (
      tester,
    ) async {
      final controller = await _app(tester);
      final before = (await controller.repository.tasks()).length;
      await _touch(tester, find.byKey(const Key('quick-add')));
      final field = find.byKey(const Key('quick-add-title'));
      await _type(tester, field, '아직 저장하지 않은 할 일');
      final rect = tester.getRect(field);
      await tester.tapAt(
        Offset(rect.left - 8, rect.center.dy),
        kind: PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
      expect(_input(tester, field).focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(_input(tester, field).controller.text, '아직 저장하지 않은 할 일');

      await _touch(tester, field);
      await _touch(tester, find.widgetWithText(ChoiceChip, '업무'));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '업무'))
            .selected,
        isTrue,
      );
      expect(_input(tester, field).focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(_input(tester, field).controller.text, '아직 저장하지 않은 할 일');

      await _touch(tester, field);
      await _touch(tester, find.byKey(const Key('access-notice')));
      expect(find.byType(ProScreen), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      await _touch(tester, find.byType(BackButton));
      expect(_input(tester, field).controller.text, '아직 저장하지 않은 할 일');
      expect(await controller.repository.tasks(), hasLength(before));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(platform));

    testWidgets('${platform.name} 입력창 영역을 건드리지 않는 스크롤 드래그도 자판을 내린다', (
      tester,
    ) async {
      await _app(tester);
      final draft = TextEditingController();
      final focus = FocusNode();
      final scroll = ScrollController();
      addTearDown(draft.dispose);
      addTearDown(focus.dispose);
      addTearDown(scroll.dispose);
      Navigator.of(tester.element(find.byKey(const Key('quick-add')))).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: ListView(
              controller: scroll,
              children: [
                TextField(
                  key: const Key('scroll-draft'),
                  controller: draft,
                  focusNode: focus,
                ),
                // Keep the down event in the field's region so this test
                // isolates drag dismissal from outside-tap dismissal.
                const TextFieldTapRegion(
                  child: ColoredBox(
                    color: Colors.white,
                    child: SizedBox(key: Key('scroll-area'), height: 300),
                  ),
                ),
                const SizedBox(height: 1600),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('scroll-draft'));
      await _type(tester, field, '드래그 후에도 남을 내용');
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('scroll-area'))),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(_input(tester, field).focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await gesture.moveBy(const Offset(0, -160));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(focus.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(draft.text, '드래그 후에도 남을 내용');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(platform));

    testWidgets('${platform.name} 상세 화면의 입력창 이동·외부 터치·저장은 같은 터치로 동작한다', (
      tester,
    ) async {
      final controller = await _app(tester);
      final before = (await controller.repository.tasks()).length;
      await _touch(tester, find.byTooltip('할 일 추가'));
      expect(find.byType(TaskEditor), findsOneWidget);
      final title = find.byKey(const Key('editor-title'));
      final note = find.byKey(const Key('editor-note'));
      await _type(tester, title, '상세 입력 내용 보존');
      await _touch(tester, note);
      expect(_input(tester, title).focusNode.hasFocus, isFalse);
      expect(_input(tester, note).focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.enterText(note, '메모도 유지');
      await tester.pumpAndSettle();
      final rect = tester.getRect(note);
      await tester.tapAt(
        Offset(rect.left - 8, rect.center.dy),
        kind: PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
      expect(_input(tester, note).focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(_input(tester, title).controller.text, '상세 입력 내용 보존');
      expect(_input(tester, note).controller.text, '메모도 유지');
      await _touch(tester, note);
      await _touch(tester, find.widgetWithText(FilledButton, '저장'));
      expect(find.byType(TaskEditor), findsNothing);
      final stored = await controller.repository.tasks();
      expect(stored, hasLength(before + 1));
      final added = stored.singleWhere((task) => task.title == '상세 입력 내용 보존');
      expect(added.note, '메모도 유지');
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(platform));

    testWidgets('${platform.name} 시간 입력 대화상자도 입력창 이동과 외부 터치 후 값을 유지한다', (
      tester,
    ) async {
      await _app(tester);
      await _touch(tester, find.byKey(const Key('quick-add')));
      await _touch(tester, find.byKey(const Key('quick-add-time')));
      final fields = find.byType(TextFormField);
      await _type(tester, fields.at(0), '9');
      await _touch(tester, fields.at(1));
      expect(_input(tester, fields.at(0)).focusNode.hasFocus, isFalse);
      expect(_input(tester, fields.at(1)).focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.enterText(fields.at(1), '27');
      await tester.pumpAndSettle();
      await _touch(tester, find.text('시간 입력'));
      expect(_input(tester, fields.at(1)).focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(_input(tester, fields.at(0)).controller.text, '9');
      expect(_input(tester, fields.at(1)).controller.text, '27');
      await _touch(tester, fields.at(1));
      await _touch(tester, find.text('확인'));
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('quick-add-time')),
          matching: find.textContaining(':27'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(platform));
  }
}
