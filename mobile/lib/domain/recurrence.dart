import 'task.dart';

class RecurrenceCalculator {
  static bool matches(Task t, DateTime date) {
    final d = dayOf(date), anchor = dayOf(t.due);
    if (d.isBefore(anchor) || (t.end != null && d.isAfter(dayOf(t.end!)))) {
      return false;
    }
    final days = DateTime.utc(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime.utc(anchor.year, anchor.month, anchor.day)).inDays;
    final interval = t.interval < 1 ? 1 : t.interval;
    switch (t.repeat) {
      case RepeatUnit.none:
        return d == anchor;
      case RepeatUnit.daily:
        return days % interval == 0;
      case RepeatUnit.weekly:
        final monday = anchor.subtract(Duration(days: anchor.weekday - 1));
        final weeks =
            (DateTime.utc(d.year, d.month, d.day)
                        .difference(
                          DateTime.utc(monday.year, monday.month, monday.day),
                        )
                        .inDays /
                    7)
                .floor();
        return weeks % interval == 0 &&
            (t.weekdays.isEmpty ? [anchor.weekday] : t.weekdays).contains(
              d.weekday,
            );
      case RepeatUnit.monthly:
        final months = (d.year - anchor.year) * 12 + d.month - anchor.month;
        final last = DateTime(d.year, d.month + 1, 0).day;
        return months % interval == 0 &&
            d.day == (anchor.day > last ? last : anchor.day);
      case RepeatUnit.monthlyWeekday:
        final months = (d.year - anchor.year) * 12 + d.month - anchor.month;
        final weekday = t.weekdays.isEmpty ? anchor.weekday : t.weekdays.first;
        return months % interval == 0 &&
            d.weekday == weekday &&
            (t.monthWeek == -1
                ? d.add(const Duration(days: 7)).month != d.month
                : ((d.day - 1) ~/ 7 + 1) == t.monthWeek);
    }
  }

  static Iterable<DateTime> between(Task t, DateTime from, DateTime to) sync* {
    for (
      var d = dayOf(from);
      !d.isAfter(dayOf(to));
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      if (matches(t, d)) {
        yield DateTime(d.year, d.month, d.day, t.due.hour, t.due.minute);
      }
    }
  }
}
