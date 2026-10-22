import 'task.dart';

class StatisticsCount {
  final int total, completed;
  const StatisticsCount({required this.total, required this.completed});
  double? get rate => total == 0 ? null : completed / total;
}

/// Mirrors the repository's inclusive statistics window. Without explicit
/// bounds it retains the rolling 30-day default.
/// Scheduled occurrences (including manually skipped ones) form the target;
/// automatically skipped weekly-goal occurrences are excluded from the target.
/// Completed counts follow the repository's separate completion-time query.
class StatisticsBreakdown {
  final DateTime from, until;
  final int total, completed;
  final Map<int, StatisticsCount> priorities;
  final Map<String, int> categoryCompleted;

  const StatisticsBreakdown._({
    required this.from,
    required this.until,
    required this.total,
    required this.completed,
    required this.priorities,
    required this.categoryCompleted,
  });

  factory StatisticsBreakdown.fromOccurrences(
    Iterable<Occurrence> items, {
    required DateTime now,
    DateTime? from,
    DateTime? until,
  }) {
    final start = from ?? now.subtract(const Duration(days: 30));
    final end = until ?? now;
    if (start.isAfter(end)) {
      throw ArgumentError('The statistics start must not follow the end.');
    }
    bool within(DateTime value) =>
        !value.isBefore(start) && !value.isAfter(end) && !value.isAfter(now);
    final targets = <int, int>{2: 0, 1: 0, 0: 0};
    final completions = <int, int>{2: 0, 1: 0, 0: 0};
    final categories = <String, int>{
      for (final name in taskCategories) name: 0,
    };
    var total = 0;
    var completed = 0;
    for (final item in items) {
      final isCompleted =
          item.status == TaskStatus.completed &&
          item.completed != null &&
          within(item.completed!);
      final eligible =
          !item.quotaSkipped && (within(item.originalDue) || isCompleted);
      final priority = targets.containsKey(item.task.priority)
          ? item.task.priority
          : 1;
      if (eligible) {
        targets[priority] = targets[priority]! + 1;
        total++;
      }
      if (isCompleted) {
        completions[priority] = completions[priority]! + 1;
        categories.update(item.task.category, (n) => n + 1, ifAbsent: () => 1);
        completed++;
      }
    }
    return StatisticsBreakdown._(
      from: start,
      until: end,
      total: total,
      completed: completed,
      priorities: Map.unmodifiable({
        for (final priority in targets.keys)
          priority: StatisticsCount(
            total: targets[priority]!,
            completed: completions[priority]!,
          ),
      }),
      categoryCompleted: Map.unmodifiable(categories),
    );
  }
}
