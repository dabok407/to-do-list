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
}
