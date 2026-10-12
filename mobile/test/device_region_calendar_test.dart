import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/l10n/device_calendar_localizations.dart';
import 'package:hangeoreum/l10n/locale_controller.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:sqflite/sqflite.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Device calendar tests must not access native storage');
}

class _SettingsRepository extends TaskRepository {
  final values = <String, String>{};
  final writes = <String>[];
  _SettingsRepository() : super(_UnusedDatabase());
  @override
  Future<String?> setting(String key) async => values[key];
  @override
  Future<void> setSetting(String key, String value) async {
    writes.add(key);
    values[key] = value;
  }
}

class _CalendarController extends TaskController {
  _CalendarController(TaskRepository repository)
    : super(repository, ReminderScheduler());
  @override
  Future<void> refresh({DateTime? through}) async => notifyListeners();
  @override
  Future<void> reconcile() async => notifyListeners();
}

class _TrialSubscription extends SubscriptionService {
  @override
  bool get hasAccess => true;
  @override
  bool get paidAccess => false;
  @override
  bool get trialActive => true;
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _SettingsRepository repository;
  late Object? nativePreferences;
  late List<String> nativeCalls;
  late Object? nativeError;

  setUp(() {
    repository = _SettingsRepository();
    nativePreferences = {'regionCode': 'KR', 'firstDayOfWeek': 0};
    nativeCalls = [];
    nativeError = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    LocaleController.currentPreference = 'system';
    AppStrings.current = const AppStrings('ko');
    messenger.setMockMethodCallHandler(WidgetService.channel, (call) async {
      nativeCalls.add(call.method);
      expect(call.method, 'getCalendarPreferences');
      expect(call.arguments, isNull);
      if (nativeError != null) throw nativeError!;
      return nativePreferences;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(WidgetService.channel, null);
    debugDefaultTargetPlatformOverride = null;
    LocaleController.currentPreference = 'system';
    AppStrings.current = const AppStrings('ko');
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final (deviceRegion, deviceDay, displayLanguage, deviceLocale) in [
      ('KR', 0, 'en', const Locale('ko', 'KR')),
      ('GB', 1, 'ko', const Locale('en', 'GB')),
    ]) {
      test(
        '$platform device $deviceRegion controls week start with $displayLanguage UI',
        () async {
          debugDefaultTargetPlatformOverride = platform;
          repository.values[LocaleController.settingKey] = displayLanguage;
          nativePreferences = {
            'regionCode': deviceRegion,
            'firstDayOfWeek': deviceDay,
          };
          final locale = LocaleController(repository);
          addTearDown(locale.dispose);
          await locale.load(systemLocale: deviceLocale);
          expect(locale.locale, Locale(displayLanguage));
          expect(locale.regionCode, deviceRegion);
          expect(locale.firstDayOfWeekIndex, deviceDay);
          expect(repository.writes, isEmpty);
          expect(nativeCalls, ['getCalendarPreferences']);
        },
      );
    }
  }

  test(
    'all OS weekday overrides take priority over the country convention',
    () async {
      final locale = LocaleController(repository);
      addTearDown(locale.dispose);
      for (var day = 0; day < 7; day++) {
        nativePreferences = {'regionCode': 'KR', 'firstDayOfWeek': day};
        await locale.refreshCalendarPreferences(
          systemLocale: const Locale('ko', 'KR'),
        );
        expect(locale.regionCode, 'KR');
        expect(locale.firstDayOfWeekIndex, day);
      }
      expect(repository.writes, isEmpty);
    },
  );

  test(
    'valid native weekday survives missing native and system countries',
    () async {
      final locale = LocaleController(repository);
      addTearDown(locale.dispose);
      nativePreferences = {'firstDayOfWeek': 6};
      await locale.load(systemLocale: const Locale('en'));
      expect(locale.regionCode, isEmpty);
      expect(locale.firstDayOfWeekIndex, 6);
      expect(locale.locale, const Locale('en'));
    },
  );

  test(
    'native region takes priority when the Flutter language locale disagrees',
    () async {
      final locale = LocaleController(repository);
      addTearDown(locale.dispose);
      nativePreferences = {'regionCode': 'GB'};
      await locale.load(systemLocale: const Locale('ko', 'KR'));
      expect(locale.locale, const Locale('ko'));
      expect(locale.regionCode, 'GB');
      expect(locale.firstDayOfWeekIndex, 1);
    },
  );

  test('native region is normalized and invalid country data cannot replace a valid OS locale', () async {
    final locale = LocaleController(repository);
    addTearDown(locale.dispose);
    nativePreferences = {'regionCode': ' gb '};
    await locale.load(systemLocale: const Locale('ko', 'KR'));
    expect(locale.regionCode, 'GB');
    expect(locale.firstDayOfWeekIndex, 1);
    for (final invalidRegion in [
      null,
      44,
      ['GB'],
      'United Kingdom',
      '',
      'G',
    ]) {
      nativePreferences = {'regionCode': invalidRegion};
      await locale.refreshCalendarPreferences(
        systemLocale: const Locale('ko', 'KR'),
      );
      expect(locale.regionCode, 'KR');
      expect(locale.firstDayOfWeekIndex, 0);
    }
  });

  for (final invalidDay in [-1, 7, 1.5, '0', null]) {
    test(
      'invalid native weekday $invalidDay falls back to the device region',
      () async {
        final locale = LocaleController(repository);
        addTearDown(locale.dispose);
        nativePreferences = {'regionCode': 'KR', 'firstDayOfWeek': invalidDay};
        await locale.load(systemLocale: const Locale('en', 'GB'));
        expect(locale.regionCode, 'KR');
        expect(locale.firstDayOfWeekIndex, 0);
      },
    );
  }

  for (final malformed in [
    null,
    'KR',
    ['KR', 0],
    0,
  ]) {
    test(
      'malformed native response $malformed uses the system country',
      () async {
        nativePreferences = malformed;
        final locale = LocaleController(repository);
        addTearDown(locale.dispose);
        await locale.load(systemLocale: const Locale('en', 'GB'));
        expect(locale.regionCode, 'GB');
        expect(locale.firstDayOfWeekIndex, 1);
      },
    );
  }

  for (final error in [
    MissingPluginException('Headless engine has no UI bridge'),
    PlatformException(code: 'unavailable'),
  ]) {
    test(
      'native read failure ${error.runtimeType} does not block local launch',
      () async {
        nativeError = error;
        final locale = LocaleController(repository);
        addTearDown(locale.dispose);
        await locale.load(systemLocale: const Locale('en', 'KR'));
        expect(locale.locale, const Locale('en'));
        expect(locale.regionCode, 'KR');
        expect(locale.firstDayOfWeekIndex, 0);
        expect(repository.writes, isEmpty);
      },
    );
  }

  test('missing country uses the world default instead of guessing from UI language', () async {
    nativePreferences = {};
    final locale = LocaleController(repository);
    addTearDown(locale.dispose);
    await locale.load(systemLocale: const Locale('ko'));
    expect(locale.regionCode, isEmpty);
    expect(locale.firstDayOfWeekIndex, 1);
  });

  test(
    'fallback includes non-Sunday and non-Monday country calendars',
    () async {
      nativePreferences = {};
      final locale = LocaleController(repository);
      addTearDown(locale.dispose);
      for (final (country, day) in [
        ('KR', 0),
        ('US', 0),
        ('JP', 0),
        ('GB', 1),
        ('DE', 1),
        ('FR', 1),
        ('AE', 1),
        ('EG', 6),
        ('MV', 5),
      ]) {
        await locale.refreshCalendarPreferences(
          systemLocale: Locale('en', country),
        );
        expect(locale.regionCode, country);
        expect(locale.firstDayOfWeekIndex, day, reason: country);
      }
    },
  );

  test(
    'display language changes cannot overwrite the OS calendar preference',
    () async {
      nativePreferences = {'regionCode': 'GB', 'firstDayOfWeek': 1};
      final locale = LocaleController(repository);
      addTearDown(locale.dispose);
      await locale.load(systemLocale: const Locale('en', 'GB'));
      for (final preference in ['ko', 'en', 'system']) {
        await locale.setPreference(
          preference,
          systemLocale: const Locale('ko', 'KR'),
        );
        expect(locale.locale, Locale(preference == 'en' ? 'en' : 'ko'));
        expect(locale.regionCode, 'GB');
        expect(locale.firstDayOfWeekIndex, 1);
      }
      expect(repository.writes.toSet(), {LocaleController.settingKey});
    },
  );

  test(
    'restart reads current OS settings instead of persisting an old week start',
    () async {
      repository.values[LocaleController.settingKey] = 'ko';
      final firstLaunch = LocaleController(repository);
      addTearDown(firstLaunch.dispose);
      await firstLaunch.load(systemLocale: const Locale('ko', 'KR'));
      expect(firstLaunch.firstDayOfWeekIndex, 0);
      nativePreferences = {'regionCode': 'GB', 'firstDayOfWeek': 1};
      final nextLaunch = LocaleController(repository);
      addTearDown(nextLaunch.dispose);
      await nextLaunch.load(systemLocale: const Locale('en', 'GB'));
      expect(nextLaunch.locale, const Locale('ko'));
      expect(nextLaunch.regionCode, 'GB');
      expect(nextLaunch.firstDayOfWeekIndex, 1);
      expect(nativeCalls, ['getCalendarPreferences', 'getCalendarPreferences']);
      expect(repository.writes, isEmpty);
    },
  );

  test('refresh publishes changed OS preferences while keeping explicit UI language', () async {
    repository.values[LocaleController.settingKey] = 'ko';
    final locale = LocaleController(repository);
    addTearDown(locale.dispose);
    await locale.load(systemLocale: const Locale('ko', 'KR'));
    var notifications = 0;
    locale.addListener(() => notifications++);
    nativePreferences = {'regionCode': 'GB', 'firstDayOfWeek': 1};
    await locale.refreshCalendarPreferences(
      systemLocale: const Locale('en', 'GB'),
    );
    expect(locale.locale, const Locale('ko'));
    expect(locale.regionCode, 'GB');
    expect(locale.firstDayOfWeekIndex, 1);
    expect(notifications, greaterThan(0));
  });

  test(
    'a stale native response cannot revert a newer region refresh',
    () async {
      final oldRead = Completer<Object?>();
      final newRead = Completer<Object?>();
      var readCount = 0;
      messenger.setMockMethodCallHandler(WidgetService.channel, (call) {
        expect(call.method, 'getCalendarPreferences');
        return ++readCount == 1 ? oldRead.future : newRead.future;
      });
      final locale = LocaleController(repository);
      addTearDown(locale.dispose);
      final oldRefresh = locale.refreshCalendarPreferences(
        systemLocale: const Locale('ko', 'KR'),
      );
      final newRefresh = locale.refreshCalendarPreferences(
        systemLocale: const Locale('en', 'GB'),
      );
      newRead.complete({'regionCode': 'GB', 'firstDayOfWeek': 1});
      await newRefresh;
      expect(locale.regionCode, 'GB');
      oldRead.complete({'regionCode': 'KR', 'firstDayOfWeek': 0});
      await oldRefresh;
      expect(locale.regionCode, 'GB');
      expect(locale.firstDayOfWeekIndex, 1);
    },
  );

  test(
    'an in-flight native read safely completes after controller disposal',
    () async {
      final pending = Completer<Object?>();
      messenger.setMockMethodCallHandler(
        WidgetService.channel,
        (call) => pending.future,
      );
      final locale = LocaleController(repository);
      var notifications = 0;
      locale.addListener(() => notifications++);
      final refresh = locale.refreshCalendarPreferences(
        systemLocale: const Locale('en', 'GB'),
      );
      locale.dispose();
      pending.complete({'regionCode': 'GB', 'firstDayOfWeek': 1});
      await refresh;
      expect(notifications, 0);
    },
  );

  for (final language in ['ko', 'en']) {
    test(
      '$language device calendar keeps the standard translated date and time formats',
      () async {
        final locale = Locale(language);
        final standard = await GlobalMaterialLocalizations.delegate.load(
          locale,
        );
        final device = await const DeviceCalendarMaterialDelegate(
          firstDayOfWeekIndex: 6,
        ).load(locale);
        final sample = DateTime(2026, 10, 12, 13, 5);
        expect(
          device.formatCompactDate(sample),
          standard.formatCompactDate(sample),
        );
        expect(device.formatFullDate(sample), standard.formatFullDate(sample));
        expect(
          device.formatMediumDate(sample),
          standard.formatMediumDate(sample),
        );
        expect(
          device.formatMonthYear(sample),
          standard.formatMonthYear(sample),
        );
        expect(device.formatYear(sample), standard.formatYear(sample));
        expect(
          device.formatTimeOfDay(const TimeOfDay(hour: 13, minute: 5)),
          standard.formatTimeOfDay(const TimeOfDay(hour: 13, minute: 5)),
        );
        expect(device.narrowWeekdays, standard.narrowWeekdays);
        expect(device.cancelButtonLabel, standard.cancelButtonLabel);
        expect(device.firstDayOfWeekIndex, 6);
      },
    );
  }

  for (final (displayLanguage, region, firstDay) in [
    ('en', 'KR', 0),
    ('ko', 'GB', 1),
    ('ko', 'KR', 6),
  ]) {
    testWidgets(
      '$displayLanguage UI home calendar uses $region OS first day $firstDay',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(430, 1100);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        repository.values[LocaleController.settingKey] = displayLanguage;
        nativePreferences = {'regionCode': region, 'firstDayOfWeek': firstDay};
        final controller = _CalendarController(repository);
        final subscription = _TrialSubscription();
        addTearDown(controller.dispose);
        addTearDown(subscription.dispose);
        await controller.localeController.load(
          systemLocale: Locale('en', region),
        );
        await tester.pumpWidget(
          HangeoreumApp(controller: controller, subscription: subscription),
        );
        await tester.pumpAndSettle();
        final material = MaterialLocalizations.of(
          tester.element(find.byType(Scaffold).first),
        );
        expect(material.firstDayOfWeekIndex, firstDay);
        var previousX = -double.infinity;
        for (var offset = 0; offset < 7; offset++) {
          final weekday = (firstDay + offset + 6) % 7 + 1;
          final header = find.byKey(Key('calendar-weekday-$weekday'));
          expect(
            tester.widget<Text>(header).data,
            AppStrings(displayLanguage).weekday(weekday),
          );
          expect(tester.getCenter(header).dx, greaterThan(previousX));
          previousX = tester.getCenter(header).dx;
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      '$displayLanguage date picker aligns its weekday header with OS day $firstDay',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(430, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(displayLanguage),
            supportedLocales: const [Locale('ko'), Locale('en')],
            localizationsDelegates: [
              DeviceCalendarMaterialDelegate(firstDayOfWeekIndex: firstDay),
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(
              body: CalendarDatePicker(
                initialDate: DateTime(2026, 10, 12),
                firstDate: DateTime(2026),
                lastDate: DateTime(2026, 12, 31),
                onDateChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final pickerElement = tester.element(find.byType(CalendarDatePicker));
        final material = MaterialLocalizations.of(pickerElement);
        expect(material.firstDayOfWeekIndex, firstDay);
        final headingTexts = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(CalendarDatePicker),
                matching: find.byType(Text),
              ),
            )
            .where((text) => material.narrowWeekdays.contains(text.data))
            .toList();
        expect(headingTexts.map((text) => text.data).toList(), [
          for (var offset = 0; offset < 7; offset++)
            material.narrowWeekdays[(firstDay + offset) % 7],
        ]);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets(
    'explicit-language app refreshes calendar on OS locale change and resume',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 1100);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      tester.platformDispatcher.localesTestValue = [const Locale('ko', 'KR')];
      repository.values[LocaleController.settingKey] = 'ko';
      final controller = _CalendarController(repository);
      final subscription = _TrialSubscription();
      addTearDown(controller.dispose);
      addTearDown(subscription.dispose);
      await controller.localeController.load(
        systemLocale: const Locale('ko', 'KR'),
      );
      await tester.pumpWidget(
        HangeoreumApp(controller: controller, subscription: subscription),
      );
      await tester.pumpAndSettle();
      nativePreferences = {'regionCode': 'GB', 'firstDayOfWeek': 1};
      tester.platformDispatcher.localesTestValue = [const Locale('en', 'GB')];
      await tester.pumpAndSettle();
      expect(controller.localeController.locale, const Locale('ko'));
      expect(controller.localeController.firstDayOfWeekIndex, 1);
      final readsAfterLocaleChange = nativeCalls.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      nativePreferences = {'regionCode': 'GB', 'firstDayOfWeek': 6};
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(controller.localeController.locale, const Locale('ko'));
      expect(controller.localeController.firstDayOfWeekIndex, 6);
      expect(nativeCalls.length, greaterThan(readsAfterLocaleChange));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
