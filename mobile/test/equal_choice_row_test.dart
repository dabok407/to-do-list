import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/features/equal_choice_row.dart';

const _korean = {'생활': '생활', '업무': '업무', '건강': '건강', '배움': '배움', '기타': '기타'};
const _english = {
  '생활': 'Life',
  '업무': 'Work',
  '건강': 'Health',
  '배움': 'Learning',
  '기타': 'Other',
};

Finder _choice(Object key) => find.byKey(ValueKey('option-$key'));

Widget _app({
  required Map<String, String> choices,
  String selected = '생활',
  ValueChanged<String>? onChanged,
  double textScale = 1,
}) => MaterialApp(
  theme: ThemeData(fontFamily: 'Pretendard'),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          // The editor is narrower than the viewport because of both its page
          // margin and the category field's inner content padding.
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
          child: EqualChoiceRow<String>(
            key: const Key('choice-group'),
            choices: choices,
            value: selected,
            optionKeyPrefix: 'option',
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });

  for (final width in [320.0, 375.0, 402.0, 440.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final language in ['ko', 'en']) {
        testWidgets(
          '$language five equal choices fill one row at $width px / ${scale}x',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 900);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final choices = language == 'ko' ? _korean : _english;
            await tester.pumpWidget(
              _app(choices: choices, textScale: scale, onChanged: (_) {}),
            );
            await tester.pumpAndSettle();
            final group = tester.getRect(find.byKey(const Key('choice-group')));
            final rects = choices.keys
                .map((key) => tester.getRect(_choice(key)))
                .toList();
            for (final rect in rects) {
              expect(rect.width, closeTo(rects.first.width, 0.01));
              expect(rect.top, closeTo(rects.first.top, 0.01));
              expect(rect.height, closeTo(rects.first.height, 0.01));
              expect(rect.height, greaterThanOrEqualTo(48));
            }
            expect(rects.first.left, closeTo(group.left, 0.01));
            expect(rects.last.right, closeTo(group.right, 0.01));
            for (final option in choices.entries) {
              final textFinder = find.descendant(
                of: _choice(option.key),
                matching: find.text(option.value),
              );
              final text = tester.widget<Text>(textFinder);
              final paragraph = tester.renderObject<RenderParagraph>(
                textFinder,
              );
              expect(text.data, option.value);
              expect(text.overflow, TextOverflow.visible);
              expect(paragraph.didExceedMaxLines, isFalse);
              final textRect = tester.getRect(textFinder);
              final chipRect = tester.getRect(_choice(option.key));
              expect(textRect.left, greaterThanOrEqualTo(chipRect.left - 0.01));
              expect(textRect.right, lessThanOrEqualTo(chipRect.right + 0.01));
              expect(textRect.top, greaterThanOrEqualTo(chipRect.top - 0.01));
              expect(
                textRect.bottom,
                lessThanOrEqualTo(chipRect.bottom + 0.01),
              );
              if (language == 'ko' && scale == 1) {
                expect(
                  paragraph
                      .getBoxesForSelection(
                        TextSelection(
                          baseOffset: 0,
                          extentOffset: option.value.length,
                        ),
                      )
                      .map((box) => box.top)
                      .toSet(),
                  hasLength(1),
                );
              }
              final materialFinder = find.descendant(
                of: _choice(option.key),
                matching: find.byType(Material),
              );
              expect(materialFinder, findsOneWidget);
              expect(
                tester.getSize(materialFinder).width,
                closeTo(chipRect.width, 0.01),
                reason: 'The painted button fills the equal-width cell.',
              );
            }
            expect(find.byType(FittedBox), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('selection, full-width taps and full-label semantics remain', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var selected = '생활';
      final changes = <String>[];
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _app(
            choices: _korean,
            selected: selected,
            onChanged: (value) {
              changes.add(value);
              setState(() => selected = value);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(_choice('생활')).selected, isTrue);
      final otherRect = tester.getRect(_choice('기타'));
      await tester.tapAt(Offset(otherRect.left + 2, otherRect.center.dy));
      await tester.pumpAndSettle();
      expect(changes, ['기타']);
      expect(tester.widget<ChoiceChip>(_choice('기타')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(_choice('생활')).selected, isFalse);
      expect(
        tester.getSemantics(_choice('기타')),
        isSemantics(
          label: '기타',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: true,
          isSelected: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      await tester.tap(_choice('기타'));
      await tester.pumpAndSettle();
      expect(changes, ['기타', '기타']);
      expect(tester.widget<ChoiceChip>(_choice('기타')).selected, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'disabled choices retain labels and selection without tap action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_app(choices: _korean, selected: '기타'));
        await tester.pumpAndSettle();
        for (final key in _korean.keys) {
          final chip = tester.widget<ChoiceChip>(_choice(key));
          expect(chip.onSelected, isNull);
          expect(chip.selected, key == '기타');
          final data = tester.getSemantics(_choice(key)).getSemanticsData();
          expect(data.label, _korean[key]);
          expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
          expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
        }
        await tester.tap(_choice('생활'));
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(_choice('기타')).selected, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('long legacy custom category follows the five intact choices', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const custom = 'My own category with a long descriptive name 나만의 분류';
    final choices = {..._english, custom: custom};
    await tester.pumpWidget(
      _app(choices: choices, selected: custom, textScale: 2, onChanged: (_) {}),
    );
    await tester.pumpAndSettle();
    final firstRect = tester.getRect(_choice('생활'));
    for (final key in _english.keys) {
      expect(tester.getRect(_choice(key)).top, closeTo(firstRect.top, 0.01));
    }
    final customRect = tester.getRect(_choice(custom));
    final groupRect = tester.getRect(find.byKey(const Key('choice-group')));
    expect(customRect.top, greaterThan(firstRect.bottom));
    expect(customRect.width, closeTo(groupRect.width, 0.01));
    expect(tester.widget<ChoiceChip>(_choice(custom)).selected, isTrue);
    final textFinder = find.descendant(
      of: _choice(custom),
      matching: find.text(custom),
    );
    expect(tester.widget<Text>(textFinder).data, custom);
    expect(
      tester.renderObject<RenderParagraph>(textFinder).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'three priorities use equal full-width shares in the given order',
    (tester) async {
      await tester.pumpWidget(
        _app(
          choices: const {'2': '높음', '1': '보통', '0': '낮음'},
          selected: '1',
          onChanged: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      final rects = [
        '2',
        '1',
        '0',
      ].map((key) => tester.getRect(_choice(key))).toList();
      expect(rects[0].left, lessThan(rects[1].left));
      expect(rects[1].left, lessThan(rects[2].left));
      expect(rects[0].width, closeTo(rects[1].width, 0.01));
      expect(rects[1].width, closeTo(rects[2].width, 0.01));
      expect(tester.widget<ChoiceChip>(_choice('1')).selected, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('no choices renders safely without a row or empty space', (
    tester,
  ) async {
    await tester.pumpWidget(_app(choices: const {}));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNothing);
    expect(tester.getSize(find.byKey(const Key('choice-group'))).height, 0);
    expect(tester.takeException(), isNull);
  });
}
