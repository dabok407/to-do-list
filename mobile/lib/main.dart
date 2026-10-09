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
        seedColor: const Color(0xff343833),
        primary: const Color(0xff292c29),
        onPrimary: Colors.white,
        primaryContainer: const Color(0xffeeede8),
        onPrimaryContainer: const Color(0xff292c29),
        secondary: const Color(0xff78736a),
        secondaryContainer: const Color(0xffeeede8),
        onSecondaryContainer: const Color(0xff292c29),
        surface: const Color(0xfffdfcf9),
        onSurface: const Color(0xff292c29),
        outline: const Color(0xffcac8c1),
        outlineVariant: const Color(0xffe7e5df),
      ),
      scaffoldBackgroundColor: const Color(0xfffdfcf9),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -.6,
          height: 1.35,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -.5,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: -.2,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.45, letterSpacing: -.2),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, letterSpacing: -.1),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfffdfcf9),
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -.5,
          color: Color(0xff292c29),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: const BorderSide(color: Color(0xffd4d1c9)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xff292c29),
        foregroundColor: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xfffdfcf9),
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        selectedColor: const Color(0xffeeede8),
        backgroundColor: const Color(0xfffdfcf9),
        side: const BorderSide(color: Color(0xffe0ddd6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.all(16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xfffdfcf9),
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? const Color(0xff292c29)
                : const Color(0xff93928c),
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? const Color(0xff292c29)
                : const Color(0xff85847e),
          ),
        ),
        height: 68,
      ),
    ),
    home: HomeScreen(controller: controller, subscription: subscription),
  );
}
