import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/widget_service.dart';

class RecordingReminders extends ReminderScheduler {
  List<Occurrence> scheduled = [];
  @override
  Future<void> requestPermissions() async { throw StateError('Permission denied'); }
  @override
  Future<bool?> enabled() async => false;
  @override
  Future<void> sync(List<Occurrence> items, {Map<String, List<DateTime>> exceptions = const {}}) async { scheduled = List.of(items); }
}
class RecordingWidgets extends WidgetService {
  List<Occurrence> snapshot = [];
  @override
  Future<void> sync(List<Occurrence> items) async { snapshot = List.of(items); }
}

void main() {
  late TaskRepository repository;
  late RecordingReminders reminders;
  late RecordingWidgets widgets;
  late TaskController controller;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repository = await TaskRepository.open(databasePath: inMemoryDatabasePath);
    reminders = RecordingReminders(); widgets = RecordingWidgets();
    controller = TaskController(repository, reminders, widgets: widgets);
  });
  tearDown(() async { controller.dispose(); await repository.db.close(); });
  Task make() => Task(id: 't', title: '안방 대청소', due: DateTime.now().add(const Duration(hours: 1)), created: DateTime.now());

  test('알림 권한이 거부되어도 할 일을 저장하고 위젯과 목록을 갱신', () async {
    await controller.save(make());
    expect(controller.items.single.task.title, '안방 대청소');
    expect(widgets.snapshot.single.id, controller.items.single.id);
    expect(controller.warning, contains('알림이 꺼져'));
  });
  test('백그라운드 예약 lease 이후 완료 상태로 다시 읽어 예약을 정리', () async {
    await controller.save(make());
    final occurrence = controller.items.single;
    expect(await repository.acquireReminderLease('background'), true);
    final release = Timer(const Duration(milliseconds: 250), () { repository.releaseReminderLease('background'); });
    await controller.act(occurrence, 'complete');
    release.cancel();
    expect(reminders.scheduled.single.active, false);
    expect(widgets.snapshot.single.status, TaskStatus.completed);
  });
  test('연속 완료·완료 해제는 마지막 상태로 알림과 위젯을 유지', () async {
    await controller.save(make());
    final occurrence = controller.items.single;
    await Future.wait([controller.act(occurrence, 'complete'), controller.act(occurrence, 'uncomplete')]);
    expect(controller.items.single.status, TaskStatus.pending);
    expect(reminders.scheduled.single.status, TaskStatus.pending);
    expect(widgets.snapshot.single.status, TaskStatus.pending);
    expect(controller.statistics['completed'], 0);
  });
}
