import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/features/backup_screen.dart';
import 'package:hangeoreum/features/privacy_card.dart';
import 'package:hangeoreum/features/pro_screen.dart';
import 'package:hangeoreum/features/settings_widgets.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/notification_privacy.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:sqflite/sqflite.dart';

class _NoDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Settings navigation must not access platform storage');
}

class _Repository extends TaskRepository {
  final values = <String, String>{};
  _Repository() : super(_NoDatabase());
  @override
  Future<String?> setting(String key) async => values[key];
  @override
  Future<void> setSetting(String key, String value) async =>
      values[key] = value;
}

class _Reminders extends ReminderScheduler {
  final actions = <String>[];
  @override
  Future<void> requestPermissions() async => actions.add('permission');
  @override
  Future<void> openSettings() async => actions.add('device');
  @override
  Future<void> requestExactPermission() async => actions.add('exact');
}

class _Controller extends TaskController {
  final languageChanges = <String>[];
  int reconciliations = 0, testNotifications = 0;
  _Controller() : super(_Repository(), _Reminders());
  @override
  Future<void> refresh({DateTime? through}) async => notifyListeners();
  @override
  Future<void> reconcile() async {
    reconciliations++;
    notifyListeners();
  }

  @override
  Future<void> setLanguage(String value) async {
    languageChanges.add(value);
    await localeController.setPreference(value);
    notifyListeners();
  }

  @override
  Future<void> testReminder() async => testNotifications++;
  @override
  Future<void> setNotificationTitles(bool show) async {
    await NotificationPrivacy(repository).setShowTitles(show);
    notifyListeners();
  }
}

enum _Access { free, trial, paid }

class _Subscription extends SubscriptionService {
  final _Access state;
  _Subscription(this.state);
  @override
  bool get paidAccess => state == _Access.paid;
  @override
  bool get trialActive => state == _Access.trial;
  @override
  bool get hasAccess => state != _Access.free;
  @override
  Future<void> refresh() async {}
}

void _phone(WidgetTester tester, {double width = 375, double scale = 1}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 812);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(() => AppStrings.current = const AppStrings('ko'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) =>
    _tap(tester, find.byKey(Key(key)));

Future<void> _closeSheet(WidgetTester tester) async {
  await _tap(tester, find.byIcon(Icons.close_rounded));
  expect(find.byType(BottomSheet), findsNothing);
}

Future<(_Controller, _Subscription)> _open(
  WidgetTester tester, {
  _Access access = _Access.paid,
  String language = 'ko',
}) async {
  final controller = _Controller(), subscription = _Subscription(access);
  addTearDown(controller.dispose);
  addTearDown(subscription.dispose);
  await controller.localeController.setPreference(
    language,
    systemLocale: const Locale('ko', 'KR'),
  );
  await tester.pumpWidget(
    HangeoreumApp(
      controller: controller,
      subscription: subscription,
      initialPage: 4,
    ),
  );
  await tester.pumpAndSettle();
  return (controller, subscription);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(WidgetService.channel, (call) async {
      if (call.method == 'getCalendarPreferences') {
        return {'regionCode': 'KR', 'firstDayOfWeek': 0};
      }
      throw MissingPluginException(
        'Widget operations are outside settings navigation',
      );
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(WidgetService.channel, null),
  );
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
  });

  for (final width in [320.0, 375.0, 402.0]) {
    for (final language in ['ko', 'en']) {
      testWidgets(
        'Settings rows and detail screens fit $width px, $language, 2x',
        (tester) async {
          _phone(tester, width: width, scale: 2);
          await _open(tester, language: language);
          final strings = AppStrings(language);
          expect(find.byType(DropdownButtonFormField<String>), findsNothing);
          expect(tester.takeException(), isNull, reason: 'Settings entry');

          await _tapKey(tester, 'language-setting');
          for (final label in [strings.t('기기 설정 사용'), '한국어', 'English']) {
            final choice = find.widgetWithText(RadioListTile<String>, label);
            await tester.ensureVisible(choice);
            await tester.pumpAndSettle();
            expect(choice.hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull, reason: 'Language sheet');
          await _closeSheet(tester);

          await _tapKey(tester, 'notification-settings');
          for (final action in [
            'request-notification-permission',
            'open-device-notification-settings',
            'test-notification',
          ]) {
            final row = find.byKey(Key(action));
            await tester.ensureVisible(row);
            await tester.pumpAndSettle();
            expect(row.hitTestable(), findsOneWidget);
            expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
          }
          expect(tester.takeException(), isNull, reason: 'Notification sheet');
          await _closeSheet(tester);

          await _tapKey(tester, 'privacy-details');
          expect(find.byType(PrivacyCard), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'Privacy sheet');
          await _closeSheet(tester);

          await _tapKey(tester, 'backup-settings');
          expect(find.byType(BackupScreen), findsOneWidget);
          expect(
            find.byKey(const Key('automatic-backup-toggle')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: 'Backup route');
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('language-setting')), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: const TargetPlatformVariant({TargetPlatform.iOS}),
      );
    }
  }

  testWidgets(
    'Language chooser retains current choice, cancels safely, and updates the existing app',
    (tester) async {
      _phone(tester);
      final (controller, _) = await _open(tester, language: 'system');
      final languageChevron = find.descendant(
        of: find.byKey(const Key('language-setting')),
        matching: find.byIcon(Icons.chevron_right_rounded),
      );
      final backupChevron = find.descendant(
        of: find.byKey(const Key('backup-settings')),
        matching: find.byIcon(Icons.chevron_right_rounded),
      );
      expect(
        tester.getCenter(languageChevron).dx,
        closeTo(tester.getCenter(backupChevron).dx, .1),
        reason: 'A trailing language value must not shift the menu arrow',
      );
      await _tapKey(tester, 'language-setting');
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'system',
      );
      await _closeSheet(tester);
      expect(controller.languageChanges, isEmpty);
      await _tapKey(tester, 'language-setting');
      await _tap(
        tester,
        find.widgetWithText(RadioListTile<String>, '기기 설정 사용'),
      );
      expect(controller.languageChanges, isEmpty);
      // A selected radio is a no-op; it does not write the preference again.
      await _closeSheet(tester);

      await _tapKey(tester, 'language-setting');
      await _tap(tester, find.widgetWithText(RadioListTile<String>, 'English'));
      expect(controller.languageChanges, ['en']);
      expect(
        (controller.repository as _Repository).values['display_language'],
        'en',
      );
      expect(find.text('Settings'), findsWidgets);
      await _tapKey(tester, 'language-setting');
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'en',
      );
      await _tap(tester, find.widgetWithText(RadioListTile<String>, '한국어'));
      expect(controller.languageChanges, ['en', 'ko']);
      expect(controller.localeController.firstDayOfWeekIndex, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final state in _Access.values) {
    testWidgets('$state keeps Pro summary and notification access rules', (
      tester,
    ) async {
      _phone(tester);
      final (controller, _) = await _open(tester, access: state);
      final label = switch (state) {
        _Access.free => '무료 캘린더 이용 중',
        _Access.trial => '전체 기능 7일 체험 중',
        _Access.paid => '투두닉 Pro 이용 중',
      };
      expect(find.text(label), findsOneWidget);
      await _tap(tester, find.widgetWithText(SettingsMenuRow, label));
      expect(find.byType(ProScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      for (final key in [
        'request-notification-permission',
        'test-notification',
      ]) {
        await _tapKey(tester, 'notification-settings');
        await _tapKey(tester, key);
        expect(find.byType(BottomSheet), findsNothing);
        if (state == _Access.free) {
          expect(find.byType(ProScreen), findsOneWidget);
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
        } else {
          expect(find.byType(ProScreen), findsNothing);
        }
      }
      final reminders = controller.reminders as _Reminders;
      expect(
        reminders.actions,
        state == _Access.free ? isEmpty : ['permission'],
      );
      expect(controller.testNotifications, state == _Access.free ? 0 : 1);
      await _tapKey(tester, 'notification-settings');
      await _tapKey(tester, 'open-device-notification-settings');
      expect(reminders.actions.last, 'device');
      expect(find.byType(ProScreen), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'Android exact alarm action is available without Pro and closes its sheet',
    (tester) async {
      _phone(tester);
      final (controller, _) = await _open(tester, access: _Access.free);
      await _tapKey(tester, 'notification-settings');
      await _tap(
        tester,
        find.widgetWithText(SettingsMenuRow, 'Android 정확한 알림 설정'),
      );
      expect((controller.reminders as _Reminders).actions, ['exact']);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(ProScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'Compact title toggle persists changes and reflects restored preferences',
    (tester) async {
      _phone(tester);
      final (controller, _) = await _open(tester);
      final toggle = find.byKey(const Key('notification-title-toggle'));
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await _tap(tester, toggle);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(
        (controller.repository as _Repository).values[NotificationPrivacy
            .settingKey],
        'false',
      );
      await controller.setNotificationTitles(true);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
