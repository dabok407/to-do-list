import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:sqflite/sqflite.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Palette fixtures must not access the database');
}

class _Controller extends TaskController {
  _Controller() : super(TaskRepository(_UnusedDatabase()), ReminderScheduler());
  @override
  Future<void> refresh({DateTime? through}) async => notifyListeners();
  @override
  Future<void> reconcile() async => notifyListeners();
}

class _Subscription extends SubscriptionService {
  @override
  Future<void> refresh() async {}
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('${platform.name} adaptive switch renders neutral tracks', (
      tester,
    ) async {
      final controller = _Controller();
      final subscription = _Subscription();
      addTearDown(controller.dispose);
      addTearDown(subscription.dispose);
      await tester.pumpWidget(
        HangeoreumApp(controller: controller, subscription: subscription),
      );
      await tester.pumpAndSettle();
      final theme = Theme.of(tester.element(find.byType(NavigationBar)));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      for (final selected in [true, false]) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundary,
                  child: Switch.adaptive(value: selected, onChanged: (_) {}),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bytes = await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return bytes;
        });
        final expected = selected ? const [41, 44, 41] : const [201, 205, 211];
        var trackPixels = 0;
        for (var i = 0; i < bytes!.lengthInBytes; i += 4) {
          if (bytes.getUint8(i) == expected[0] &&
              bytes.getUint8(i + 1) == expected[1] &&
              bytes.getUint8(i + 2) == expected[2] &&
              bytes.getUint8(i + 3) == 255) {
            trackPixels++;
          }
        }
        expect(
          trackPixels,
          greaterThan(40),
          reason: 'The actual $platform track must be neutral: $selected',
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.only(platform));
  }
}
