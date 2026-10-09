import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'app/task_controller.dart';
import 'data/task_repository.dart';
import 'features/home_screen.dart';
import 'services/reminder_scheduler.dart';
import 'services/widget_service.dart';
import 'services/background_refresh.dart';
import 'services/subscription_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repository = await TaskRepository.open();
    final reminders = ReminderScheduler();
    final widgets = WidgetService();
    final controller = TaskController(repository, reminders, widgets: widgets);
    try {
      await reminders.initialize();
    } catch (_) {
      controller.warning = '알림을 준비하지 못했습니다. 할 일은 로컬에 저장됩니다.';
    }
    reminders.onAction = controller.handleNotification;
    widgets.onLaunch = controller.handleWidgetLaunch;
    await widgets.initialize();
    await controller.reconcile();
    try {
      await reminders.handleLaunch();
      await widgets.handleLaunch();
    } catch (_) {
      /* Keep local tasks usable. */
    }
    runApp(HangeoreumApp(controller: controller));
    try {
      await BackgroundRefresh.register();
    } catch (_) {
      /* OS scheduling budgets do not block local CRUD. */
    }
  } catch (error, stack) {
    assert(() {
      debugPrint('App initialization failed: $error\n$stack');
      return true;
    }());
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(child: Text('앱을 준비하지 못했습니다. 다시 실행해주세요.')),
          ),
        ),
      ),
    );
  }
}

// Debug-only harness for the production scheduler after driver force-stop. It
// omits HomeScreen's resume reconciliation so synthetic probes stay scheduled.
@pragma('vm:entry-point')
Future<void> nativeLifecycleProbe() async {
  if (!kDebugMode) return;
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('알림 종료 상태 검증'))),
    ),
  );
  final scheduler = ReminderScheduler();
  await scheduler.initialize();
  for (final probe in [(100001, 90), (100002, 240)]) {
    await scheduler.plugin.zonedSchedule(
      id: probe.$1,
      title: '한걸음 종료 상태 테스트 ${probe.$1}',
      body: '네이티브 AlarmManager 검증',
      scheduledDate: tz.TZDateTime.now(tz.local)
          .add(Duration(seconds: probe.$2)),
      notificationDetails: scheduler.details(),
      androidScheduleMode: await scheduler.mode(),
    );
  }
  debugPrint('NATIVE_LIFECYCLE_PROBES_READY');
}

@pragma('vm:entry-point')
Future<void> nativeBackgroundProbe() async {
  if (!kDebugMode) return;
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('백그라운드 갱신 검증'))),
    ),
  );
  await BackgroundRefresh.register();
  await Workmanager().registerOneOffTask(
    '$refreshTask.verification',
    refreshTask,
  );
  debugPrint('NATIVE_BACKGROUND_PROBE_REGISTERED');
}

class HangeoreumApp extends StatelessWidget {
  final TaskController controller;
  final SubscriptionService? subscription;
  const HangeoreumApp({super.key, required this.controller, this.subscription});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '한걸음',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      fontFamily: 'Pretendard',
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff394c40),
        primary: const Color(0xff273c32),
        secondary: const Color(0xff7a6654),
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.all(16),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Color(0xffeaf0e9),
        height: 74,
      ),
    ),
    home: HomeScreen(controller: controller, subscription: subscription),
  );
}
