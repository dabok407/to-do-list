import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/recurrence_preview.dart';
import 'package:hangeoreum/domain/task.dart';

Task _task({
  required DateTime due,
  RepeatUnit repeat = RepeatUnit.weekly,
  int interval = 1,
  List<int> weekdays = const [5],
  DateTime? end,
  int monthWeek = 1,
  int countPerWeek = 1,
}) => Task(
  id: 'preview-test',
  title: '일정',
  due: due,
  created: due,
  repeat: repeat,
  interval: interval,
  weekdays: weekdays,
  end: end,
  monthWeek: monthWeek,
  countPerWeek: countPerWeek,
);

void main() {
  test('approved biweekly Friday preview preserves the time and interval', () {
    final task = _task(due: DateTime(2026, 10, 30, 12), interval: 2);
    expect(RecurrencePreview.build(task, now: DateTime(2026, 10, 26)).dates, [
      DateTime(2026, 10, 30, 12),
      DateTime(2026, 11, 13, 12),
      DateTime(2026, 11, 27, 12),
    ]);
  });

  test(
    'past first due date moves to future pattern, not stale first dates',
    () {
      final task = _task(due: DateTime(2026, 10, 30, 12), interval: 2);
      expect(
        RecurrencePreview.build(task, now: DateTime(2026, 11, 13, 12, 1)).dates,
        [
          DateTime(2026, 11, 27, 12),
          DateTime(2026, 12, 11, 12),
          DateTime(2026, 12, 25, 12),
        ],
      );
    },
  );

  test('monthly last-day adjustment handles leap and ordinary February', () {
    for (final year in [2027, 2028]) {
      final task = _task(
        due: DateTime(year, 1, 31, 9, 15),
        repeat: RepeatUnit.monthly,
      );
      expect(RecurrencePreview.build(task, now: DateTime(year, 1)).dates, [
        DateTime(year, 1, 31, 9, 15),
        DateTime(year, 2, year == 2028 ? 29 : 28, 9, 15),
        DateTime(year, 3, 31, 9, 15),
      ]);
    }
  });

  test('inclusive end date shortens preview, expired pattern shows none', () {
    final task = _task(
      due: DateTime(2026, 10, 30, 12),
      interval: 2,
      end: DateTime(2026, 11, 13),
    );
    expect(RecurrencePreview.build(task, now: DateTime(2026, 10, 26)).dates, [
      DateTime(2026, 10, 30, 12),
      DateTime(2026, 11, 13, 12),
    ]);
    expect(
      RecurrencePreview.build(task, now: DateTime(2026, 11, 13, 13)).dates,
      isEmpty,
    );
  });

  test('monthly weekday last and second week follow the real generator', () {
    for (final week in [-1, 2]) {
      final task = _task(
        due: DateTime(2026, 10, 1, 18),
        repeat: RepeatUnit.monthlyWeekday,
        monthWeek: week,
      );
      expect(
        RecurrencePreview.build(task, now: DateTime(2026, 10, 1)).dates,
        week == -1
            ? [
                DateTime(2026, 10, 30, 18),
                DateTime(2026, 11, 27, 18),
                DateTime(2026, 12, 25, 18),
              ]
            : [
                DateTime(2026, 10, 9, 18),
                DateTime(2026, 11, 13, 18),
                DateTime(2026, 12, 11, 18),
              ],
      );
    }
  });

  test(
    'weekly multiple days preserves interval and daily respects leap day',
    () {
      final weekly = _task(
        due: DateTime(2026, 10, 5, 7),
        weekdays: [1, 4],
        interval: 2,
      );
      expect(RecurrencePreview.build(weekly, now: DateTime(2026, 10)).dates, [
        DateTime(2026, 10, 5, 7),
        DateTime(2026, 10, 8, 7),
        DateTime(2026, 10, 19, 7),
      ]);
      final daily = _task(
        due: DateTime(2028, 2, 28, 23, 59),
        repeat: RepeatUnit.daily,
      );
      expect(RecurrencePreview.build(daily, now: DateTime(2028, 2)).dates, [
        DateTime(2028, 2, 28, 23, 59),
        DateTime(2028, 2, 29, 23, 59),
        DateTime(2028, 3, 1, 23, 59),
      ]);
    },
  );

  test('weekly goal shows possible days and skips non-participating weeks', () {
    final task = _task(
      due: DateTime(2026, 10, 30, 12),
      repeat: RepeatUnit.weeklyGoal,
      countPerWeek: 2,
      interval: 2,
    );
    expect(
      RecurrencePreview.build(task, now: DateTime(2026, 10, 31, 13)).dates,
      [
        DateTime(2026, 11, 1, 12),
        DateTime(2026, 11, 9, 12),
        DateTime(2026, 11, 10, 12),
      ],
    );
  });

  test('invalid draft values show issues instead of inventing a schedule', () {
    final due = DateTime(2026, 10, 30, 12);
    for (final invalidInterval in [0, -1, 366]) {
      final preview = RecurrencePreview.build(
        _task(due: due, interval: invalidInterval),
        now: due,
      );
      expect(preview.dates, isEmpty);
      expect(preview.issue, RecurrencePreviewIssue.interval);
    }
    for (final repeat in [RepeatUnit.weekly, RepeatUnit.monthlyWeekday]) {
      for (final days in <List<int>>[
        [],
        [0],
        [8],
      ]) {
        final preview = RecurrencePreview.build(
          _task(due: due, repeat: repeat, weekdays: days),
          now: due,
        );
        expect(preview.dates, isEmpty);
        expect(preview.issue, RecurrencePreviewIssue.weekdays);
      }
    }
    expect(
      RecurrencePreview.build(
        _task(due: due, repeat: RepeatUnit.monthlyWeekday, weekdays: [1, 5]),
        now: due,
      ).issue,
      RecurrencePreviewIssue.weekdays,
    );
    expect(
      RecurrencePreview.build(
        _task(due: due, repeat: RepeatUnit.monthlyWeekday, monthWeek: 0),
        now: due,
      ).issue,
      RecurrencePreviewIssue.monthlyWeek,
    );
    expect(
      RecurrencePreview.build(
        _task(due: due, repeat: RepeatUnit.weeklyGoal, countPerWeek: 0),
        now: due,
      ).issue,
      RecurrencePreviewIssue.weeklyGoal,
    );
  });

  test('once has no repeat preview and maximal interval stays finite', () {
    final due = DateTime(2026, 10, 30, 12);
    expect(
      RecurrencePreview.build(
        _task(due: due, repeat: RepeatUnit.none),
        now: due,
      ).dates,
      isEmpty,
    );
    expect(
      RecurrencePreview.build(
        _task(due: due, repeat: RepeatUnit.monthly, interval: 365),
        now: due,
      ).dates,
      [due, DateTime(2057, 3, 30, 12), DateTime(2087, 8, 30, 12)],
    );
  });
}
