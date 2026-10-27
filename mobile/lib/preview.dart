// Browser-only, explicitly labelled sample data. Production starts at main.dart.
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'app/task_controller.dart';
import 'data/task_repository.dart';
import 'domain/task.dart';
import 'domain/recurrence.dart';
import 'domain/statistics_breakdown.dart';
import 'main.dart' show HangeoreumApp;
import 'services/reminder_scheduler.dart';
import 'services/subscription_service.dart';
import 'l10n/app_strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final requested = Uri.base.queryParameters['lang'];
  final controller = PreviewController(sampleLanguage: requested ?? 'ko');
  if (requested == 'ko' || requested == 'en') {
    await controller.localeController.setPreference(requested!);
  } else {
    await controller.localeController.load();
  }
  runApp(
    HangeoreumApp(
      controller: controller,
      subscription: PreviewSubscription(),
      calendarHorizontalInset:
          switch (Uri.base.queryParameters['calendarWidth']) {
            'standard' => 16,
            'wide' => 0,
            _ => 8,
          },
      initialPage: switch (Uri.base.queryParameters['section']) {
        'upcoming' => 1,
        'completed' => 2,
        'statistics' => 3,
        'settings' => 4,
        _ => 0,
      },
    ),
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
    // ProScreen asks for a refresh in initState; notify after its build finishes.
    await Future<void>.value();
    price = 'US\$0.70';
    available = true;
    autoRenewing = active;
    message = AppStrings.current.t('미리보기용 예상 가격입니다. 실제 결제는 발생하지 않아요.');
    notifyListeners();
  }

  @override
  Future<void> purchase() async {
    active = true;
    await refresh();
  }

  @override
  Future<void> restore() async {
    message = AppStrings.current.t('샘플 환경에는 실제 구매 내역이 없습니다.');
    notifyListeners();
  }

  @override
  Future<void> manage() async {
    active = false;
    previewTrial = false;
    message = AppStrings.current.t('미리보기: 무료 상태로 돌아왔어요. 실제 구독은 변경되지 않았어요.');
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
  List<Task> storedTasks = [];
  final Map<String, String> _settings = {};
  _PreviewRepository() : super(_NoDatabase());

  @override
  Future<List<Task>> tasks() async => List.of(storedTasks);

  @override
  Future<String?> setting(String key) async {
    if (_settings.containsKey(key)) return _settings[key];
    if (kIsWeb) {
      return (await SharedPreferences.getInstance()).getString('preview.$key');
    }
    return null;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
    if (kIsWeb) {
      await (await SharedPreferences.getInstance()).setString(
        'preview.$key',
        value,
      );
    }
  }

  @override
  Future<int> todaySnoozes(String id) async =>
      sample.where((o) => o.id == id).firstOrNull?.snoozes ?? 0;
}

class PreviewController extends TaskController {
  @override
  Future<void> setNotificationTitles(bool show) async {
    await repository.setSetting('notification_show_titles', show.toString());
    notifyListeners();
  }

  final List<Task> _tasks = [];
  final Map<String, Occurrence> _states = {};
  final _snoozeEvents = <({String id, DateTime at, int minutes})>[];
  final Set<String> _hidden = {};
  PreviewController({String sampleLanguage = 'ko'})
    : super(_PreviewRepository(), ReminderScheduler()) {
    // Share the preview's live task source, without touching the SQLite stub.
    (repository as _PreviewRepository).storedTasks = _tasks;
    final now = DateTime.now();
    final today = dayOf(now);
    final english = sampleLanguage == 'en';
    final examples = [
      (english ? 'Morning stretch' : '아침 스트레칭', '건강', 8, RepeatUnit.daily),
      (english ? 'Read 10 pages' : '책 10쪽 읽기', '배움', 21, RepeatUnit.daily),
      (
        english ? 'Weekly work review' : '이번 주 업무 정리',
        '업무',
        16,
        RepeatUnit.weekly,
      ),
      (english ? 'Clean the bedroom' : '안방 대청소', '생활', 14, RepeatUnit.none),
      (
        english ? 'Clean the AC filter' : '에어컨 필터 청소',
        '생활',
        12,
        RepeatUnit.none,
      ),
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
          smallStep: english
              ? (i == 3
                    ? 'Put away just 3 things from the floor'
                    : 'Get ready and try for 5 minutes')
              : (i == 3 ? '바닥에 놓인 물건 3개만 제자리에 두기' : '준비하고 5분만 해보기'),
          note: english
              ? (i == 3
                    ? 'You do not have to finish it all at once. Start with the floor.'
                    : 'A small promise to myself')
              : (i == 3 ? '한 번에 전부 하지 않아도 괜찮아요. 바닥부터 차근차근.' : '나를 위한 작은 약속'),
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
    statistics = _periodStatistics(
      now.subtract(const Duration(days: 30)),
      now,
      now,
    );
    (repository as _PreviewRepository).sample = items;
    notifyListeners();
  }

  @override
  Future<Map<String, Object>> statisticsForPeriod(
    DateTime from,
    DateTime until,
  ) async => _periodStatistics(from, until, DateTime.now());

  Map<String, Object> _periodStatistics(
    DateTime from,
    DateTime until,
    DateTime now,
  ) {
    final breakdown = StatisticsBreakdown.fromOccurrences(
      items,
      now: now,
      from: from,
      until: until,
    );
    bool within(DateTime date) =>
        !date.isBefore(from) && !date.isAfter(until) && !date.isAfter(now);
    final itemIds = items.map((item) => item.id).toSet();
    final delays = _snoozeEvents
        .where((event) => itemIds.contains(event.id) && within(event.at))
        .toList();
    final hours = <int, int>{};
    for (final item in items) {
      final completed = item.completed;
      if (item.status != TaskStatus.completed ||
          completed == null ||
          !within(completed)) {
        continue;
      }
      hours.update(completed.toLocal().hour, (n) => n + 1, ifAbsent: () => 1);
    }
    final rankedHours = hours.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount == 0 ? a.key.compareTo(b.key) : byCount;
      });
    return {
      'registered': _tasks.where((t) => !t.derived && within(t.created)).length,
      'total': breakdown.total,
      'completed': breakdown.completed,
      'snoozes': delays.length,
      'average': delays.isEmpty
          ? 0.0
          : delays.fold<int>(0, (sum, event) => sum + event.minutes) /
                delays.length,
      'hour': rankedHours.isEmpty ? '기록 없음' : '${rankedHours.first.key}시',
    };
  }

  @override
  Future<void> reconcile() => refresh();
  @override
  Future<void> setLanguage(String preference) async {
    await localeController.setPreference(preference);
    notifyListeners();
  }

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
  Future<void> snoozeUntil(Occurrence occurrence, DateTime target) async {
    final now = DateTime.now();
    if (!target.isAfter(now)) {
      throw ArgumentError('Reminder is in the past');
    }
    final o = _states[occurrence.id] ?? occurrence;
    if (!o.active) return;
    if (o.status == TaskStatus.paused && o.reminder.isAtSameMomentAs(target)) {
      return;
    }
    _snoozeEvents.add((
      id: o.id,
      at: now,
      minutes: target.difference(now).inMinutes,
    ));
    _states[o.id] = Occurrence(
      id: o.id,
      task: o.task,
      originalDue: o.originalDue,
      reminder: target,
      status: TaskStatus.paused,
      started: o.started,
      snoozes: o.snoozes + 1,
      smallActive: o.smallActive,
    );
    await refresh();
  }

  @override
  Future<void> act(
    Occurrence occurrence,
    String action, {
    int minutes = 10,
  }) async {
    final o = occurrence;
    if (action == 'snooze') {
      _snoozeEvents.add((id: o.id, at: DateTime.now(), minutes: minutes));
    }
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
