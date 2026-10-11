import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/task_editor.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget home, String language) => MaterialApp(
  locale: Locale(language),
  supportedLocales: const [Locale('ko'), Locale('en')],
  localizationsDelegates: const [
    AppStrings.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: ThemeData(fontFamily: 'Pretendard', platform: TargetPlatform.iOS),
  home: home,
);

Task _existing({RepeatUnit repeat = RepeatUnit.weekly}) => Task(
  id: 'editor-existing',
  title: '에어컨 필터 청소',
  note: '필터를 완전히 말리기',
  smallStep: '커버부터 열기',
  category: '내 분류',
  due: DateTime(2026, 10, 16, 12, 25),
  created: DateTime(2026, 10, 1, 9, 30),
  priority: 2,
  repeat: repeat,
  interval: 2,
  weekdays: const [1, 3],
  end: DateTime(2027, 12, 31),
  overdueDays: 3,
  overdueMinute: 13 * 60 + 15,
  groupId: 'original-series',
  derived: true,
);

void _narrowLargeType(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('new-task defaults keep the selected date at midnight and use 9am on other days', () {
    final today = DateTime(2026, 12, 31);
    expect(
      defaultTaskDue(today, now: DateTime(2026, 12, 31, 21, 25)),
      DateTime(2026, 12, 31, 22, 25),
    );
    for (final minute in [0, 30, 59]) {
      expect(
        defaultTaskDue(today, now: DateTime(2026, 12, 31, 23, minute)),
        DateTime(2026, 12, 31, 23, 59),
      );
    }
    expect(
      defaultTaskDue(DateTime(2027, 1, 1), now: DateTime(2026, 12, 31, 23, 59)),
      DateTime(2027, 1, 1, 9),
    );
  });

  for (final language in ['ko', 'en']) {
    for (final editing in [false, true]) {
      testWidgets(
        '$language ${editing ? 'edit' : 'new'} form keeps scheduling first and assistance last',
        (tester) async {
          final task = editing ? _existing() : null;
          await tester.pumpWidget(
            _app(
              TaskEditor(task: task, initialDate: DateTime(2026, 10, 16)),
              language,
            ),
          );
          await tester.pumpAndSettle();
          const order = [
            'editor-category',
            'editor-date',
            'editor-time',
            'editor-title',
            'editor-note',
            'editor-priority',
            'overdue-settings',
            'editor-repeat',
            'editor-small-step',
          ];
          for (var i = 1; i < order.length; i++) {
            final previous = tester.getRect(find.byKey(Key(order[i - 1])));
            final next = tester.getRect(find.byKey(Key(order[i])));
            expect(
              next.top,
              greaterThanOrEqualTo(previous.bottom),
              reason: '${order[i]} must follow ${order[i - 1]}',
            );
          }
          expect(find.text(language == 'ko' ? '날짜' : 'Date'), findsOneWidget);
          expect(find.text(language == 'ko' ? '시간' : 'Time'), findsOneWidget);
          expect(tester.testTextInput.isVisible, isFalse);
          expect(
            find.byKey(const Key('editor-category')).hitTestable(),
            findsOneWidget,
          );
          for (final key in ['editor-date', 'editor-time']) {
            expect(
              tester.getSize(find.byKey(Key(key))).height,
              greaterThanOrEqualTo(48),
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$language editor scheduling controls remain usable at 320px and 200% type',
      (tester) async {
        _narrowLargeType(tester);
        final task = _existing();
        await tester.pumpWidget(
          _app(TaskEditor(task: task, initialDate: task.due), language),
        );
        await tester.pumpAndSettle();
        final cancel = language == 'ko' ? '취소' : 'Cancel';
        for (final key in ['editor-date', 'editor-time']) {
          final button = find.byKey(Key(key));
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(
            key == 'editor-date'
                ? find.byType(DatePickerDialog)
                : find.byType(TimePickerDialog),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: '$key dialog');
          await tester.tap(find.text(cancel));
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(find.byKey(const Key('editor-small-step')));
        await tester.pumpAndSettle();
        expect(
          find.text(language == 'ko' ? '실행 보조' : 'Start assistance'),
          findsOneWidget,
        );
        expect(
          find.text(language == 'ko' ? '저장' : 'Save').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final premium in [true, false]) {
      testWidgets(
        '$language reordered editor preserves all existing data with premium=$premium',
        (tester) async {
          final task = _existing();
          Task? result;
          await tester.pumpWidget(
            _app(
              Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      result = await Navigator.push<Task>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TaskEditor(
                            task: task,
                            initialDate: task.due,
                            premium: premium,
                          ),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
              language,
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const Key('editor-small-step')),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextFormField>(
                  find.byKey(const Key('editor-small-step')),
                )
                .enabled,
            premium,
          );
          await tester.tap(find.text(language == 'ko' ? '저장' : 'Save'));
          await tester.pumpAndSettle();
          expect(result?.toMap(), task.toMap());
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$language invalid new task reveals the title field after scheduling-first entry',
      (tester) async {
        _narrowLargeType(tester);
        await tester.pumpWidget(
          _app(TaskEditor(initialDate: DateTime(2026, 10, 16)), language),
        );
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isFalse);
        await tester.tap(find.text(language == 'ko' ? '저장' : 'Save'));
        await tester.pumpAndSettle();
        expect(
          find.text(language == 'ko' ? '제목을 입력해주세요' : 'Enter a task title'),
          findsOneWidget,
        );
        expect(tester.testTextInput.isVisible, isTrue);
        expect(
          find.byKey(const Key('editor-title')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
