import 'task.dart';

enum TaskListOrder { latest, oldest }

enum TaskListSectionKind {
  progressing,
  overdue,
  scheduled,
  completed,
  unknownCompletion,
}

class TaskListSection {
  final String id;
  final DateTime? day;
  final TaskListSectionKind kind;
  final List<Occurrence> items;

  TaskListSection({
    required this.id,
    required this.day,
    required this.kind,
    required Iterable<Occurrence> items,
  }) : items = List.unmodifiable(items);
}

/// Presentation order only. Reminder times and occurrence identity stay intact.
List<TaskListSection> taskListSections(
  Iterable<Occurrence> items, {
  required DateTime now,
  required bool completed,
  TaskListOrder order = TaskListOrder.latest,
}) {
  int clockOrder(DateTime a, DateTime b) =>
      order == TaskListOrder.latest ? b.compareTo(a) : a.compareTo(b);

  int dueOrder(Occurrence a, Occurrence b) {
    final time = clockOrder(a.originalDue, b.originalDue);
    if (time != 0) return time;
    final priority = b.task.priority.compareTo(a.task.priority);
    return priority != 0 ? priority : a.id.compareTo(b.id);
  }

  final groups = <String, List<Occurrence>>{};
  final groupDays = <String, DateTime?>{};
  final groupKinds = <String, TaskListSectionKind>{};
  for (final occurrence in items) {
    if (completed
        ? occurrence.status != TaskStatus.completed
        : !occurrence.active) {
      continue;
    }
    final TaskListSectionKind kind;
    final DateTime? day;
    if (completed) {
      kind = occurrence.completed == null
          ? TaskListSectionKind.unknownCompletion
          : TaskListSectionKind.completed;
      day = occurrence.completed == null
          ? null
          : dayOf(occurrence.completed!.toLocal());
    } else if (occurrence.status == TaskStatus.progressing) {
      kind = TaskListSectionKind.progressing;
      day = null;
    } else {
      kind = occurrence.originalDue.isBefore(now)
          ? TaskListSectionKind.overdue
          : TaskListSectionKind.scheduled;
      day = dayOf(occurrence.originalDue.toLocal());
    }
    final id = '${kind.name}${day == null ? '' : '-${dayKey(day)}'}';
    groups.putIfAbsent(id, () => []).add(occurrence);
    groupDays[id] = day;
    groupKinds[id] = kind;
  }

  final result = groups.entries.map((entry) {
    final sorted = entry.value
      ..sort((a, b) {
        if (completed && a.completed != null && b.completed != null) {
          final time = clockOrder(a.completed!, b.completed!);
          if (time != 0) return time;
        }
        return dueOrder(a, b);
      });
    return TaskListSection(
      id: entry.key,
      day: groupDays[entry.key],
      kind: groupKinds[entry.key]!,
      items: sorted,
    );
  }).toList();
  result.sort((a, b) {
    final kind = a.kind.index.compareTo(b.kind.index);
    if (kind != 0) return kind;
    if (a.day == null || b.day == null) return 0;
    return clockOrder(a.day!, b.day!);
  });
  return result;
}
