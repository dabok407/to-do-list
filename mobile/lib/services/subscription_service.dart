import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'feature_access.dart';

/// Store-owned entitlements only. No preference flag can unlock paid features.
class SubscriptionService extends ChangeNotifier {
  static const productId = 'hangeoreum_pro_yearly';
  final MethodChannel channel;
  final FeatureAccess? access;
  bool get hasAccess => access?.enabled ?? active;
  DateTime? get trialEnds => access?.trialEnds;
  bool get trialActive => access?.trialActive ?? false;
  bool busy = false, active = false, pending = false;
  bool available = false;
  String? price, message;
  DateTime? expires;
  bool? autoRenewing;
  bool _disposed = false;
  Timer? _timeout;
  Completer<Map<String, dynamic>?>? _request;
  SubscriptionService({
    this.access,
    this.channel = const MethodChannel('com.dabok407.hangeoreum/billing'),
  }) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') await refresh();
    });
  }

  Future<void> refresh() => _call('status');
  Future<void> purchase() => _call('purchase');
  Future<void> restore() => _call('restore');
  Future<void> manage() => _call('manage');

  Future<void> _call(String method) async {
    if (busy || _disposed) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      final request = Completer<Map<String, dynamic>?>();
      _request = request;
      _timeout = Timer(const Duration(seconds: 90), () {
        if (!request.isCompleted) {
          request.completeError(TimeoutException('store'));
        }
      });
      channel
          .invokeMapMethod<String, dynamic>(method)
          .then(
            (value) {
              if (!request.isCompleted) request.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              if (!request.isCompleted) request.completeError(error, stack);
            },
          );
      final result = await request.future;
      if (result != null) {
        active = result['active'] == true;
        pending = result['pending'] == true;
        available = result['available'] == true;
        price = result['price'] as String?;
        autoRenewing = result['autoRenewing'] as bool?;
        expires = result['expires'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (result['expires'] as num).toInt(),
              )
            : null;
        message = result['message'] as String?;
        if (method != 'manage') {
          await access?.verifiedStore(active: active, expires: expires);
        }
      }
    } on MissingPluginException {
      active = false;
      available = false;
      message = '이 환경에서는 스토어 결제를 사용할 수 없어요.';
    } catch (_) {
      // Fail closed if the store cannot establish current access. Basic tasks
      // remain available offline; the last verified 24h access lease is retained.
      active = false;
      available = false;
      message = '스토어에서 구독을 확인하지 못했어요. 인터넷 연결을 확인한 뒤 다시 시도해주세요.';
    } finally {
      _timeout?.cancel();
      _request = null;
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timeout?.cancel();
    if (_request != null && !_request!.isCompleted) _request!.complete(null);
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}
