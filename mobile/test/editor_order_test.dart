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

Task _existing({RepeatUnit repeat = RepeatUnit.weekly, int interval = 2}) =>
    Task(
      id: 'editor-existing',
      title: '에어컨 필터 청소',
      note: '필터를 완전히 말리기',
      smallStep: '커버부터 열기',
      category: '내 분류',
      due: DateTime(2026, 10, 16, 12, 25),
      created: DateTime(2026, 10, 1, 9, 30),
      priority: 2,
      repeat: repeat,
      interval: interval,
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

Finder _panelHeader(String key) => find
    .descendant(of: find.byKey(Key(key)), matching: find.byType(InkWell))
    .first;

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
            'editor-date-time',
            'editor-category',
            'editor-priority',
            'editor-title',
            'editor-note',
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
          expect(
            find.text(language == 'ko' ? '날짜/시간' : 'Date/time'),
            findsOneWidget,
          );
          final date = tester.getRect(find.byKey(const Key('editor-date')));
          final time = tester.getRect(find.byKey(const Key('editor-time')));
          expect(date.center.dy, time.center.dy);
          expect(date.right, lessThan(time.left));
          expect(date.width, greaterThan(time.width));
          expect(tester.testTextInput.isVisible, isFalse);
          expect(
            find.byKey(const Key('editor-date')).hitTestable(),
            findsOneWidget,
          );
          for (final key in ['editor-date', 'editor-time']) {
            expect(
              tester.getSize(find.byKey(Key(key))).height,
              greaterThanOrEqualTo(48),
            );
          }
          for (final decorator in tester.widgetList<InputDecorator>(
            find.byType(InputDecorator),
          )) {
            expect(decorator.decoration.border, isA<OutlineInputBorder>());
            expect(
              decorator.decoration.floatingLabelBehavior,
              FloatingLabelBehavior.always,
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
        final semantics = tester.ensureSemantics();
        try {
          final task = _existing();
          await tester.pumpWidget(
            _app(TaskEditor(task: task, initialDate: task.due), language),
          );
          await tester.pumpAndSettle();
          final date = tester.getRect(find.byKey(const Key('editor-date')));
          final time = tester.getRect(find.byKey(const Key('editor-time')));
          expect(date.center.dy, time.center.dy);
          expect(date.right, lessThan(time.left));
          final strings = AppStrings(language);
          expect(
            tester.getSemantics(find.byKey(const Key('editor-date'))),
            matchesSemantics(
              label: '${strings.t('날짜')}, ${strings.date(task.due)}',
              isButton: true,
              hasTapAction: true,
            ),
          );
          expect(
            tester.getSemantics(find.byKey(const Key('editor-time'))),
            matchesSemantics(
              label: '${strings.t('시간')}, ${strings.time(task.due)}',
              isButton: true,
              hasTapAction: true,
            ),
          );
          for (final value in [
            strings.date(task.due),
            strings.time(task.due),
          ]) {
            final text = tester.widget<Text>(
              find.descendant(
                of: find.byKey(const Key('editor-date-time')),
                matching: find.text(value),
              ),
            );
            expect(text.maxLines, isNull, reason: '큰 글씨에서도 전체 값을 줄바꿈해 표시');
            expect(text.overflow, isNot(TextOverflow.ellipsis));
          }
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
          await tester.ensureVisible(
            find.byKey(const Key('editor-small-step')),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              language == 'ko' ? '작게 시작하기 (선택)' : 'Start small (optional)',
            ),
            findsOneWidget,
          );
          expect(
            find.text(language == 'ko' ? '저장' : 'Save').hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
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
          final interval = find.byKey(const Key('editor-interval'));
          expect(interval, findsOneWidget);
          expect(tester.widget<TextFormField>(interval).controller!.text, '2');
          await tester.tap(find.text(language == 'ko' ? '저장' : 'Save'));
          await tester.pumpAndSettle();
          expect(result?.toMap(), task.toMap());
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$language optional interval preserves collapsed edits and reveals invalid input',
      (tester) async {
        final task = _existing(interval: 1);
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
                        builder: (_) =>
                            TaskEditor(task: task, initialDate: task.due),
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
        final header = _panelHeader('editor-interval-settings');
        final input = find.byKey(const Key('editor-interval'));
        expect(input, findsNothing, reason: '기본 간격 숫자 입력은 접어 둠');
        await tester.ensureVisible(header);
        await tester.tap(header);
        await tester.pumpAndSettle();
        await tester.enterText(input, '');
        await tester.ensureVisible(header);
        await tester.tap(header);
        await tester.pumpAndSettle();
        expect(input, findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('editor-interval-settings')),
            matching: find.text(
              language == 'ko'
                  ? '1~365를 입력해주세요'
                  : 'Enter a number from 1 to 365',
            ),
          ),
          findsOneWidget,
          reason: '빈 간격이 정상 기본값처럼 보이지 않음',
        );
        await tester.ensureVisible(find.byKey(const Key('editor-small-step')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(language == 'ko' ? '저장' : 'Save'));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(input.hitTestable(), findsOneWidget);
        expect(
          tester
              .widget<EditableText>(
                find.descendant(of: input, matching: find.byType(EditableText)),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        await tester.enterText(input, '2');
        await tester.ensureVisible(header);
        await tester.tap(header);
        await tester.pumpAndSettle();
        expect(input, findsNothing);
        expect(
          find.text(language == 'ko' ? '2주마다' : 'Every 2 weeks'),
          findsOneWidget,
        );
        await tester.tap(find.text(language == 'ko' ? '저장' : 'Save'));
        await tester.pumpAndSettle();
        expect(result?.interval, 2);
        expect(result?.end, task.end);
        expect(result?.weekdays, task.weekdays);
        expect(result?.smallStep, task.smallStep);
        expect(result?.overdueMinute, task.overdueMinute);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$language pattern switching preserves multiple weekly days and expanded settings',
      (tester) async {
        final task = _existing();
        await tester.pumpWidget(
          _app(TaskEditor(task: task, initialDate: task.due), language),
        );
        await tester.pumpAndSettle();
        final repeat = find.byKey(const Key('editor-repeat'));
        final monthly = language == 'ko' ? '매월 특정 번째 요일' : 'Monthly · weekday';
        final weekly = language == 'ko' ? '매주 · 요일 선택' : 'Weekly · choose days';
        for (final value in [monthly, weekly]) {
          await tester.ensureVisible(repeat);
          await tester.tap(repeat);
          await tester.pumpAndSettle();
          await tester.tap(find.text(value).last);
          await tester.pumpAndSettle();
        }
        final strings = AppStrings(language);
        for (final day in [1, 3]) {
          expect(
            tester
                .widget<FilterChip>(
                  find.widgetWithText(FilterChip, strings.weekday(day)),
                )
                .selected,
            isTrue,
            reason: '월간 패턴을 둘러봐도 주간의 여러 요일이 유지됨',
          );
        }
        final overdue = _panelHeader('overdue-settings');
        await tester.ensureVisible(overdue);
        await tester.tap(overdue);
        await tester.pumpAndSettle();
        final helper = find.textContaining(
          language == 'ko' ? '기한이 지난 뒤 3일 후부터' : 'Reminders start 3 days after',
        );
        await tester.ensureVisible(helper);
        await tester.tap(helper);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('overdue-interval')),
          findsOneWidget,
          reason: '펼친 설정의 안내나 여백을 눌러도 패널이 접히지 않음',
        );
        expect(tester.takeException(), isNull);
      },
    );

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
