import 'package:flutter/foundation.dart';

import '../data/task_repository.dart';
import '../domain/task.dart';
import '../services/reminder_scheduler.dart';

class TaskController extends ChangeNotifier {
  final TaskRepository repository;
  final ReminderScheduler reminders;
  List<Occurrence> items = [];
  Map<String, Object> statistics = {};
  String? warning;
  TaskController(this.repository, this.reminders);
  Future<void> refresh({DateTime? through}) async {
    await repository.materialize(through: through);
    items = await repository.occurrences();
    statistics = await repository.stats();
    notifyListeners();
  }

  Future<void> reconcile() async {
    await refresh();
    try {
      await reminders.sync(items);
      warning = null;
    } catch (_) {
      warning = '일정은 저장했지만 알림을 예약하지 못했습니다. 설정에서 알림 권한을 확인해주세요.';
    }
    notifyListeners();
  }

  Future<void> save(Task task) async {
    await repository.saveTask(task);
    await reconcile();
  }

  Future<void> delete(Task task) async {
    await repository.deleteTask(task.id);
    await reconcile();
  }

  Future<void> act(
    Occurrence occurrence,
    String action, {
    int minutes = 10,
  }) async {
    await repository.act(occurrence.id, action, minutes: minutes);
    await reconcile();
  }

  List<Occurrence> get queue {
    final now = DateTime.now();
    final result = items.where((o) => o.active).toList();
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
}
