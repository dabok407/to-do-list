import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/task_repository.dart';

/// Local, installation-scoped trial. Store verification grants a bounded offline
/// lease, never a fabricated year based on a purchase timestamp.
class FeatureAccess extends ChangeNotifier {
  final TaskRepository repository;
  final DateTime Function() clock;
  DateTime? trialEnds, paidUntil;
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
    final trial = trialEnds;
    final paid = paidUntil;
    if (trial == null) return paid;
    return paid != null && paid.isAfter(trial) ? paid : trial;
  }

  bool get enabled => until?.isAfter(now) ?? false;
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
      if (raw != null) {
        try {
          final value = jsonDecode(raw) as Map<String, dynamic>;
          trialEnds = DateTime.tryParse(value['trialEnds'] ?? '');
          paidUntil = DateTime.tryParse(value['paidUntil'] ?? '');
          final seen = DateTime.tryParse(value['lastSeen'] ?? '');
          if (seen != null && (_lastSeen == null || seen.isAfter(_lastSeen!))) {
            _lastSeen = seen;
          }
        } catch (_) {
          trialEnds = paidUntil = null;
        }
      } else if (startTrial) {
        trialEnds = now.add(const Duration(days: 7));
      } else if (storeActive == null) {
        // A headless launch must not consume or prevent the first-launch trial.
        return null;
      }
      _lastSeen = now;
      if (storeActive != null) {
        final limit = now.add(const Duration(hours: 24));
        paidUntil = storeActive
            ? (expires != null && expires.isBefore(limit) ? expires : limit)
            : null;
      }
      return jsonEncode({
        'trialEnds': trialEnds?.toIso8601String(),
        'paidUntil': paidUntil?.toIso8601String(),
        'lastSeen': now.toIso8601String(),
      });
    });
    notifyListeners();
  }
}
