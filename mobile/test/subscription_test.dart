import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/features/pro_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.dabok407.hangeoreum/billing');
  final binding =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => binding.setMockMethodCallHandler(channel, null));

  test('store entitlement lifecycle: restored, canceled renewal, expired, refunded', () async {
    Map<String, Object?> state = {
      'active': true,
      'available': true,
      'price': '₩1,100',
      'autoRenewing': true,
    };
    binding.setMockMethodCallHandler(channel, (_) async => state);
    final s = SubscriptionService();
    await s.restore();
    expect(s.active, isTrue);
    expect(s.price, '₩1,100');
    state = {...state, 'autoRenewing': false};
    await s.refresh();
    expect(
      s.active,
      isTrue,
      reason: 'canceling renewal does not end paid access',
    );
    expect(s.autoRenewing, isFalse);
    state = {'active': false, 'available': true, 'price': '₩1,100'};
    await s.refresh();
    expect(s.active, isFalse);
    await s.restore();
    expect(
      s.active,
      isFalse,
      reason: 'restore cannot fabricate a refunded entitlement',
    );
  });
  test('pending approval does not grant access or issue a second simultaneous purchase', () async {
    final done = Completer<Map<String, Object>>();
    var calls = 0;
    binding.setMockMethodCallHandler(channel, (_) {
      calls++;
      return done.future;
    });
    final s = SubscriptionService();
    final first = s.purchase();
    await s.purchase();
    done.complete({'active': false, 'pending': true, 'available': true});
    await first;
    expect(calls, 1);
    expect(s.active, isFalse);
    expect(s.pending, isTrue);
  });
  test('store failure cannot retain a stale paid flag', () async {
    binding.setMockMethodCallHandler(
      channel,
      (_) async => {'active': true, 'available': true},
    );
    final s = SubscriptionService();
    await s.refresh();
    binding.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'offline'),
    );
    await s.refresh();
    expect(s.active, isFalse);
    expect(s.available, isFalse);
    expect(s.message, isNotNull);
  });
  testWidgets(
    'unconfigured product disables payment; localized price and renewal terms stay visible',
    (tester) async {
      binding.setMockMethodCallHandler(
        channel,
        (_) async => {'active': false, 'available': false},
      );
      final s = SubscriptionService();
      await tester.pumpWidget(MaterialApp(home: ProScreen(subscription: s)));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      binding.setMockMethodCallHandler(
        channel,
        (_) async => {'active': false, 'available': true, 'price': '₩1,100', 'autoRenewing': false},
      );
      await s.refresh();
      await tester.pumpAndSettle();
      expect(find.text('₩1,100 / 1년'), findsOneWidget);
      expect(find.text('1년에 한 번 결제 · 해지 전까지 자동 갱신'), findsOneWidget);
      expect(find.textContaining('자동 갱신이 해제되어'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(find.textContaining('US\$0.70'), findsNothing);
    },
  );
}
