import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/popup_theme.dart';
import 'package:hangeoreum/features/task_editor.dart';
import 'package:hangeoreum/l10n/app_strings.dart';

Future<CupertinoDatePicker> _openTime(
  WidgetTester tester,
  String key, {
  required bool use24h,
  required String language,
}) async {
  final entry = find.byKey(Key(key));
  await tester.ensureVisible(entry);
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await tester.pumpAndSettle();
  final finder = find.byKey(const Key('time-wheel-picker'));
  expect(finder, findsOneWidget);
  expect(find.byType(TimePickerDialog), findsNothing);
  expect(find.byType(CupertinoPicker), findsNWidgets(use24h ? 2 : 3));
  expect(find.text(language == 'ko' ? '시간 선택' : 'Choose time'), findsOneWidget);
  final picker = tester.widget<CupertinoDatePicker>(finder);
  expect(picker.use24hFormat, use24h);
  return picker;
}

void _select(CupertinoDatePicker picker, int hour, int minute) {
  // Real wheel scrolling and settling are covered by the shared picker tests.
  // This route test verifies where the wheel's returned value is committed.
  final initial = picker.initialDateTime;
  picker.onDateTimeChanged(
    DateTime(initial.year, initial.month, initial.day, hour, minute),
  );
}

Future<void> _dismiss(
  WidgetTester tester,
  String language, {
  required bool confirm,
}) async {
  await tester.tap(
    confirm
        ? find.byKey(const Key('picker-confirm'))
        : find.byTooltip(language == 'ko' ? '취소' : 'Cancel'),
  );
  await tester.pumpAndSettle();
  expect(find.byType(CupertinoDatePicker), findsNothing);
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });

  for (final language in ['ko', 'en']) {
    for (final use24h in [false, true]) {
      for (final editing in [false, true]) {
        testWidgets(
          '$language ${use24h ? 24 : 12}h ${editing ? 'edit' : 'new'} '
          'commits due and custom reminder wheels independently',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(375, 812);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            final date = DateTime(2027, 1, 16);
            final original = editing
                ? Task(
                    id: 'wheel-editor',
                    title: '에어컨 필터 청소',
                    note: '메모 유지',
                    due: DateTime(2027, 1, 16, 23, 45),
                    created: DateTime(2026, 11, 9),
                    overdueMinute: 13 * 60 + 15,
                  )
                : null;
            Task? result;
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(language),
                supportedLocales: const [Locale('ko'), Locale('en')],
                localizationsDelegates: const [
                  AppStrings.delegate,
                  ...GlobalMaterialLocalizations.delegates,
                ],
                theme: ThemeData(
                  platform: TargetPlatform.iOS,
                  fontFamily: 'Pretendard',
                  bottomSheetTheme: TodoniqPopupTheme.bottomSheet,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(alwaysUse24HourFormat: use24h),
                  child: child!,
                ),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () async {
                        result = await Navigator.of(context).push<Task>(
                          MaterialPageRoute(
                            builder: (_) =>
                                TaskEditor(task: original, initialDate: date),
                          ),
                        );
                      },
                      child: const Text('Open editor'),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open editor'));
            await tester.pumpAndSettle();

            var picker = await _openTime(
              tester,
              'editor-time',
              use24h: use24h,
              language: language,
            );
            final originalTime = TimeOfDay.fromDateTime(picker.initialDateTime);
            _select(picker, 21, 58);
            await _dismiss(tester, language, confirm: false);
            picker = await _openTime(
              tester,
              'editor-time',
              use24h: use24h,
              language: language,
            );
            expect(
              TimeOfDay.fromDateTime(picker.initialDateTime),
              originalTime,
              reason: '취소한 예정 시각은 편집 초안에 적용하지 않음',
            );
            _select(picker, 0, 15);
            await _dismiss(tester, language, confirm: true);

            final overdueHeader = find
                .descendant(
                  of: find.byKey(const Key('overdue-settings')),
                  matching: find.byType(InkWell),
                )
                .first;
            await tester.ensureVisible(overdueHeader);
            await tester.pumpAndSettle();
            await tester.tap(overdueHeader);
            await tester.pumpAndSettle();
            if (!editing) {
              final sameTime = find.descendant(
                of: find.byKey(const Key('overdue-settings')),
                matching: find.byType(SwitchListTile),
              );
              expect(tester.widget<SwitchListTile>(sameTime).value, isTrue);
              await tester.ensureVisible(sameTime);
              await tester.pumpAndSettle();
              await tester.tap(sameTime);
              await tester.pumpAndSettle();
            }
            final initialReminder = editing
                ? const TimeOfDay(hour: 13, minute: 15)
                : const TimeOfDay(hour: 0, minute: 15);
            picker = await _openTime(
              tester,
              'overdue-time',
              use24h: use24h,
              language: language,
            );
            expect(
              TimeOfDay.fromDateTime(picker.initialDateTime),
              initialReminder,
              reason: '기존 재알림 시각 유지, 새 사용자 시각은 예정 시각으로 시작',
            );
            _select(picker, 17, 40);
            await _dismiss(tester, language, confirm: false);
            picker = await _openTime(
              tester,
              'overdue-time',
              use24h: use24h,
              language: language,
            );
            expect(
              TimeOfDay.fromDateTime(picker.initialDateTime),
              initialReminder,
              reason: '취소한 재알림 시각은 편집 초안에 적용하지 않음',
            );
            _select(picker, 6, 35);
            await _dismiss(tester, language, confirm: true);

            if (!editing) {
              final title = find.byKey(const Key('editor-title'));
              await tester.ensureVisible(title);
              await tester.enterText(title, '새 일정 휠 검증');
              await tester.testTextInput.receiveAction(TextInputAction.done);
              await tester.pumpAndSettle();
            }
            expect(result, isNull, reason: '휠 확인은 폼 전체 저장과 분리됨');
            await tester.tap(find.text(language == 'ko' ? '저장' : 'Save'));
            await tester.pumpAndSettle();
            expect(result, isNotNull);
            expect(result!.due, DateTime(2027, 1, 16, 0, 15));
            expect(result!.overdueMinute, 6 * 60 + 35);
            expect(result!.overdueDays, 1);
            if (original != null) {
              expect(result!.id, original.id);
              expect(result!.note, original.note);
              expect(result!.created, original.created);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
