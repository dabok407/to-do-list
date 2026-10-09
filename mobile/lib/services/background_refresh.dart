import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/task_repository.dart';
import 'reminder_scheduler.dart';
import 'widget_service.dart';
import 'feature_access.dart';

const refreshTask = 'com.dabok407.hangeoreum.refresh';

@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return BackgroundRefresh.run();
  });
}

class BackgroundRefresh {
  static Future<void> register() async {
    await Workmanager().initialize(backgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      refreshTask,
      refreshTask,
      frequency: const Duration(hours: 6),
      initialDelay: const Duration(hours: 6),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.notRequired),
    );
  }

  /// Shared by OS headless callbacks and native integration verification.
  static Future<bool> run() async {
    TaskRepository? repository;
    final owner = 'bg${DateTime.now().microsecondsSinceEpoch}';
    var leased = false;
    try {
      repository = await TaskRepository.open();
      leased = await repository.acquireReminderLease(owner);
      if (!leased) return true;
      await repository.materialize();
      final items = await repository.occurrences();
      final reminders = ReminderScheduler();
      await reminders.initialize();
      final access = FeatureAccess(repository);
      await access.load();
      reminders.accessUntil = access.enabled ? access.until : DateTime(1970);
      await reminders.sync(
        items,
        exceptions: await repository.notificationExceptions(),
      );
      await WidgetService().sync(items);
      await repository.setSetting(
        'last_background_refresh',
        DateTime.now().toIso8601String(),
      );
      return true;
    } catch (_) {
      return false; // Android retries; iOS chooses its next permitted refresh.
    } finally {
      if (repository != null) {
        if (leased) await repository.releaseReminderLease(owner);
        await repository.db.close();
      }
    }
  }
}
