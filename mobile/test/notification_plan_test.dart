import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/domain/recurrence.dart';
import 'package:hangeoreum/services/notification_plan.dart';
import 'package:hangeoreum/services/widget_service.dart';

void main() {
  final now = DateTime(2026, 10, 6, 12);
  Task task({
    RepeatUnit repeat = RepeatUnit.daily,
    DateTime? due,
    DateTime? end,
  }) => Task(
    id: 't',
    title: '운동',
    due: due ?? DateTime(2026, 10, 6, 19),
    created: now,
    repeat: repeat,
    weekdays: const [2, 5],
    end: end,
  );
  List<Occurrence> occurrences(Task t) =>
      RecurrenceCalculator.between(t, t.due, DateTime(2027, 3))
          .map(
            (due) => Occurrence(
              id: '${t.id}@${due.toIso8601String()}',
              task: t,
              originalDue: due,
              reminder: due,
            ),
          )
          .toList();

  test('매일 무기한 반복은 60일이 지나도 OS 반복 요청 하나로 이어짐', () {
    final plan = NotificationPlan.build(
      occurrences(task()),
      now: now,
      capacity: 60,
    );
    expect(plan.jobs, hasLength(1));
    expect(plan.jobs.single.repeat, NotificationRepeat.daily);
    expect(plan.deferred, 0);
  });
  test('매주 두 요일 반복은 두 개의 OS 반복 요청', () {
    final plan = NotificationPlan.build(
      occurrences(task(repeat: RepeatUnit.weekly)),
      now: now,
      capacity: 60,
    );
    expect(plan.jobs, hasLength(2));
    expect(plan.jobs.every((j) => j.repeat == NotificationRepeat.weekly), true);
  });
  test('미래 시작일 전에는 반복 알림을 앞당겨 생성하지 않음', () {
    final plan = NotificationPlan.build(
      occurrences(task(due: DateTime(2026, 11, 1, 19))),
      now: now,
      capacity: 60,
    );
    expect(plan.jobs.first.at, DateTime(2026, 11, 1, 19));
    expect(plan.jobs.every((j) => j.repeat == null), true);
  });
  test('종료일 있는 일정은 무한 반복 트리거를 사용하지 않음', () {
    final plan = NotificationPlan.build(
      occurrences(task(end: DateTime(2026, 10, 10))),
      now: now,
      capacity: 60,
    );
    expect(plan.jobs, hasLength(5));
    expect(plan.jobs.every((j) => j.repeat == null), true);
  });
  test('매월 31일은 2월 말일로 보정하고 OS의 31일 트리거로 누락시키지 않음', () {
    final t = task(repeat: RepeatUnit.monthly, due: DateTime(2026, 10, 31, 19));
    final plan = NotificationPlan.build(occurrences(t), now: now, capacity: 60);
    expect(plan.jobs.every((j) => j.repeat == null), true);
    expect(plan.jobs.any((j) => j.at == DateTime(2027, 2, 28, 19)), true);
  });
  test('이번 회차 변경 예외는 OS 반복으로 되살아나지 않음', () {
    final plan = NotificationPlan.build(
      occurrences(task()),
      now: now,
      capacity: 60,
      exceptions: {
        't': [DateTime(2026, 10, 10, 19)],
      },
    );
    expect(plan.jobs.every((j) => j.repeat == null), true);
  });
  test('첫 미루기 알림이 지나도 앞으로 올 추가 알림은 유지', () {
    final t = task(repeat: RepeatUnit.none);
    final o = Occurrence(
      id: 'paused',
      task: t,
      originalDue: now,
      reminder: now.subtract(const Duration(minutes: 10)),
      status: TaskStatus.paused,
      snoozes: 1,
    );
    final plan = NotificationPlan.build([o], now: now, capacity: 60);
    expect(plan.jobs.map((j) => j.at.difference(now).inMinutes), [20, 50]);
  });
  test('OS 예약 한도에서는 먼 요청을 보류하고 가까운 순서로 예약', () {
    final plan = NotificationPlan.build(
      occurrences(task(end: DateTime(2027, 2, 1))),
      now: now,
      capacity: 3,
    );
    expect(plan.jobs, hasLength(3));
    expect(plan.jobs.first.at, DateTime(2026, 10, 6, 19));
    expect(plan.deferred, greaterThan(0));
    expect(plan.coveredThrough, DateTime(2026, 10, 8, 19));
  });
  test('위젯 URI는 한글·시간대 식별자를 보존하고 다른 액션을 거부', () {
    const id = '청소@2026-10-06T19:00:00+09:00';
    final uri = Uri(
      scheme: 'hangeoreum',
      host: 'task',
      queryParameters: {'id': id, 'action': 'snooze'},
    );
    expect(WidgetService.parseLaunch(uri.toString()), (
      id: id,
      action: 'snooze',
    ));
    expect(
      WidgetService.parseLaunch('hangeoreum://task?id=t&action=delete'),
      isNull,
    );
    expect(WidgetService.parseLaunch('https://task?id=t&action=start'), isNull);
  });
  test('지난 알림은 완료한 오늘 회차 대신 어제의 미완료 회차를 선택하지 않음', () {
    final t = task();
    final yesterday = DateTime(2026, 10, 5, 19), today = DateTime(2026, 10, 6, 19);
    final rows = [Occurrence(id: 'yesterday', task: t, originalDue: yesterday, reminder: yesterday), Occurrence(id: 'today', task: t, originalDue: today, reminder: today, status: TaskStatus.completed)];
    expect(resolveReminderPayload(rows, 'repeat:t:0', DateTime(2026, 10, 6, 20))?.id, 'today');
    expect(resolveReminderPayload(rows, 'repeat:t:0', DateTime(2026, 10, 6, 20))?.active, false);
  });
  test('요일마다 남은 주간 알림은 자기 요일 회차에 적용', () {
    final t = task(repeat: RepeatUnit.weekly);
    final tuesday = DateTime(2026, 10, 6, 19), friday = DateTime(2026, 10, 9, 19);
    final rows = [Occurrence(id: 'tuesday', task: t, originalDue: tuesday, reminder: tuesday), Occurrence(id: 'friday', task: t, originalDue: friday, reminder: friday)];
    expect(resolveReminderPayload(rows, 'repeat:t:2', DateTime(2026, 10, 9, 20))?.id, 'tuesday');
    expect(resolveReminderPayload(rows, 'repeat:t:5', DateTime(2026, 10, 9, 20))?.id, 'friday');
  });
}
