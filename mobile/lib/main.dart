import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/task_controller.dart';
import 'data/task_repository.dart';
import 'features/home_screen.dart';
import 'services/reminder_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repository = await TaskRepository.open();
    final reminders = ReminderScheduler();
    final controller = TaskController(repository, reminders);
    try {
      await reminders.initialize();
    } catch (_) {
      controller.warning = '알림을 준비하지 못했습니다. 할 일은 로컬에 저장됩니다.';
    }
    reminders.onAction = (id, action) async {
      await repository.act(id, action);
      await controller.reconcile();
    };
    await controller.reconcile();
    try {
      await reminders.handleLaunch();
    } catch (_) {
      /* Keep local tasks usable. */
    }
    runApp(HangeoreumApp(controller: controller));
  } catch (_) {
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

class HangeoreumApp extends StatelessWidget {
  final TaskController controller;
  const HangeoreumApp({super.key, required this.controller});
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
        seedColor: const Color(0xff3569ed),
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
        height: 74,
      ),
    ),
    home: HomeScreen(controller: controller),
  );
}
