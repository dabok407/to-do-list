import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart' as app;

/// Start the production entry point and distinguish initialization failures from
/// a missing frame. Native database/plugin work must run outside fake test time.
Future<TaskController> launchApplication(WidgetTester tester) async {
  await tester.runAsync(app.main);
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find
        .text(AppStrings.current.t('앱을 준비하지 못했습니다. 다시 실행해주세요.'))
        .evaluate()
        .isNotEmpty) {
      fail(
        'Production startup failed and displayed its fallback screen. '
        'Inspect the preceding native database/plugin log for the cause.',
      );
    }
    final application = find.byType(app.HangeoreumApp);
    if (application.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return tester.widget<app.HangeoreumApp>(application).controller;
    }
  }
  fail('Production application did not mount within 10 seconds.');
}
