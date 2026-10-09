// Browser-only, explicitly labelled sample data. Production starts at main.dart.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:sqflite/sqflite.dart';

import 'app/task_controller.dart';
import 'data/task_repository.dart';
import 'domain/task.dart';
import 'domain/recurrence.dart';
import 'main.dart' show HangeoreumApp;
import 'services/reminder_scheduler.dart';
import 'services/subscription_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final controller = PreviewController();
  runApp(
    HangeoreumApp(controller: controller, subscription: PreviewSubscription()),
  );
}

class PreviewSubscription extends SubscriptionService {
  bool previewTrial = Uri.base.queryParameters['mode'] != 'free';
  PreviewSubscription() {
    active = Uri.base.queryParameters['pro'] == '1';
  }
  @override
  bool get trialActive => previewTrial && !active;
  @override
  DateTime? get trialEnds =>
      trialActive ? DateTime.now().add(const Duration(days: 7)) : null;
  @override
  bool get hasAccess => active || trialActive;
  @override
  Future<void> refresh() async {
    price = 'US\$0.70';
    available = true;
    autoRenewing = active;
    message = '미리보기용 예상 가격입니다. 실제 결제는 발생하지 않아요.';
    notifyListeners();
  }

  @override
  Future<void> purchase() async {
    active = true;
    await refresh();
  }

  @override
  Future<void> restore() async {
    message = '샘플 환경에는 실제 구매 내역이 없습니다.';
    notifyListeners();
  }

  @override
  Future<void> manage() async {
    active = false;
    previewTrial = false;
    message = '미리보기: 무료 상태로 돌아왔어요. 실제 구독은 변경되지 않았어요.';
    notifyListeners();
  }
}

class _NoDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Preview has no SQLite database');
}

class _PreviewRepository extends TaskRepository {
  List<Occurrence> sample = [];
  _PreviewRepository() : super(_NoDatabase());
  @override
  Future<int> todaySnoozes(String id) async =>
      sample.where((o) => o.id == id).firstOrNull?.snoozes ?? 0;
}

class PreviewController extends TaskController {
  final List<Task> _tasks = [];
  final Map<String, Occurrence> _states = {};
  final Map<String, List<int>> _snoozeMinutes = {};
  final Set<String> _hidden = {};
  PreviewController() : super(_PreviewRepository(), ReminderScheduler()) {
    final now = DateTime.now();
    final today = dayOf(now);
    final examples = [
      ('아침 스트레칭', '건강', 8, RepeatUnit.daily),
      ('책 10쪽 읽기', '배움', 21, RepeatUnit.daily),
      ('이번 주 업무 정리', '업무', 16, RepeatUnit.weekly),
      ('안방 대청소', '생활', 14, RepeatUnit.none),
      ('에어컨 필터 청소', '생활', 12, RepeatUnit.none),
    ];
    for (var i = 0; i < examples.length; i++) {
      final e = examples[i];
      final date = i < 2
          ? DateTime(today.year, today.month, today.day - 25, e.$3)
          : DateTime(
              today.year,
              today.month,
              today.day - (i == 4 ? 1 : 0),
              e.$3,
            );
      _tasks.add(
        Task(
          id: 'sample-$i',
          title: e.$1,
          category: e.$2,
          due: date,
          created: date,
          repeat: e.$4,
          weekdays: [today.weekday],
          priority: i >= 3 ? 2 : 1,
          smallStep: i == 3 ? '바닥에 놓인 물건 3개만 제자리에 두기' : '준비하고 5분만 해보기',
          note: i == 3 ? '한 번에 전부 하지 않아도 괜찮아요. 바닥부터 차근차근.' : '나를 위한 작은 약속',
        ),
      );
    }
    refresh();
  }
  @override
  Future<void> refresh({DateTime? through}) async {
    final now = DateTime.now();
    items = [];
    for (final t in _tasks) {
      for (final due in RecurrenceCalculator.between(
        t,
        t.due,
        through ?? DateTime(now.year, now.month + 3, 0),
      )) {
        final id = '${t.id}@${due.toIso8601String()}';
        if (_hidden.contains(id)) continue;
        final old = _states[id];
        if (old != null) {
          items.add(old);
          continue;
        }
        final past = dayOf(due).isBefore(dayOf(now));
        items.add(
          Occurrence(
            id: id,
            task: t,
            originalDue: due,
            reminder: due,
            status: past && t.id != 'sample-4'
                ? (due.day % 4 == 0 ? TaskStatus.skipped : TaskStatus.completed)
                : TaskStatus.pending,
            completed: past && due.day % 4 != 0 ? due : null,
          ),
        );
      }
    }
    items.sort((a, b) => a.originalDue.compareTo(b.originalDue));
    final done = items.where((o) => o.status == TaskStatus.completed).length;
    statistics = {
      'registered': _tasks.length,
      'total': items.where((o) => !o.originalDue.isAfter(now)).length,
      'completed': done,
      'snoozes': items.fold<int>(0, (n, o) => n + o.snoozes),
      'average':
          items.fold<int>(
            0,
            (sum, o) =>
                sum +
                (_snoozeMinutes[o.id] ?? []).fold<int>(0, (a, b) => a + b),
          ) /
          (items.fold<int>(0, (sum, o) => sum + o.snoozes).clamp(1, 1000000)),
      'hour': '21시',
    };
    (repository as _PreviewRepository).sample = items;
    notifyListeners();
  }

  @override
  Future<void> reconcile() => refresh();
  @override
  Future<void> save(Task task) async {
    _tasks.removeWhere((t) => t.id == task.id);
    _tasks.add(task);
    await refresh();
  }

  @override
  Future<void> editOccurrence(
    Occurrence original,
    Task task, {
    required bool onlyThis,
  }) async {
    if (onlyThis) {
      _hidden.add(original.id);
      await save(
        Task.fromMap({
          ...task.toMap(),
          'id': 'edited-${DateTime.now().microsecondsSinceEpoch}',
          'repeat_unit': 'none',
        }),
      );
    } else {
      final end = dayOf(original.originalDue).subtract(const Duration(days: 1));
      _tasks.removeWhere((t) => t.id == original.task.id);
      _tasks.add(
        Task.fromMap({
          ...original.task.toMap(),
          'end_date': end.toIso8601String(),
        }),
      );
      await save(
        Task.fromMap({
          ...task.toMap(),
          'id': 'edited-${DateTime.now().microsecondsSinceEpoch}',
        }),
      );
    }
  }

  @override
  Future<void> deleteOccurrence(
    Occurrence occurrence, {
    required String scope,
  }) async {
    final o = occurrence;
    if (scope == 'series') {
      _tasks.removeWhere((t) => t.id == o.task.id);
    } else if (scope == 'future') {
      _tasks.removeWhere((t) => t.id == o.task.id);
      _tasks.add(
        Task.fromMap({
          ...o.task.toMap(),
          'end_date': dayOf(o.originalDue)
              .subtract(const Duration(days: 1))
              .toIso8601String(),
        }),
      );
    } else {
      _hidden.add(o.id);
    }
    await refresh();
  }

  @override
  Future<void> act(
    Occurrence occurrence,
    String action, {
    int minutes = 10,
  }) async {
    final o = occurrence;
    if (action == 'snooze') (_snoozeMinutes[o.id] ??= []).add(minutes);
    final state = switch (action) {
      'complete' => TaskStatus.completed,
      'uncomplete' => o.beforeComplete ?? TaskStatus.pending,
      'snooze' => TaskStatus.paused,
      'start' || 'small' => TaskStatus.progressing,
      'skip' => TaskStatus.skipped,
      _ => TaskStatus.pending,
    };
    _states[o.id] = Occurrence(
      id: o.id,
      task: o.task,
      originalDue: o.originalDue,
      reminder: DateTime.now().add(
        Duration(minutes: action == 'small' ? 5 : minutes),
      ),
      status: state,
      completed: state == TaskStatus.completed ? DateTime.now() : null,
      beforeComplete: action == 'complete' ? o.status : null,
      snoozes: o.snoozes + (action == 'snooze' ? 1 : 0),
      smallActive: action == 'small',
    );
    await refresh();
  }
}
