import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/features/pro_screen.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/feature_access.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:sqflite/sqflite.dart';

class _NoDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('The billing UI fixture only uses saved settings');
}

class _SettingsRepository extends TaskRepository {
  final settings = <String, String>{};
  _SettingsRepository() : super(_NoDatabase());

  @override
  Future<String?> setting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
  }

  @override
  Future<void> updateSetting(
    String key,
    String? Function(String?) update,
  ) async {
    final value = update(settings[key]);
    if (value != null) settings[key] = value;
  }
}

class _Controller extends TaskController {
  _Controller(TaskRepository repository)
    : super(repository, ReminderScheduler());

  @override
  Future<void> reconcile() async {}
}

const _billing = MethodChannel('com.dabok407.hangeoreum/billing');
final _messenger =
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
final _start = DateTime(2026, 10, 17, 12);

/// Uses the production entitlement parser and persisted-access implementation.
/// The method-channel replies simulate verified native store results; these
/// tests do not claim to execute an actual StoreKit transaction.
class _Fixture {
  final repository = _SettingsRepository();
  late final access = FeatureAccess(repository, clock: () => now);
  late final controller = _Controller(repository);
  late final service = SubscriptionService(access: access);
  DateTime now = _start;
  Map<String, Object?> response = {'active': false, 'available': true};
  Object? error;
  final methods = <String>[];

  Future<void> initialize(String language, {bool expiredTrial = false}) async {
    _messenger.setMockMethodCallHandler(_billing, (call) async {
      methods.add(call.method);
      if (error != null) throw error!;
      return response;
    });
    await access.load(startTrial: true);
    if (expiredTrial) {
      now = _start.add(const Duration(days: 8));
      await access.load();
    }
    await controller.localeController.setPreference(language);
  }

  void paid({bool autoRenewing = true}) {
    error = null;
    response = {
      'active': true,
      'available': true,
      'price': '₩1,100',
      'autoRenewing': autoRenewing,
      'expires': _start.add(const Duration(days: 365)).millisecondsSinceEpoch,
    };
  }

  void dispose() {
    service.dispose();
    access.dispose();
    controller.dispose();
  }
}

Future<void> _home(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(
    HangeoreumApp(
      controller: fixture.controller,
      subscription: fixture.service,
    ),
  );
  await tester.pumpAndSettle();
}

Finder _nav(String text) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(text));

void _expectNoTrialCard(String language) {
  final strings = AppStrings(language);
  expect(find.byKey(const Key('access-notice')), findsNothing);
  expect(find.text(strings.t('전체 기능 7일 체험 중')), findsNothing);
  expect(find.textContaining(strings.t('체험만으로 결제되지 않아요')), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    _messenger.setMockMethodCallHandler(WidgetService.channel, (call) async {
      if (call.method == 'getCalendarPreferences') {
        return {'regionCode': 'KR', 'firstDayOfWeek': 0};
      }
      throw MissingPluginException('Not required by the billing UI fixture');
    });
  });
  tearDown(() {
    _messenger.setMockMethodCallHandler(_billing, null);
    _messenger.setMockMethodCallHandler(WidgetService.channel, null);
    AppStrings.current = const AppStrings('ko');
  });

  for (final language in ['ko', 'en']) {
    testWidgets(
      '$language verified purchase removes the entire trial card and purchase prompts',
      (tester) async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        await fixture.initialize(language);
        await _home(tester, fixture);
        final strings = AppStrings(language);
        expect(find.byKey(const Key('access-notice')), findsOneWidget);
        expect(find.text(strings.t('전체 기능 7일 체험 중')), findsOneWidget);

        fixture.paid();
        await fixture.service.purchase();
        await tester.pumpAndSettle();
        expect(fixture.methods, contains('purchase'));
        expect(fixture.service.paidAccess, isTrue);
        expect(
          fixture.service.trialActive,
          isTrue,
          reason: 'A valid local trial may still exist after a purchase',
        );
        _expectNoTrialCard(language);

        await tester.tap(_nav(strings.t('설정')));
        await tester.pumpAndSettle();
        expect(find.text(strings.t('투두닉 Pro 이용 중')), findsOneWidget);
        expect(find.text(strings.t('전체 기능 7일 체험 중')), findsNothing);
        await tester.tap(find.text(strings.t('투두닉 Pro 이용 중')));
        await tester.pumpAndSettle();
        expect(find.byType(ProScreen), findsOneWidget);
        expect(find.text(strings.t('Pro 이용 중')), findsOneWidget);
        expect(find.text(strings.t('7일 체험 후 Pro')), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.text(strings.t('구매 복원')), findsOneWidget);
        expect(find.text(strings.t('구독 관리·해지')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'purchase remains paid after a restart and an unavailable store check',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.initialize('ko');
      fixture.paid(autoRenewing: false);
      await fixture.service.purchase();
      await _home(tester, fixture);
      _expectNoTrialCard('ko');
      expect(
        fixture.service.autoRenewing,
        isFalse,
        reason: 'Canceling renewal does not end the already paid period',
      );
      await tester.pumpWidget(const SizedBox.shrink());

      fixture.now = _start.add(const Duration(days: 30));
      final reopened = FeatureAccess(
        fixture.repository,
        clock: () => fixture.now,
      );
      addTearDown(reopened.dispose);
      await reopened.load(startTrial: true);
      final service = SubscriptionService(access: reopened);
      addTearDown(service.dispose);
      fixture.error = PlatformException(code: 'offline');
      await tester.pumpWidget(
        HangeoreumApp(controller: fixture.controller, subscription: service),
      );
      await tester.pumpAndSettle();
      expect(service.paidAccess, isTrue);
      expect(service.trialActive, isFalse);
      _expectNoTrialCard('ko');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a verified restore removes an expired-trial upsell', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.initialize('ko', expiredTrial: true);
    await _home(tester, fixture);
    expect(find.byKey(const Key('access-notice')), findsOneWidget);
    expect(find.text('무료 캘린더 이용 중'), findsOneWidget);
    fixture.paid();
    await fixture.service.restore();
    await tester.pumpAndSettle();
    expect(fixture.methods, contains('restore'));
    _expectNoTrialCard('ko');
    expect(fixture.service.hasAccess, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final failure in ['pending', 'canceled', 'offline', 'incomplete']) {
    testWidgets('$failure purchase cannot hide the trial as if paid', (
      tester,
    ) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.initialize('ko');
      await _home(tester, fixture);
      fixture.response = switch (failure) {
        'pending' => {'active': false, 'available': true, 'pending': true},
        'canceled' => {'active': false, 'available': true},
        'incomplete' => {'available': true},
        _ => {'active': false},
      };
      if (failure == 'offline') {
        fixture.error = PlatformException(code: 'offline');
      }
      await fixture.service.purchase();
      await tester.pumpAndSettle();
      expect(fixture.service.paidAccess, isFalse);
      expect(find.byKey(const Key('access-notice')), findsOneWidget);
      expect(find.text('전체 기능 7일 체험 중'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('confirmed loss of paid access restores the free-status card', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.initialize('ko', expiredTrial: true);
    fixture.paid();
    await _home(tester, fixture);
    _expectNoTrialCard('ko');
    fixture.response = {'active': false, 'available': true};
    await fixture.service.refresh();
    await tester.pumpAndSettle();
    expect(fixture.service.hasAccess, isFalse);
    expect(find.byKey(const Key('access-notice')), findsOneWidget);
    expect(find.text('무료 캘린더 이용 중'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
