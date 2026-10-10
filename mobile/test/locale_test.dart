import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/l10n/locale_controller.dart';
import 'package:hangeoreum/services/notification_plan.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _LanguageReminders extends ReminderScheduler {
  int categoryRegistrations = 0;
  String? scheduledLanguage;
  @override
  Future<void> initialize() async {
    categoryRegistrations++;
  }

  @override
  Future<bool?> enabled() async => true;
  @override
  Future<void> requestPermissions() async {}
  @override
  Future<void> sync(
    List<Occurrence> items, {
    Map<String, List<DateTime>> exceptions = const {},
  }) async {
    scheduledLanguage = AppStrings.current.languageCode;
  }
}

class _LanguageWidgets extends WidgetService {
  String? displayedLanguage;
  @override
  Future<void> sync(List<Occurrence> items) async {
    displayedLanguage = AppStrings.current.languageCode;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TaskRepository repository;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repository = await TaskRepository.open(databasePath: inMemoryDatabasePath);
    AppStrings.current = const AppStrings('ko');
    LocaleController.currentPreference = 'system';
  });
  tearDown(() async {
    AppStrings.current = const AppStrings('ko');
    LocaleController.currentPreference = 'system';
    debugDefaultTargetPlatformOverride = null;
    await repository.db.close();
  });

  test('system choice follows supported language and unsupported locales use English', () async {
    final locale = LocaleController(repository);
    await locale.load(systemLocale: const Locale('ko', 'KR'));
    expect(locale.preference, 'system');
    expect(locale.locale.languageCode, 'ko');
    await locale.load(systemLocale: const Locale('fr'));
    expect(locale.locale.languageCode, 'en');
    locale.dispose();
  });

  test('explicit language survives reload and does not modify user content or category keys', () async {
    final task = Task(
      id: 't',
      title: '에어컨 필터 청소',
      note: '필터 2개 / bedroom',
      category: '생활',
      smallStep: '필터 꺼내기',
      due: DateTime(2026, 10, 12, 12),
      created: DateTime(2026, 10, 10),
    );
    await repository.saveTask(task);
    final before = (await repository.tasks()).single.toMap();
    final locale = LocaleController(repository);
    await locale.setPreference('en', systemLocale: const Locale('ko'));
    final reloaded = LocaleController(repository);
    await reloaded.load(systemLocale: const Locale('ko'));
    expect(reloaded.preference, 'en');
    expect(reloaded.locale, const Locale('en'));
    expect((await repository.tasks()).single.toMap(), before);
    expect(AppStrings.current.category('생활'), 'Personal');
    expect(AppStrings.current.category('취소'), '취소');
    await expectLater(locale.setPreference('invalid'), throwsArgumentError);
    expect(await repository.setting(LocaleController.settingKey), 'en');
    await locale.setPreference('system', systemLocale: const Locale('ko'));
    expect(locale.locale, const Locale('ko'));
    locale.dispose();
    reloaded.dispose();
  });

  test(
    'English reminder bodies preserve Korean task title, dates, and payload',
    () async {
      AppStrings.current = const AppStrings('en');
      final now = DateTime(2026, 10, 10, 10);
      await repository.saveTask(
        Task(
          id: 't',
          title: '에어컨 필터 청소',
          due: now.add(const Duration(hours: 2)),
          created: now,
        ),
      );
      final occurrences = await repository.occurrences();
      final plan = NotificationPlan.build(occurrences, now: now, capacity: 60);
      expect(plan.jobs.first.title, '에어컨 필터 청소');
      expect(plan.jobs.first.body, 'Ready to start?');
      expect(plan.jobs.first.payload, occurrences.single.id);
      expect(plan.jobs.first.at, occurrences.single.reminder);
      expect(
        plan.jobs.skip(1).every((job) => !RegExp(r'[가-힣]').hasMatch(job.body)),
        isTrue,
      );
    },
  );

  test('language switch re-registers notification categories, reminders, and native widgets', () async {
    final reminders = _LanguageReminders();
    final widgets = _LanguageWidgets();
    final controller = TaskController(repository, reminders, widgets: widgets);
    final now = DateTime.now();
    await controller.save(
      Task(
        id: 't',
        title: '필터 청소',
        due: now.add(const Duration(hours: 1)),
        created: now,
      ),
    );
    expect(reminders.scheduledLanguage, 'ko');
    await controller.setLanguage('en');
    expect(reminders.categoryRegistrations, 1);
    expect(reminders.scheduledLanguage, 'en');
    expect(widgets.displayedLanguage, 'en');
    expect(controller.items.single.task.title, '필터 청소');
    expect(await repository.setting(LocaleController.settingKey), 'en');
    controller.dispose();
  });

  test('date and time formatting changes by locale across midnight and year boundaries', () {
    const english = AppStrings('en');
    const korean = AppStrings('ko');
    expect(english.time(DateTime(2026, 10, 10)), '12:00 AM');
    expect(english.time(DateTime(2026, 10, 10, 12)), '12:00 PM');
    expect(english.month(DateTime(2026, 10)), 'October 2026');
    expect(korean.month(DateTime(2026, 10)), '2026년 10월');
    expect(english.weekday(7), 'Sun');
    expect(korean.weekday(7), '일');
    expect(
      english.dayLabel(DateTime(2027, 1, 1), now: DateTime(2026, 12, 31, 23)),
      'Tomorrow',
    );
    expect(english.dateShort(DateTime(2026, 10, 10)), 'Oct 10');
  });

  test(
    'native widget snapshot records display language while keeping task data',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({});
      AppStrings.current = const AppStrings('en');
      final now = DateTime.now();
      await repository.saveTask(
        Task(
          id: 't',
          title: '필터 청소',
          due: now.add(const Duration(hours: 2)),
          created: now,
        ),
      );
      Map<Object?, Object?>? payload;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WidgetService.channel, (call) async {
            payload = call.arguments as Map<Object?, Object?>;
            return null;
          });
      await WidgetService().sync(await repository.occurrences());
      final prefs = await SharedPreferences.getInstance();
      final snapshot = jsonDecode(prefs.getString('widget_snapshot')!) as Map;
      expect(snapshot['languageCode'], 'en');
      expect(snapshot['languagePreference'], 'system');
      expect((snapshot['tasks'] as List).first['title'], '필터 청소');
      expect(payload?['languageCode'], 'en');
      expect(payload?['languagePreference'], 'system');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WidgetService.channel, null);
    },
  );

  test('widget keeps the language choice separate from its current resolved locale', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    final locale = LocaleController(repository);
    addTearDown(locale.dispose);
    Map<Object?, Object?>? payload;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(WidgetService.channel, (call) async {
      payload = call.arguments as Map<Object?, Object?>;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(WidgetService.channel, null),
    );

    for (final choice in ['system', 'ko', 'en']) {
      for (final deviceLocale in [const Locale('ko'), const Locale('en')]) {
        await locale.setPreference(choice, systemLocale: deviceLocale);
        await WidgetService().sync([]);
        final prefs = await SharedPreferences.getInstance();
        final snapshot = jsonDecode(prefs.getString('widget_snapshot')!) as Map;
        final expectedLanguage = choice == 'system'
            ? deviceLocale.languageCode
            : choice;
        expect(snapshot['languagePreference'], choice);
        expect(snapshot['languageCode'], expectedLanguage);
        expect(payload?['languagePreference'], choice);
        expect(payload?['languageCode'], expectedLanguage);
      }
    }

    // A headless engine loads the saved choice before building the snapshot.
    await locale.setPreference('system', systemLocale: const Locale('ko'));
    final reloaded = LocaleController(repository);
    addTearDown(reloaded.dispose);
    await reloaded.load(systemLocale: const Locale('en'));
    await WidgetService().sync([]);
    expect(payload?['languagePreference'], 'system');
    expect(payload?['languageCode'], 'en');
  });

  test(
    'store messages respond to locale changes without a second store request',
    () {
      final subscription = SubscriptionService(
        channel: const MethodChannel('locale_test_billing'),
      );
      subscription.message = '결제를 취소했어요.';
      expect(subscription.message, '결제를 취소했어요.');
      AppStrings.current = const AppStrings('en');
      expect(subscription.message, 'Purchase canceled.');
      AppStrings.current = const AppStrings('ko');
      expect(subscription.message, '결제를 취소했어요.');
      subscription.dispose();
    },
  );

  testWidgets('same component resolves copy from localization delegate', (
    tester,
  ) async {
    Widget app(Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Builder(builder: (context) => Text(AppStrings.of(context).t('메모'))),
    );
    await tester.pumpWidget(app(const Locale('ko')));
    await tester.pumpAndSettle();
    expect(find.text('메모'), findsOneWidget);
    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('메모'), findsNothing);
  });
}
