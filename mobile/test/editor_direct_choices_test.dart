import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/task_editor.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart'
    show PreviewController, PreviewSubscription;
import 'package:hangeoreum/services/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _captureUpdateUi = bool.fromEnvironment('CAPTURE_UPDATE_UI');

Widget _app(String language, {Task? task, ValueChanged<Task?>? onSaved}) =>
    MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await Navigator.push<Task>(
                context,
                MaterialPageRoute(
                  builder: (_) => TaskEditor(
                    task: task,
                    initialDate: DateTime(2026, 10, 17),
                  ),
                ),
              );
              onSaved?.call(result);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

Finder _category(String key) => find.byKey(Key('editor-category-option-$key'));
Finder _priority(int value) => find.byKey(Key('editor-priority-option-$value'));

Future<void> _tapChoice(WidgetTester tester, Finder choice) async {
  await tester.ensureVisible(choice);
  await tester.pumpAndSettle();
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final language in ['ko', 'en']) {
    final strings = AppStrings(language);

    testWidgets('$language category and priority are direct single choices', (
      tester,
    ) async {
      Task? saved;
      await tester.pumpWidget(_app(language, onSaved: (task) => saved = task));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      for (final category in ['생활', '업무', '건강', '배움', '기타']) {
        final choice = _category(category);
        expect(choice, findsOneWidget);
        expect(
          tester
              .widget<Text>(
                find.descendant(of: choice, matching: find.byType(Text)),
              )
              .data,
          strings.category(category),
        );
      }
      expect(tester.widget<ChoiceChip>(_category('생활')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(_priority(1)).selected, isTrue);
      final priorities = tester.widgetList<ChoiceChip>(
        find.descendant(
          of: find.byKey(const Key('editor-priority')),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(
        priorities.map(
          (choice) => tester
              .widget<Text>(
                find.descendant(
                  of: find.byWidget(choice),
                  matching: find.byType(Text),
                ),
              )
              .data,
        ),
        ['높음', '보통', '낮음'].map(strings.t),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('editor-category')),
          matching: find.byType(DropdownButtonFormField<String>),
        ),
        findsNothing,
      );

      await _tapChoice(tester, _category('기타'));
      await _tapChoice(tester, _category('기타'));
      expect(tester.widget<ChoiceChip>(_category('기타')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(_category('생활')).selected, isFalse);
      await _tapChoice(tester, _priority(2));
      expect(tester.widget<ChoiceChip>(_priority(2)).selected, isTrue);
      expect(tester.widget<ChoiceChip>(_priority(1)).selected, isFalse);
      await _tapChoice(tester, _priority(1));
      expect(tester.widget<ChoiceChip>(_priority(1)).selected, isTrue);
      final title = find.byKey(const Key('editor-title'));
      await tester.ensureVisible(title);
      await tester.enterText(title, 'My task');
      await tester.tap(find.text(strings.t('저장')));
      await tester.pumpAndSettle();
      expect(saved?.category, '기타');
      expect(saved?.priority, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$language a new task saves normal priority by default', (
      tester,
    ) async {
      Task? saved;
      await tester.pumpWidget(_app(language, onSaved: (task) => saved = task));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final title = find.byKey(const Key('editor-title'));
      await tester.ensureVisible(title);
      await tester.enterText(title, 'Default priority');
      await tester.tap(find.text(strings.t('저장')));
      await tester.pumpAndSettle();
      expect(saved?.priority, 1);
      expect(saved?.category, '생활');
      expect(tester.takeException(), isNull);
    });

    for (final existingPriority in [0, 1, 2]) {
      testWidgets(
        '$language edit preserves custom category and priority $existingPriority',
        (tester) async {
          final task = Task(
            id: 'existing-task',
            title: 'Keep my task',
            category: '내 분류',
            priority: existingPriority,
            due: DateTime(2026, 10, 17, 14),
            created: DateTime(2026, 10, 10),
          );
          Task? saved;
          await tester.pumpWidget(
            _app(language, task: task, onSaved: (value) => saved = value),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(tester.widget<ChoiceChip>(_category('내 분류')).selected, isTrue);
          expect(
            tester.widget<ChoiceChip>(_priority(existingPriority)).selected,
            isTrue,
          );
          await tester.tap(find.text(strings.t('저장')));
          await tester.pumpAndSettle();
          expect(saved?.toMap(), task.toMap());
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('$language direct choices fit 320px with 200% text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const longCategory = '내 일정에 사용하는 아주 길고 자세한 분류 이름';
      final task = Task(
        id: 'long-category',
        title: 'Keep my task',
        category: longCategory,
        due: DateTime(2026, 10, 17, 14),
        created: DateTime(2026, 10, 10),
      );
      await tester.pumpWidget(_app(language, task: task));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final longText = tester.widget<Text>(find.text(longCategory));
      expect(longText.overflow, isNot(TextOverflow.ellipsis));
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(longCategory))
            .didExceedMaxLines,
        isFalse,
      );
      final choiceKeys = <String, List<Key>>{
        'editor-category': [
          // Check the original custom choice before switching to built-ins.
          // The form retains a custom option only while it is selected.
          const Key('editor-category-option-$longCategory'),
          for (final category in taskCategories)
            Key('editor-category-option-$category'),
        ],
        'editor-priority': [
          for (final priority in [2, 1, 0])
            Key('editor-priority-option-$priority'),
        ],
      };
      for (final entry in choiceKeys.entries) {
        final key = entry.key;
        final group = find.byKey(Key(key));
        final groupRect = tester.getRect(group);
        for (final choiceKey in entry.value) {
          // Widgets/elements can be replaced while selection rebuilds the
          // form. Resolve a fresh keyed finder for every interaction.
          final finder = find.byKey(choiceKey);
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          final rect = tester.getRect(finder);
          expect(rect.left, greaterThanOrEqualTo(groupRect.left));
          expect(rect.right, lessThanOrEqualTo(groupRect.right));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(finder.hitTestable(), findsOneWidget);
          await tester.tap(finder);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$key $choiceKey');
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('$language capture actual editor update UI', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 932);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            WidgetService.channel,
            (call) async => call.method == 'getCalendarPreferences'
                ? {'regionCode': 'KR', 'firstDayOfWeek': 0}
                : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(WidgetService.channel, null),
      );
      final controller = PreviewController(sampleLanguage: language);
      final subscription = PreviewSubscription();
      addTearDown(controller.dispose);
      addTearDown(subscription.dispose);
      await controller.localeController.setPreference(language);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: HangeoreumApp(
            controller: controller,
            subscription: subscription,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(NavigationBar))).push<Task>(
        MaterialPageRoute(
          builder: (_) => TaskEditor(initialDate: DateTime(2026, 10, 17)),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.byKey(const Key('editor-title'));
      await tester.ensureVisible(title);
      await tester.enterText(
        title,
        language == 'ko' ? '에어컨 필터 청소' : 'Clean the AC filter',
      );
      await tester.pumpAndSettle();
      await _tapChoice(tester, _category('기타'));
      final firstField = tester.element(
        find.byKey(const Key('editor-date-time')),
      );
      // Preserve the form's initial 24px top padding rather than aligning the
      // outlined field itself against the viewport and clipping its label.
      Scrollable.of(firstField).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(_category('기타')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(_priority(1)).selected, isTrue);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final renderer =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await renderer.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/update-ui/editor-$language.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
    }, skip: !_captureUpdateUi);
  }
}
