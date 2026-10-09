import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/task_repository.dart';

/// Local trial and last verified store entitlement. App inactivity must not
/// revoke a purchase. A known store expiry is enforced even while offline.
class FeatureAccess extends ChangeNotifier {
  final TaskRepository repository;
  final DateTime Function() clock;
  DateTime? trialEnds, paidUntil;
  bool _verifiedPaid = false;
  DateTime? _lastSeen;
  FeatureAccess(this.repository, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  DateTime get now {
    final current = clock();
    return _lastSeen != null && current.isBefore(_lastSeen!)
        ? _lastSeen!
        : current;
  }

  DateTime? get until {
    // Play Billing does not return an expiry. Keep verified access until the
    // next successful store check rather than inventing a purchase anniversary.
    if (_verifiedPaid && paidUntil == null) return null;
    final trial = trialEnds;
    final paid = paidUntil;
    if (trial == null) return paid;
    return paid != null && paid.isAfter(trial) ? paid : trial;
  }

  bool get paidActive => _verifiedPaid && (paidUntil?.isAfter(now) ?? true);
  bool get enabled => paidActive || trialActive;
  bool get trialActive => trialEnds?.isAfter(now) ?? false;
  bool allows(String action) =>
      !{'start', 'small', 'snooze'}.contains(action) || enabled;

  Future<void> load({bool startTrial = false}) =>
      _update(startTrial: startTrial);

  Future<void> verifiedStore({required bool active, DateTime? expires}) =>
      _update(storeActive: active, expires: expires);

  Future<void> _update({
    bool startTrial = false,
    bool? storeActive,
    DateTime? expires,
  }) async {
    await repository.updateSetting('feature_access_v1', (raw) {
      trialEnds = paidUntil = null;
      _verifiedPaid = false;
      if (raw != null) {
        try {
          final value = jsonDecode(raw) as Map<String, dynamic>;
          trialEnds = DateTime.tryParse(value['trialEnds'] ?? '');
          paidUntil = DateTime.tryParse(value['paidUntil'] ?? '');
          if (value['paidUntil'] != null && paidUntil == null) {
            throw const FormatException('Invalid store expiry');
          }
          // Old records only contain a bounded lease. Preserve its boundary;
          // only a new verified result can grant unbounded offline access.
          _verifiedPaid = value['version'] == 2
              ? value['verifiedPaid'] == true
              : paidUntil != null;
          if (!_verifiedPaid) paidUntil = null;
          final seen = DateTime.tryParse(value['lastSeen'] ?? '');
          if (seen != null && (_lastSeen == null || seen.isAfter(_lastSeen!))) {
            _lastSeen = seen;
          }
        } catch (_) {
          trialEnds = paidUntil = null;
          _verifiedPaid = false;
        }
      } else if (startTrial) {
        trialEnds = now.add(const Duration(days: 7));
      } else if (storeActive == null) {
        // A headless launch must not consume or prevent the first-launch trial.
        return null;
      }
      _lastSeen = now;
      if (storeActive != null) {
        _verifiedPaid = storeActive;
        paidUntil = storeActive ? expires : null;
      }
      return jsonEncode({
        'version': 2,
        'verifiedPaid': _verifiedPaid,
        'trialEnds': trialEnds?.toIso8601String(),
        'paidUntil': paidUntil?.toIso8601String(),
        'lastSeen': now.toIso8601String(),
      });
    });
    notifyListeners();
  }
}
