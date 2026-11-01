// Read-only UI audit: actual app widgets, fictional data, no native services.
// flutter test tool/capture_consistency_audit_test.dart --dart-define=CONSISTENCY_CAPTURE=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart';
import 'package:hangeoreum/features/task_completion_checkbox.dart';
import 'package:hangeoreum/services/widget_service.dart';

import 'capture_seed_comparison_test.dart' as baseline;

void main() {
  if (!const bool.fromEnvironment('CONSISTENCY_CAPTURE')) {
    test('Cross-screen UI audit capture requires opt-in', () {}, skip: true);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('capture real tabs and secondary surfaces at iPhone mini size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 1624);
    tester.view.padding = const FakeViewPadding(top: 100, bottom: 68);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = previousShadows);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WidgetService.channel, (call) async {
          return call.method == 'getCalendarPreferences'
              ? {'regionCode': 'KR', 'firstDayOfWeek': 0}
              : null;
        });
    final c = PreviewController(sampleLanguage: 'ko');
    await c.localeController.setPreference('ko');
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
    final now = DateTime.now();
    for (final task in baseline.fixtures) {
      await c.save(
        Task.fromMap({
          ...task.toMap(),
          'due': DateTime(
            now.year,
            now.month,
            now.day + 1,
            task.due.hour,
            task.due.minute,
          ).toIso8601String(),
        }),
      );
    }
    await c.save(
      Task(
        id: 'repeat-audit',
        title: '매일 스트레칭',
        due: DateTime(now.year, now.month, now.day + 1, 9),
        created: now,
        repeat: RepeatUnit.daily,
        end: DateTime(now.year, now.month, now.day + 2),
      ),
    );

    final overdue = Task(
      id: 'audit-overdue',
      title: '정수기 필터 교체',
      due: DateTime(now.year, now.month, now.day - 2, 18),
      created: now,
      category: '생활',
      priority: 2,
    );
    await c.save(overdue);
    await c.act(
      c.items.firstWhere((o) => o.task.id == overdue.id),
      'uncomplete',
    );
    final done = Task(
      id: 'audit-completed',
      title: '이번 주 운동 계획 세우기',
      due: DateTime(now.year, now.month, now.day, 8),
      created: now,
      category: '건강',
      priority: 0,
    );
    await c.save(done);
    await c.act(c.items.firstWhere((o) => o.task.id == done.id), 'complete');
    final subscription = baseline.PaidFixture();
    addTearDown(c.dispose);
    addTearDown(subscription.dispose);
    final boundary = GlobalKey();
    Future<void> mount(int page) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: HangeoreumApp(
            controller: c,
            subscription: subscription,
            initialPage: page,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('../.tools/consistency-fixes-2026-11-01/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    await mount(0);
    await capture('01-calendar');
    await tester.tap(find.byKey(const Key('overdue-banner')));
    await capture('02-remaining-sheet');
    await tester.tap(find.byType(TaskCompletionCheckbox).last);
    await tester.pump(const Duration(milliseconds: 220));
    await capture('12-remaining-held');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
    await capture('13-remaining-removed');
    await tester.tap(find.text('되돌리기').hitTestable());
    await tester.pumpAndSettle();

    await mount(1);
    await capture('03-upcoming');
    final work = c.items.firstWhere((o) => o.task.id == 'seed-work');
    final row = find.byKey(ValueKey('task-row-${work.id}'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await capture('04-task-detail');
    await tester.tap(find.text('완료했어요').hitTestable());
    await tester.pump(const Duration(milliseconds: 200));
    await capture('14-detail-completed');
    await tester.tap(find.text('되돌리기').hitTestable());
    await tester.pumpAndSettle();

    await mount(1);
    await tester.tap(find.byType(FloatingActionButton));
    await capture('05-task-editor');
    await mount(2);
    await capture('06-completed');
    await mount(3);
    await capture('07-statistics-priority');
    await tester.tap(find.byKey(const Key('statistics-tab-category')));
    await capture('08-statistics-category');
    await mount(4);
    await capture('09-settings');
    final notifications = find.byKey(const Key('notification-settings'));
    await tester.ensureVisible(notifications);
    await tester.tap(notifications);
    await capture('10-notification-sheet');
    await mount(4);
    final backups = find.byKey(const Key('backup-settings'));
    await tester.ensureVisible(backups);
    await tester.tap(backups);
    await capture('11-backup');
    await mount(1);
    final repeated = c.items.firstWhere((o) => o.task.id == 'repeat-audit');
    final repeatRow = find.byKey(ValueKey('task-row-${repeated.id}'));
    await Scrollable.ensureVisible(tester.element(repeatRow), alignment: .3);
    await tester.pumpAndSettle();
    await tester.tap(repeatRow);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('수정'));
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이번 일정만'));
    await capture('15-repeat-scope');

    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
    debugDisableShadows = previousShadows;
  });
}
