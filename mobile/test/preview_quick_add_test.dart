import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/persistent_time_picker.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart'
    show PreviewController, PreviewSubscription;
import 'package:shared_preferences/shared_preferences.dart';

Future<PreviewController> _preview(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 932);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = PreviewController();
  final subscription = PreviewSubscription();
  addTearDown(controller.dispose);
  addTearDown(subscription.dispose);
  await controller.setLanguage('ko');
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

Future<void> _add(WidgetTester tester, String title) async {
  final field = find.byKey(const Key('quick-add-title'));
  await tester.ensureVisible(field);
  await tester.enterText(field, title);
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(
    tester.element(find.byTooltip('빠른 추가')),
    alignment: .5,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('빠른 추가'));
  await tester.pump(const Duration(milliseconds: 300));
  if (find.byType(AlertDialog).evaluate().isEmpty) await tester.pumpAndSettle();
}

Future<void> _chooseTime(WidgetTester tester) async {
  final time = find.byKey(const Key('quick-add-time'));
  await tester.ensureVisible(time);
  await tester.pumpAndSettle();
  await tester.tap(time);
  await tester.pumpAndSettle();
  await tester.tap(find.text('확인'));
  await tester.pumpAndSettle();
  expect(find.byType(TimePickerDialog), findsNothing);
}

void main() {
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

  testWidgets(
    'production preview quick add saves the chosen time without accessing SQLite',
    (tester) async {
      final controller = await _preview(tester);
      final before = await controller.repository.tasks();
      expect(before, hasLength(5));
      final now = DateTime.now();
      final chosen = DateTime(now.year, now.month, 16);
      final date = find.byKey(Key('calendar-date-${dayKey(chosen)}'));
      await tester.ensureVisible(date);
      await tester.pumpAndSettle();
      await tester.tap(date);
      await tester.pumpAndSettle();
      expect(find.text('월 보기'), findsOneWidget);
      expect(find.text('주 보기'), findsNothing);
      final timeButton = find.byKey(const Key('quick-add-time'));
      await tester.ensureVisible(timeButton);
      await tester.pumpAndSettle();
      await tester.tap(timeButton);
      await tester.pumpAndSettle();
      final initial = tester
          .widget<TimePickerDialog>(find.byType(TimePickerDialog))
          .initialTime;
      await tester.enterText(find.byType(TextFormField).at(1), '25');
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await _add(tester, '미리보기에서 추가한 새 할 일');
      final stored = await controller.repository.tasks();
      expect(stored, hasLength(before.length + 1));
      final added = stored.singleWhere(
        (task) => task.title == '미리보기에서 추가한 새 할 일',
      );
      expect(dayOf(added.due), chosen);
      expect(added.due.hour, initial.hour);
      expect(added.due.minute, 25);
      expect(controller.items.any((item) => item.task.id == added.id), isTrue);
      expect(find.text('할 일을 등록했어요.'), findsOneWidget);
      expect(find.text('처리하지 못했습니다. 다시 시도해주세요.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'production preview detects seeded and newly saved duplicates, with cancellation and approval',
    (tester) async {
      final controller = await _preview(tester);
      final seeded = await controller.repository.tasks();
      final original = seeded.singleWhere((task) => task.title == '에어컨 필터 청소');
      await _chooseTime(tester);
      await _add(tester, original.title);
      expect(find.text('중복된 내용입니다.'), findsOneWidget);
      expect(await controller.repository.tasks(), hasLength(seeded.length));
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('quick-add-title')))
            .controller!
            .text,
        original.title,
      );
      await _add(tester, original.title);
      await tester.tap(find.text('그래도 등록'));
      await tester.pumpAndSettle();
      var stored = await controller.repository.tasks();
      final matching = stored
          .where((task) => task.title == original.title)
          .toList();
      expect(matching, hasLength(2));
      expect(matching.map((task) => task.id).toSet(), hasLength(2));
      expect(stored, hasLength(seeded.length + 1));
      // The repository must also reflect additions, rather than only seed data.
      await _chooseTime(tester);
      await _add(tester, '방금 저장한 미리보기 일정');
      stored = await controller.repository.tasks();
      expect(stored, hasLength(seeded.length + 2));
      await _chooseTime(tester);
      await _add(tester, '방금 저장한 미리보기 일정');
      expect(find.text('중복된 내용입니다.'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(await controller.repository.tasks(), hasLength(seeded.length + 2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'production preview requires an accepted time before saving a quick-add title',
    (tester) async {
      final controller = await _preview(tester);
      final before = await controller.repository.tasks();
      await _add(tester, '시간 선택 전 미리보기 일정');
      expect(await controller.repository.tasks(), hasLength(before.length));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('quick-add-time-hint')))
            .semanticsLabel,
        '시간을 먼저 선택해주세요.',
      );
      expect(find.text('할 일을 등록했어요.'), findsNothing);
      await _chooseTime(tester);
      await _add(tester, '시간 선택 전 미리보기 일정');
      final stored = await controller.repository.tasks();
      expect(stored, hasLength(before.length + 1));
      expect(
        stored.where((task) => task.title == '시간 선택 전 미리보기 일정'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
