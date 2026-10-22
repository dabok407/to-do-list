import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/features/home_screen.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:sqflite/sqflite.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Calendar width fixtures must not use storage');
}

class _Controller extends TaskController {
  _Controller() : super(TaskRepository(_UnusedDatabase()), ReminderScheduler());

  @override
  Future<void> reconcile() async => notifyListeners();
}

class _Subscription extends SubscriptionService {
  @override
  bool get hasAccess => true;
  @override
  bool get paidAccess => false;
  @override
  bool get trialActive => true;
  @override
  Future<void> refresh() async {}
}

Future<void> _mount(
  WidgetTester tester, {
  required String language,
  required double width,
  required double calendarInset,
  double safeLeft = 0,
  double safeRight = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 812);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = _Controller();
  final subscription = _Subscription();
  addTearDown(controller.dispose);
  addTearDown(subscription.dispose);
  addTearDown(() => AppStrings.current = const AppStrings('ko'));
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      locale: Locale(language),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: EdgeInsets.only(left: safeLeft, right: safeRight),
        ),
        child: child!,
      ),
      home: HomeScreen(
        controller: controller,
        subscription: subscription,
        calendarHorizontalInset: calendarInset,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _dateCells() => find.descendant(
  of: find.byKey(const Key('calendar-grid')),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is InkWell &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('calendar-date-'),
  ),
);

void main() {
  test('production calendar uses the balanced 8px inset by default', () {
    final controller = _Controller();
    addTearDown(controller.dispose);
    expect(HangeoreumApp(controller: controller).calendarHorizontalInset, 8);
    expect(HomeScreen(controller: controller).calendarHorizontalInset, 8);
  });

  for (final language in ['ko', 'en']) {
    for (final width in [320.0, 375.0, 402.0]) {
      for (final calendarInset in [16.0, 8.0, 0.0]) {
        testWidgets(
          '$language ${width.toInt()} ${calendarInset.toInt()}px inset calendar '
          'keeps equal columns and first/last touch targets',
          (tester) async {
            await _mount(
              tester,
              language: language,
              width: width,
              calendarInset: calendarInset,
            );
            final grid = tester.getRect(find.byKey(const Key('calendar-grid')));
            expect(grid.left, closeTo(calendarInset, .01));
            expect(grid.width, closeTo(width - calendarInset * 2, .01));
            final cells = _dateCells();
            final count = cells.evaluate().length;
            expect(count % 7, 0);
            final first = tester.getRect(cells.at(0));
            final last = tester.getRect(cells.at(6));
            expect(first.left, closeTo(grid.left, .01));
            expect(last.right, closeTo(grid.right, .01));
            expect(first.width, closeTo(grid.width / 7, .01));
            expect(last.width, closeTo(first.width, .01));

            // The actual weekday cell participates in hit testing at the edge.
            // Merely painting a wider grid through an overflow widget fails this.
            final firstKey = tester.widget<InkWell>(cells.at(0)).key!;
            await tester.tapAt(Offset(first.left + 1, first.top + 10));
            await tester.pumpAndSettle();
            expect(_dateCells(), findsNWidgets(7));
            final selected = find.ancestor(
              of: find.byKey(firstKey),
              matching: find.byType(Semantics),
            );
            expect(
              tester
                  .widgetList<Semantics>(selected)
                  .any((semantics) => semantics.properties.selected == true),
              isTrue,
            );

            await tester.tap(
              find.text(language == 'ko' ? '월 보기' : 'Month view'),
            );
            await tester.pumpAndSettle();
            final newLast = tester.getRect(_dateCells().at(6));
            final lastKey = tester.widget<InkWell>(_dateCells().at(6)).key!;
            await tester.tapAt(Offset(newLast.right - 1, newLast.top + 10));
            await tester.pumpAndSettle();
            expect(_dateCells(), findsNWidgets(7));
            expect(find.byKey(lastKey), findsOneWidget);
            expect(
              tester.getSize(find.byKey(const Key('calendar-grid'))).width,
              closeTo(grid.width, .01),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('all calendar widths preserve height and non-calendar gutters', (
    tester,
  ) async {
    await _mount(tester, language: 'ko', width: 375, calendarInset: 16);
    final currentGrid = tester.getRect(find.byKey(const Key('calendar-grid')));
    final currentQuick = tester.getRect(
      find.byKey(const Key('quick-add-card')),
    );
    for (final calendarInset in [8.0, 0.0]) {
      await _mount(
        tester,
        language: 'ko',
        width: 375,
        calendarInset: calendarInset,
      );
      final grid = tester.getRect(find.byKey(const Key('calendar-grid')));
      final quick = tester.getRect(find.byKey(const Key('quick-add-card')));
      expect(grid.height, closeTo(currentGrid.height, .01));
      expect(grid.top, closeTo(currentGrid.top, .01));
      expect(quick, currentQuick);
      expect(quick.left, 16);
      expect(quick.right, 359);
      expect(tester.takeException(), isNull);
    }
  });

  for (final calendarInset in [16.0, 8.0, 0.0]) {
    testWidgets(
      '${calendarInset.toInt()}px inset respects horizontal device safe areas',
      (tester) async {
        await _mount(
          tester,
          language: 'en',
          width: 402,
          calendarInset: calendarInset,
          safeLeft: 12,
          safeRight: 18,
        );
        final grid = tester.getRect(find.byKey(const Key('calendar-grid')));
        final quick = tester.getRect(find.byKey(const Key('quick-add-card')));
        expect(grid.left, 12 + calendarInset);
        expect(grid.right, 384 - calendarInset);
        expect(quick.left, 28);
        expect(quick.right, 368);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
