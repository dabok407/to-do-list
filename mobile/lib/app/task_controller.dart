import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/task_repository.dart';
import '../domain/task.dart';
import '../services/reminder_scheduler.dart';
import '../services/widget_service.dart';
import '../services/feature_access.dart';

class TaskController extends ChangeNotifier {
  final TaskRepository repository;
  final ReminderScheduler reminders;
  final WidgetService widgets;
  final FeatureAccess? access;
  List<Occurrence> items = [];
  Map<String, Object> statistics = {};
  String? warning;
  String? pendingOpenId;
  Future<void> _tail = Future.value();
  Timer? _retryTimer;
  TaskController(
    this.repository,
    this.reminders, {
    WidgetService? widgets,
    this.access,
  }) : widgets = widgets ?? WidgetService();
  Future<void> _serial(Future<void> Function() action) {
    final current = _tail.then((_) => action());
    _tail = current.catchError((Object _) {});
    return current;
  }

  Future<void> refresh({DateTime? through}) async {
    await repository.materialize(through: through);
    items = await repository.occurrences();
    statistics = await repository.stats();
    notifyListeners();
  }

  Future<void> reconcile() => _serial(_reconcile);
  Future<void> _reconcile() async {
    await refresh();
    final owner = 'ui${DateTime.now().microsecondsSinceEpoch}';
    var leased = await repository.acquireReminderLease(owner);
    for (var attempt = 0; !leased && attempt < 15; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      leased = await repository.acquireReminderLease(owner);
    }
    try {
      if (leased) {
        _retryTimer?.cancel();
        await refresh();
        await access?.load();
        reminders.accessUntil = access == null
            ? null
            : access!.enabled
            ? access!.until
            : DateTime(1970);
        await reminders.sync(
          items,
          exceptions: await repository.notificationExceptions(),
        );
      }
      if (!leased) {
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 2), () {
          reconcile();
        });
      }
      await widgets.sync(items);
      final enabled = access?.enabled == false
          ? true
          : await reminders.enabled();
      warning = enabled == false
          ? '알림이 꺼져 있어요. 설정에서 알림을 켜면 예정된 시간에 알려드릴 수 있어요.'
          : null;
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('Reminder reconciliation failed: $error\n$stack');
      }
      warning = '일정은 저장했지만 알림을 예약하지 못했습니다. 설정에서 알림 권한을 확인해주세요.';
    } finally {
      if (leased) await repository.releaseReminderLease(owner);
    }
    notifyListeners();
  }

  Future<void> save(Task task) => _serial(() async {
    await repository.saveTask(task);
    try {
      if (access?.enabled != false) await reminders.requestPermissions();
    } catch (_) {
      /* Saving is independent of permission. */
    }
    await _reconcile();
  });

  Future<void> editOccurrence(
    Occurrence original,
    Task task, {
    required bool onlyThis,
  }) => _serial(() async {
    await repository.editOccurrence(original, task, onlyThis: onlyThis);
    await _reconcile();
  });

  Future<void> delete(Task task) => _serial(() async {
    await repository.deleteTask(task.id);
    await _reconcile();
  });

  Future<void> deleteOccurrence(
    Occurrence occurrence, {
    required String scope,
  }) => _serial(() async {
    await repository.deleteOccurrence(occurrence, scope: scope);
    await _reconcile();
  });

  Future<void> act(Occurrence occurrence, String action, {int minutes = 10}) =>
      _serial(() async {
        await access?.load();
        if (access?.allows(action) == false) return;
        await repository.act(occurrence.id, action, minutes: minutes);
        await _reconcile();
      });

  Future<void> handleNotification(String payload, String action) =>
      _serial(() async {
        final occurrence = await repository.resolveNotification(payload);
        if (occurrence == null || !occurrence.active) return;
        await access?.load();
        if (action == 'open' || access?.allows(action) == false) {
          pendingOpenId = occurrence.id;
        } else {
          await repository.act(occurrence.id, action);
        }
        await _reconcile();
      });

  Future<void> handleWidgetLaunch(String uri) => _serial(() async {
    final launch = WidgetService.parseLaunch(uri);
    if (launch == null) return;
    final occurrence = (await repository.occurrences())
        .where((o) => o.id == launch.id)
        .firstOrNull;
    if (occurrence == null) return;
    await access?.load();
    if (launch.action != 'open' &&
        occurrence.active &&
        access?.allows(launch.action) != false) {
      await repository.act(occurrence.id, launch.action);
    }
    pendingOpenId = occurrence.id;
    await _reconcile();
  });

  List<Occurrence> get queue {
    final now = DateTime.now();
    final result = items
        .where(
          (o) =>
              o.active &&
              !(o.task.repeat == RepeatUnit.weeklyGoal &&
                  dayOf(o.originalDue).isBefore(dayOf(now))),
        )
        .toList();
    int rank(Occurrence o) => o.status == TaskStatus.progressing
        ? 0
        : o.reminder.isBefore(now)
        ? 1
        : 2;
    result.sort((a, b) {
      final group = rank(a).compareTo(rank(b));
      if (group != 0) return group;
      if (rank(a) < 2 && a.task.priority != b.task.priority) {
        return b.task.priority.compareTo(a.task.priority);
      }
      final time = a.reminder.compareTo(b.reminder);
      return time == 0 ? b.task.priority.compareTo(a.task.priority) : time;
    });
    return result;
  }

  List<Occurrence> get overdue {
    final now = DateTime.now();
    final result = queue.where((o) => o.originalDue.isBefore(now)).toList();
    result.sort((a, b) {
      final priority = b.task.priority.compareTo(a.task.priority);
      return priority != 0 ? priority : a.originalDue.compareTo(b.originalDue);
    });
    return result;
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}
