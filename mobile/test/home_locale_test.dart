import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:sqflite/sqflite.dart';

class _NoDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Home fixtures must not use platform storage');
}

class _Repository extends TaskRepository {
  final preferences = <String, String>{};
  _Repository() : super(_NoDatabase());
  @override
  Future<String?> setting(String key) async => preferences[key];
  @override
  Future<void> setSetting(String key, String value) async {
    preferences[key] = value;
  }

  @override
  Future<int> todaySnoozes(String id) async => 3;
}

class _Subscription extends SubscriptionService {
  final bool premium;
  _Subscription(this.premium);
  @override
  bool get hasAccess => premium;
  @override
  bool get paidAccess => premium;
  @override
  Future<void> refresh() async {}
}

class _Controller extends TaskController {
  final actions = <String>[];
  Task? saved;
  _Controller() : super(_Repository(), ReminderScheduler()) {
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day, 19);
    final task = Task(
      id: 'english-layout',
      title: '에어컨 필터 청소 · A long user-written task title',
      note: '사용자가 작성한 메모는 번역하지 않아요.',
      due: due,
      created: now,
      category: '배움',
      priority: 2,
      repeat: RepeatUnit.weeklyGoal,
      countPerWeek: 2,
      smallStep: '필터 덮개 열기',
    );
    final old = due.subtract(const Duration(days: 2));
    final overdueTask = Task(
      id: 'overdue-layout',
      title: task.title,
      note: task.note,
      due: old,
      created: old,
      category: task.category,
      smallStep: task.smallStep,
    );
    items = [
      Occurrence(id: 'current', task: task, originalDue: due, reminder: due),
      Occurrence(
        id: 'overdue',
        task: overdueTask,
        originalDue: old,
        reminder: old,
      ),
    ];
    statistics = {
      'registered': 10,
      'total': 12,
      'completed': 8,
      'snoozes': 5,
      'average': 30,
      'hour': '19시',
    };
  }
  @override
  Future<void> refresh({DateTime? through}) async => notifyListeners();
  @override
  Future<void> reconcile() async => notifyListeners();
  @override
  Future<void> setLanguage(String value) async {
    await localeController.setPreference(value);
    notifyListeners();
  }

  @override
  Future<void> save(Task task) async {
    saved = task;
    notifyListeners();
  }

  @override
  Future<void> act(
    Occurrence occurrence,
    String action, {
    int minutes = 10,
  }) async {
    actions.add(action);
    items = items
        .map(
          (o) => o.id != occurrence.id
              ? o
              : Occurrence(
                  id: o.id,
                  task: o.task,
                  originalDue: o.originalDue,
                  reminder: o.reminder,
                  status: action == 'complete'
                      ? TaskStatus.completed
                      : TaskStatus.pending,
                ),
        )
        .toList();
    notifyListeners();
  }
}

Finder _nav(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void _phone(WidgetTester tester, double scale) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(() => AppStrings.current = const AppStrings('ko'));
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });

  testWidgets(
    'English calendar month and year stay readable at 320px and 1.5x',
    (tester) async {
      _phone(tester, 1.5);
      final c = _Controller();
      final subscription = _Subscription(true);
      addTearDown(c.dispose);
      addTearDown(subscription.dispose);
      await c.localeController.setPreference('en');
      await tester.pumpWidget(
        HangeoreumApp(controller: c, subscription: subscription),
      );
      await tester.pumpAndSettle();
      for (var month = 0; month < 12; month++) {
        final heading = find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(Text),
        );
        final paragraph = tester.renderObject<RenderParagraph>(heading);
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'Month and year must not truncate',
        );
        expect(paragraph.size.height, lessThanOrEqualTo(kToolbarHeight));
        await tester.tap(find.byTooltip('Next'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final scale in [1.0, 1.5]) {
    for (final premium in [false, true]) {
      testWidgets('English home fits 320px at ${scale}x, Pro=$premium', (
        tester,
      ) async {
        _phone(tester, scale);
        final c = _Controller();
        final subscription = _Subscription(premium);
        await c.localeController.setPreference('en');
        addTearDown(c.dispose);
        addTearDown(subscription.dispose);
        await tester.pumpWidget(
          HangeoreumApp(controller: c, subscription: subscription),
        );
        await tester.pumpAndSettle();
        expect(_nav('Calendar'), findsOneWidget);
        expect(find.text('Mon'), findsOneWidget);
        expect(
          find.byKey(const Key('overdue-banner')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Week view'));
        await tester.pumpAndSettle();
        expect(find.text('Learning'), findsOneWidget);
        expect(find.text('Month view'), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final page in ['Upcoming', 'Done', 'Insights', 'Settings']) {
          await tester.tap(_nav(page));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: page);
        }
        expect(find.byKey(const Key('language-setting')), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('language-setting')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('language-setting')));
        await tester.pumpAndSettle();
        expect(find.text('Device language').last.hitTestable(), findsOneWidget);
        expect(find.text('한국어').last.hitTestable(), findsOneWidget);
        expect(find.text('English').last.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Language menu');
        await tester.tap(find.text('English').last);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
    'Language setting changes existing components and keeps user content',
    (tester) async {
      _phone(tester, 1.0);
      final c = _Controller();
      final subscription = _Subscription(true);
      addTearDown(c.dispose);
      addTearDown(subscription.dispose);
      await c.localeController.setPreference('ko');
      await tester.pumpWidget(
        HangeoreumApp(controller: c, subscription: subscription),
      );
      await tester.pumpAndSettle();
      await tester.tap(_nav('설정'));
      await tester.pumpAndSettle();
      final language = find.byKey(const Key('language-setting'));
      await tester.ensureVisible(language);
      await tester.pumpAndSettle();
      await tester.tap(language);
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      expect(_nav('Settings'), findsOneWidget);
      expect(c.localeController.preference, 'en');
      expect(
        (c.repository as _Repository).preferences['display_language'],
        'en',
      );
      await tester.tap(_nav('Upcoming'));
      await tester.pumpAndSettle();
      expect(find.text(c.items.first.task.title), findsWidgets);
      expect(c.items.first.task.category, '배움');
      await tester.tap(find.byTooltip('Mark complete').first);
      await tester.pumpAndSettle();
      await tester.tap(_nav('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mark incomplete').first);
      await tester.pumpAndSettle();
      expect(c.actions, ['complete', 'uncomplete']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'English task detail includes snooze and small start at large type',
    (tester) async {
      _phone(tester, 1.5);
      final c = _Controller();
      final subscription = _Subscription(true);
      addTearDown(c.dispose);
      addTearDown(subscription.dispose);
      await c.localeController.setPreference('en');
      await tester.pumpWidget(
        HangeoreumApp(controller: c, subscription: subscription),
      );
      await tester.pumpAndSettle();
      await tester.tap(_nav('Upcoming'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ListTile, c.items.first.task.title).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Start now'), findsOneWidget);
      expect(find.text('In 10 minutes'), findsOneWidget);
      expect(find.textContaining('You’ve snoozed 3 times'), findsOneWidget);
      expect(find.text(c.items.first.task.note), findsOneWidget);
      final skip = find.text('Not today · Skip this task');
      await tester.ensureVisible(skip);
      await tester.pumpAndSettle();
      expect(skip.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
