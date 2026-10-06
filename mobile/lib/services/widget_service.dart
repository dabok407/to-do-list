import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/task.dart';

/// Native WidgetKit/RemoteViews share a local snapshot, never the database file.
class WidgetService {
  static const channel = MethodChannel('com.dabok407.hangeoreum/widget');
  Future<void> Function(String uri)? onLaunch;

  Future<void> initialize() async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'launchUri' && call.arguments is String) {
        await onLaunch?.call(call.arguments as String);
      }
    });
  }

  Future<void> handleLaunch() async {
    try {
      final uri = await channel.invokeMethod<String>('getLaunchUri');
      if (uri != null) await onLaunch?.call(uri);
    } on MissingPluginException {
      // Unit tests/background engines do not register a UI channel.
    }
  }

  Future<void> sync(List<Occurrence> items) async {
    final today = dayOf(DateTime.now());
    final byTask = <String, List<Occurrence>>{};
    for (final o in items.where((o) => o.active)) {
      // A flexible goal is an invitation on the current/future day, not overdue debt.
      if (o.task.repeat == RepeatUnit.weeklyGoal &&
          dayOf(o.originalDue).isBefore(today)) {
        continue;
      }
      if (o.task.repeat != RepeatUnit.none &&
          o.status == TaskStatus.pending &&
          dayOf(o.originalDue).isBefore(today)) {
        continue;
      }
      (byTask[o.task.id] ??= []).add(o);
    }
    final snapshot = <Map<String, Object>>[];
    for (final occurrences in byTask.values) {
      // Include the current actionable item and future calendar dates so timelines
      // keep advancing while the app is closed.
      snapshot.addAll(
        occurrences.map(
          (o) => {
            'id': o.id,
            'taskId': o.task.id,
            'title': o.task.title,
            'due': o.reminder.millisecondsSinceEpoch,
            'priority': o.task.priority,
            'status': o.status.name,
            'smallStep': o.task.smallStep,
            if (o.task.repeat != RepeatUnit.none &&
                o.status == TaskStatus.pending &&
                o.snoozes == 0)
              'expiresAt': DateTime(
                o.originalDue.year,
                o.originalDue.month,
                o.originalDue.day + 1,
              ).millisecondsSinceEpoch,
          },
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
      'widget_snapshot',
      jsonEncode({
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'tasks': snapshot,
      }),
      );
    }
    try {
      await channel.invokeMethod<void>('update', {'tasks': snapshot});
    } on MissingPluginException {
      // The same worker can safely run in a headless engine.
    }
  }

  static ({String id, String action})? parseLaunch(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'hangeoreum' || uri.host != 'task') {
      return null;
    }
    final id = uri.queryParameters['id'];
    final action = uri.queryParameters['action'] ?? 'open';
    if (id == null ||
        id.isEmpty ||
        !{'open', 'start', 'snooze', 'complete'}.contains(action)) {
      return null;
    }
    return (id: id, action: action);
  }
}
