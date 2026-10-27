import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/task_detail_metadata.dart';
import 'package:hangeoreum/features/task_completion_checkbox.dart';
import 'package:hangeoreum/features/notification_privacy_setting.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paid extends SubscriptionService {
  @override
  bool get hasAccess => true;
  @override
  bool get paidAccess => true;
  @override
  Future<void> refresh() async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStrings.current = const AppStrings('ko');
  });
  for (final lang in ['ko', 'en']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('$lang compact detail date/icon fits mini at $scale', (
        t,
      ) async {
        t.view.physicalSize = const Size(375, 812);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        AppStrings.current = AppStrings(lang);
        final due = DateTime(2027, 10, 27, 23, 59);
        final task = Task(
          id: 'x',
          title: 'task',
          due: due,
          created: due,
          category: '배움',
          priority: 2,
          repeat: RepeatUnit.weekly,
        );
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: TaskDetailMetadata(
                    occurrence: Occurrence(
                      id: 'o',
                      task: task,
                      originalDue: due,
                      reminder: due,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text(AppStrings(lang).time(due)), findsOneWidget);
        expect(find.text(AppStrings(lang).category('배움')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets('completion is independent checkbox and exposes checked state', (
    t,
  ) async {
    var first = false, second = false;
    await t.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, set) => Column(
              children: [
                TaskCompletionCheckbox(
                  completed: first,
                  enabled: true,
                  onToggle: () => set(() => first = !first),
                ),
                TaskCompletionCheckbox(
                  completed: second,
                  enabled: true,
                  onToggle: () => set(() => second = !second),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byType(Checkbox).first);
    await t.pump();
    expect(first, isTrue);
    expect(second, isFalse);
    expect(t.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
    await t.tap(find.byType(Checkbox).first);
    await t.pump();
    expect(first, isFalse);
  });
  testWidgets(
    'notification titles default on, toggle persists across reopening',
    (t) async {
      final c = PreviewController();
      addTearDown(c.dispose);
      Future<void> show() => t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NotificationPrivacySetting(controller: c)),
        ),
      );
      await show();
      await t.pumpAndSettle();
      expect(
        t.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(await c.repository.setting('notification_show_titles'), 'false');
      await t.pumpWidget(const SizedBox());
      await show();
      await t.pumpAndSettle();
      expect(
        t.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
    },
  );
  testWidgets(
    'upcoming empty state opens editor without changing existing data',
    (t) async {
      final c = PreviewController();
      final sub = _Paid();
      addTearDown(c.dispose);
      addTearDown(sub.dispose);
      await c.refresh();
      for (final task in await c.repository.tasks()) {
        await c.deleteOccurrence(
          Occurrence(
            id: '${task.id}@${task.due.toIso8601String()}',
            task: task,
            originalDue: task.due,
            reminder: task.due,
          ),
          scope: 'series',
        );
      }
      await t.pumpWidget(
        HangeoreumApp(controller: c, subscription: sub, initialPage: 1),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('upcoming-empty-state')), findsOneWidget);
      await t.tap(find.text('첫 할 일 추가'));
      await t.pumpAndSettle();
      expect(find.text('할 일 추가'), findsOneWidget);
      expect(c.items, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
}
