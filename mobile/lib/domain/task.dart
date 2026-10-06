import 'dart:convert';

enum TaskStatus { pending, progressing, paused, completed, skipped }

enum RepeatUnit { none, daily, weekly, monthly, monthlyWeekday }

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Task {
  final String id, title, note, smallStep;
  final int priority, interval, monthWeek;
  final DateTime due, created;
  final DateTime? end;
  final RepeatUnit repeat;
  final List<int> weekdays;
  const Task({
    required this.id,
    required this.title,
    required this.due,
    required this.created,
    this.note = '',
    this.smallStep = '',
    this.priority = 1,
    this.repeat = RepeatUnit.none,
    this.interval = 1,
    this.weekdays = const [],
    this.end,
    this.monthWeek = 1,
  });
  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'note': note,
    'small_step': smallStep,
    'priority': priority,
    'due': due.toIso8601String(),
    'created': created.toIso8601String(),
    'repeat_unit': repeat.name,
    'repeat_interval': interval,
    'weekdays': jsonEncode(weekdays),
    'end_date': end?.toIso8601String(),
    'month_week': monthWeek,
  };
  factory Task.fromMap(Map<String, Object?> m) => Task(
    id: m['id'] as String,
    title: m['title'] as String,
    note: m['note'] as String,
    smallStep: m['small_step'] as String,
    priority: m['priority'] as int,
    due: DateTime.parse(m['due'] as String),
    created: DateTime.parse(m['created'] as String),
    repeat: RepeatUnit.values.byName(m['repeat_unit'] as String),
    interval: m['repeat_interval'] as int,
    weekdays: (jsonDecode(m['weekdays'] as String) as List).cast<int>(),
    end: m['end_date'] == null ? null : DateTime.parse(m['end_date'] as String),
    monthWeek: m['month_week'] as int,
  );
}

class Occurrence {
  final String id;
  final Task task;
  final DateTime originalDue, reminder;
  final TaskStatus status;
  final DateTime? started, completed;
  final int snoozes;
  final bool smallActive;
  final TaskStatus? beforeComplete;
  const Occurrence({
    required this.id,
    required this.task,
    required this.originalDue,
    required this.reminder,
    this.status = TaskStatus.pending,
    this.started,
    this.completed,
    this.snoozes = 0,
    this.smallActive = false,
    this.beforeComplete,
  });
  bool get active =>
      status != TaskStatus.completed && status != TaskStatus.skipped;
  factory Occurrence.fromMap(Map<String, Object?> m, Task task) => Occurrence(
    id: m['id'] as String,
    task: task,
    originalDue: DateTime.parse(m['original_due'] as String),
    reminder: DateTime.parse(m['reminder'] as String),
    status: TaskStatus.values.byName(m['state'] as String),
    started: m['started'] == null
        ? null
        : DateTime.parse(m['started'] as String),
    completed: m['completed'] == null
        ? null
        : DateTime.parse(m['completed'] as String),
    snoozes: m['snoozes'] as int,
    smallActive: m['small_active'] == 1,
    beforeComplete: m['before_complete'] == null
        ? null
        : TaskStatus.values.byName(m['before_complete'] as String),
  );
}
