import 'recurrence.dart';
import 'task.dart';

enum RecurrencePreviewIssue { interval, weekdays, monthlyWeek, weeklyGoal }

/// A view of the existing schedule rules, not a second recurrence engine.
/// Weekly goals list days on which participation is possible; they do not
/// promise a fixed number of scheduled completions or notification deliveries.
class RecurrencePreview {
  final List<DateTime> dates;
  final RecurrencePreviewIssue? issue;
  const RecurrencePreview(this.dates, {this.issue});

  static RecurrencePreview build(Task task, {required DateTime now}) {
    if (task.repeat == RepeatUnit.none) return const RecurrencePreview([]);
    if (task.interval < 1 || task.interval > 365) {
      return const RecurrencePreview(
        [],
        issue: RecurrencePreviewIssue.interval,
      );
    }
    if (task.repeat == RepeatUnit.weekly ||
        task.repeat == RepeatUnit.monthlyWeekday) {
      if (task.weekdays.isEmpty ||
          task.weekdays.any((day) => day < 1 || day > 7) ||
          (task.repeat == RepeatUnit.monthlyWeekday &&
              task.weekdays.length != 1)) {
        return const RecurrencePreview(
          [],
          issue: RecurrencePreviewIssue.weekdays,
        );
      }
    }
    if (task.repeat == RepeatUnit.monthlyWeekday &&
        !const [1, 2, 3, 4, -1].contains(task.monthWeek)) {
      return const RecurrencePreview(
        [],
        issue: RecurrencePreviewIssue.monthlyWeek,
      );
    }
    if (task.repeat == RepeatUnit.weeklyGoal &&
        (task.countPerWeek < 1 || task.countPerWeek > 7)) {
      return const RecurrencePreview(
        [],
        issue: RecurrencePreviewIssue.weeklyGoal,
      );
    }
    final result = <DateTime>[];
    var cursor = now.isAfter(task.due) ? now : task.due;
    while (result.length < 3) {
      final next = RecurrenceCalculator.next(task, cursor);
      if (next == null) break;
      result.add(next);
      // Calendar days, not a 24-hour duration, keep local dates across DST.
      cursor = DateTime(next.year, next.month, next.day + 1);
    }
    return RecurrencePreview(List.unmodifiable(result));
  }
}
