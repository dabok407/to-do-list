import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('preview stats follow actual snooze actions, including completion and deletion', () async {
    final controller = PreviewController();
    await controller.refresh();
    expect(controller.statistics['snoozes'], 0);
    expect(controller.statistics['average'], 0);
    var row = controller.items.firstWhere((o) => o.active);
    final id = row.id;
    await controller.act(row, 'snooze', minutes: 10);
    row = controller.items.firstWhere((o) => o.id == id);
    await controller.act(row, 'snooze', minutes: 30);
    expect(controller.statistics['snoozes'], 2);
    expect(controller.statistics['average'], 20);
    row = controller.items.firstWhere((o) => o.id == id);
    await controller.act(row, 'complete');
    expect(controller.statistics['average'], 20);
    await controller.deleteOccurrence(row, scope: 'series');
    expect(controller.statistics['snoozes'], 0);
    expect(controller.statistics['average'], 0);
    controller.dispose();
  });

  test(
    'preview period queries filter completions and snooze events together',
    () async {
      final controller = PreviewController();
      addTearDown(controller.dispose);
      await controller.refresh();
      var row = controller.items.firstWhere((o) => o.active);
      final id = row.id;
      await controller.act(row, 'snooze', minutes: 15);
      row = controller.items.firstWhere((o) => o.id == id);
      await controller.act(row, 'snooze', minutes: 25);
      row = controller.items.firstWhere((o) => o.id == id);
      await controller.act(row, 'complete');
      final now = DateTime.now();
      final today = await controller.statisticsForPeriod(
        DateTime(now.year, now.month, now.day),
        now,
      );
      expect(today['completed'], 1);
      expect(today['snoozes'], 2);
      expect(today['average'], 20);
      expect(today['hour'], '${now.hour}시');
      final historical = await controller.statisticsForPeriod(
        now.subtract(const Duration(days: 80)),
        now.subtract(const Duration(days: 60)),
      );
      expect(historical['completed'], 0);
      expect(historical['registered'], 0);
      expect(historical['snoozes'], 0);
      expect(historical['average'], 0);
      expect(historical['hour'], '기록 없음');
    },
  );
}
