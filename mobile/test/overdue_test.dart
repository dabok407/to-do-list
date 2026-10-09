import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/services/notification_plan.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final monday = DateTime(2026, 10, 5, 9);
  final friday = DateTime(2026, 10, 9, 12);
  Task task({int days = 1, int? minute}) => Task(
    id: 'filter',
    title: '에어컨 필터 청소',
    due: friday,
    created: monday,
    overdueDays: days,
    overdueMinute: minute,
  );
  Occurrence occurrence(
    Task t, {
    TaskStatus status = TaskStatus.pending,
    DateTime? reminder,
  }) => Occurrence(
    id: 'filter@friday',
    task: t,
    originalDue: friday,
    reminder: reminder ?? friday,
    status: status,
  );
  NotificationPlan plan(Occurrence o, DateTime now) =>
      NotificationPlan.build([o], now: now, capacity: 60);

  test('월요일에 등록한 금요일 12시 일정은 토요일 12시부터 하루 한 번', () {
    final jobs = plan(occurrence(task()), monday).jobs;
    expect(jobs.first.at, friday);
    final followups = jobs.where((j) => j.key.startsWith('overdue:')).toList();
    expect(followups.first.at, DateTime(2026, 10, 10, 12));
    expect(followups[1].at, DateTime(2026, 10, 11, 12));
    expect(
      followups.every((j) => j.repeat == null),
      true,
      reason: '미래 기한 전 iOS 반복 트리거가 먼저 울리면 안 된다',
    );
    expect(followups.map((j) => j.at).toSet().length, followups.length);
  });
  test('기한 경과 후에는 OS 일일 반복 한 개로 앱 종료 중에도 계속 예약', () {
    final jobs = plan(occurrence(task()), DateTime(2026, 10, 9, 13)).jobs;
    expect(jobs, hasLength(1));
    expect(jobs.single.at, DateTime(2026, 10, 10, 12));
    expect(jobs.single.repeat, NotificationRepeat.daily);
    expect(jobs.single.payload, 'filter@friday');
  });
  test('완료·건너뛰기·삭제는 재알림을 없애고 완료 해제는 다시 예약', () {
    for (final state in [TaskStatus.completed, TaskStatus.skipped]) {
      expect(
        plan(occurrence(task(), status: state), DateTime(2026, 10, 10)).jobs,
        isEmpty,
      );
    }
    expect(NotificationPlan.build([], now: monday, capacity: 60).jobs, isEmpty);
    expect(plan(occurrence(task()), DateTime(2026, 10, 10)).jobs, isNotEmpty);
  });
  test('일정마다 끄기·3일 간격·별도 시각을 선택 가능', () {
    expect(
      plan(occurrence(task(days: 0)), DateTime(2026, 10, 10)).jobs,
      isEmpty,
    );
    final jobs = plan(
      occurrence(task(days: 3, minute: 18 * 60 + 30)),
      monday,
    ).jobs;
    expect(jobs[1].at, DateTime(2026, 10, 12, 18, 30));
    expect(jobs[2].at, DateTime(2026, 10, 15, 18, 30));
  });
  test('보류 중에는 사용자가 선택한 미래 시간보다 먼저 재촉하지 않음', () {
    final held = DateTime(2026, 10, 12, 15);
    final jobs = plan(
      occurrence(task(), status: TaskStatus.paused, reminder: held),
      DateTime(2026, 10, 10),
    ).jobs;
    expect(jobs.first.at, held);
    expect(jobs.skip(1).every((j) => j.at.isAfter(held)), true);
    expect(jobs[1].at, DateTime(2026, 10, 13, 12));
  });
  test('지난 반복 회차가 여러 개여도 같은 시각에 같은 일의 배너를 중복 예약하지 않음', () {
    final t = Task.fromMap({...task().toMap(), 'repeat_unit': 'weekly'});
    final earlier = friday.subtract(const Duration(days: 7));
    final jobs = NotificationPlan.build(
      [
        Occurrence(
          id: 'earlier',
          task: t,
          originalDue: earlier,
          reminder: earlier,
        ),
        occurrence(t),
      ],
      now: DateTime(2026, 10, 9, 13),
      capacity: 60,
    ).jobs;
    expect(jobs.map((j) => j.at).toSet().length, jobs.length);
    expect(jobs.first.payload, 'filter@friday');
  });
  test('재알림 설정은 SQLite 저장·다시 읽기 후에도 보존', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final repository = await TaskRepository.open(
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(repository.db.close);
    await repository.saveTask(task(days: 7, minute: 9 * 60));
    final saved = (await repository.tasks()).single;
    expect(saved.overdueDays, 7);
    expect(saved.overdueMinute, 540);
    await repository.saveTask(
      Task.fromMap({...saved.toMap(), 'overdue_days': 0}),
    );
    expect((await repository.tasks()).single.overdueDays, 0);
  });
}
