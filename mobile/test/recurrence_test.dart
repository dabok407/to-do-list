import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/domain/recurrence.dart';

void main() {
  Task task(
    DateTime due,
    RepeatUnit repeat, {
    int interval = 1,
    List<int> days = const [],
    DateTime? end,
    int week = 1,
  }) => Task(
    id: 't',
    title: '테스트',
    due: due,
    created: due,
    repeat: repeat,
    interval: interval,
    weekdays: days,
    end: end,
    monthWeek: week,
  );
  test('말일 보정 뒤에도 원래 날짜 유지', () {
    final t = task(DateTime(2028, 1, 31, 19), RepeatUnit.monthly);
    final dates = RecurrenceCalculator.between(
      t,
      DateTime(2028, 1, 1),
      DateTime(2028, 3, 31),
    ).toList();
    expect(dates, [
      DateTime(2028, 1, 31, 19),
      DateTime(2028, 2, 29, 19),
      DateTime(2028, 3, 31, 19),
    ]);
  });
  test('격주 여러 요일과 종료일 포함', () {
    final t = task(
      DateTime(2026, 10, 5, 10),
      RepeatUnit.weekly,
      interval: 2,
      days: [1, 4],
      end: DateTime(2026, 10, 22),
    );
    expect(
      RecurrenceCalculator.between(
        t,
        t.due,
        DateTime(2026, 11),
      ).map(dayKey).toList(),
      ['2026-10-05', '2026-10-08', '2026-10-19', '2026-10-22'],
    );
  });
  test('매월 마지막 금요일', () {
    final t = task(
      DateTime(2026, 10, 1, 9),
      RepeatUnit.monthlyWeekday,
      days: [5],
      week: -1,
    );
    expect(
      RecurrenceCalculator.between(
        t,
        t.due,
        DateTime(2026, 12, 31),
      ).map(dayKey).toList(),
      ['2026-10-30', '2026-11-27', '2026-12-25'],
    );
  });
  test('단발성 일정은 정확히 한 회차', () {
    final t = task(DateTime(2026, 10, 10, 19), RepeatUnit.none);
    expect(
      RecurrenceCalculator.between(
        t,
        DateTime(2026, 10),
        DateTime(2026, 12),
      ).length,
      1,
    );
  });
}
