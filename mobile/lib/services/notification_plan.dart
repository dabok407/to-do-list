import '../domain/task.dart';

enum NotificationRepeat { daily, weekly, monthly }

class ReminderJob {
  final String key, title, body, payload;
  final DateTime at;
  final NotificationRepeat? repeat;
  const ReminderJob({
    required this.key,
    required this.title,
    required this.body,
    required this.payload,
    required this.at,
    this.repeat,
  });
}

class NotificationPlan {
  final List<ReminderJob> jobs;
  final int deferred;
  final DateTime? coveredThrough;
  NotificationPlan(this.jobs, this.deferred, this.coveredThrough);

  static NotificationPlan build(
    List<Occurrence> items, {
    required DateTime now,
    required int capacity,
    DateTime? until,
    Map<String, List<DateTime>> exceptions = const {},
  }) {
    final jobs = <ReminderJob>[];
    final groups = <String, List<Occurrence>>{};
    for (final o in items) {
      (groups[o.task.id] ??= []).add(o);
    }
    for (final occurrences in groups.values) {
      final task = occurrences.first.task;
      final simple =
          until == null &&
          task.end == null &&
          task.interval == 1 &&
          !(exceptions[task.id] ?? []).any((d) => d.isAfter(now)) &&
          !occurrences.any(
            (o) => o.originalDue.isAfter(now) && o.status != TaskStatus.pending,
          ) &&
          (task.repeat == RepeatUnit.daily ||
              task.repeat == RepeatUnit.weekly ||
              (task.repeat == RepeatUnit.monthly && task.due.day <= 28));
      final untouched = occurrences.where(
        (o) => o.status == TaskStatus.pending && o.snoozes == 0,
      );
      // Completed/edited future dates must not be resurrected by a calendar trigger.
      var boundary = now;
      if (simple) {
        for (final o in occurrences.where((o) => !untouched.contains(o))) {
          if (o.originalDue.isAfter(boundary)) boundary = o.originalDue;
        }
      }
      final repeatCandidates =
          untouched.where((o) => o.reminder.isAfter(boundary)).toList()
            ..sort((a, b) => a.reminder.compareTo(b.reminder));
      final compressedDays = <int>{};
      if (simple) {
        for (final o in repeatCandidates) {
          final bucket = task.repeat == RepeatUnit.weekly
              ? o.originalDue.weekday
              : 0;
          if (compressedDays.contains(bucket)) continue;
          // UNCalendarNotificationTrigger has no delayed-start date for a repeating
          // hour/weekday/monthday trigger. Never notify before a future start.
          var next = DateTime(
            now.year,
            now.month,
            now.day,
            task.due.hour,
            task.due.minute,
          );
          if (task.repeat == RepeatUnit.weekly) {
            next = DateTime(
              now.year,
              now.month,
              now.day + (bucket - now.weekday + 7) % 7,
              task.due.hour,
              task.due.minute,
            );
          }
          if (task.repeat == RepeatUnit.monthly) {
            next = DateTime(
              now.year,
              now.month,
              task.due.day,
              task.due.hour,
              task.due.minute,
            );
          }
          if (!next.isAfter(now)) {
            next = task.repeat == RepeatUnit.monthly
                ? DateTime(
                    now.year,
                    now.month + 1,
                    task.due.day,
                    task.due.hour,
                    task.due.minute,
                  )
                : DateTime(
                    next.year,
                    next.month,
                    next.day + (task.repeat == RepeatUnit.weekly ? 7 : 1),
                    next.hour,
                    next.minute,
                  );
          }
          if (o.reminder != next) continue;
          compressedDays.add(bucket);
          jobs.add(
            ReminderJob(
              key: 'repeat:${task.id}:$bucket',
              title: task.title,
              body: '지금 시작해볼까요?',
              payload: 'repeat:${Uri.encodeComponent(task.id)}:$bucket',
              at: o.reminder,
              repeat: task.repeat == RepeatUnit.daily
                  ? NotificationRepeat.daily
                  : task.repeat == RepeatUnit.weekly
                  ? NotificationRepeat.weekly
                  : NotificationRepeat.monthly,
            ),
          );
        }
      }
      for (final o in occurrences.where((o) => o.active)) {
        if (task.repeat == RepeatUnit.weeklyGoal &&
            dayOf(o.originalDue).isBefore(dayOf(now))) {
          continue;
        }
        if (simple &&
            compressedDays.contains(
              task.repeat == RepeatUnit.weekly ? o.originalDue.weekday : 0,
            ) &&
            o.status == TaskStatus.pending &&
            o.snoozes == 0 &&
            o.reminder.isAfter(boundary)) {
          continue;
        }
        final body = o.status == TaskStatus.progressing
            ? '진행은 어떤가요? 완료했거나 잠시 쉬어도 괜찮아요.'
            : o.status == TaskStatus.paused
            ? '아까 하기로 했어요. 지금 시작해볼까요?'
            : '지금 시작해볼까요?';
        if (o.reminder.isAfter(now)) {
          jobs.add(
            ReminderJob(
              key: o.id,
              title: task.title,
              body: body,
              payload: o.id,
              at: o.reminder,
            ),
          );
        }
      }
    }
    // A postponed alert is an explicit choice, not permission for extra 30/60m nags.
    // Pre-book future follow-ups so delivery does not depend on opening the app.
    // Once a one-off deadline is past, a safe daily/weekly OS trigger can persist.
    for (final occurrences in groups.values) {
      final candidates = <DateTime, Occurrence>{};
      final task = occurrences.first.task;
      if (task.overdueDays <= 0) continue;
      final interval = task.overdueDays;
      for (final o in occurrences.where((o) => o.active)) {
        if (task.repeat == RepeatUnit.weeklyGoal &&
            dayOf(o.originalDue).isBefore(dayOf(now))) {
          continue;
        }
        final minute =
            task.overdueMinute ??
            o.originalDue.hour * 60 + o.originalDue.minute;
        final elapsedDays = DateTime.utc(now.year, now.month, now.day)
            .difference(
              DateTime.utc(
                o.originalDue.year,
                o.originalDue.month,
                o.originalDue.day,
              ),
            )
            .inDays;
        var step = elapsedDays > 0
            ? (elapsedDays ~/ interval).clamp(1, 1000000)
            : 1;
        var emitted = 0;
        // Skip an explicit snooze in calendar days rather than iterating minute by minute.
        if (o.reminder.isAfter(now)) {
          final heldDays =
              DateTime.utc(o.reminder.year, o.reminder.month, o.reminder.day)
                  .difference(
                    DateTime.utc(
                      o.originalDue.year,
                      o.originalDue.month,
                      o.originalDue.day,
                    ),
                  )
                  .inDays;
          if (heldDays ~/ interval > step) step = heldDays ~/ interval;
        }
        while (emitted < 32) {
          final at = DateTime(
            o.originalDue.year,
            o.originalDue.month,
            o.originalDue.day + step * interval,
            minute ~/ 60,
            minute % 60,
          );
          step++;
          if (!at.isAfter(now) || !at.isAfter(o.reminder)) continue;
          // Weekly flexible goals are invitations only within their current week.
          if (task.repeat == RepeatUnit.weeklyGoal &&
              weekOf(at) != weekOf(o.originalDue)) {
            break;
          }
          final previous = candidates[at];
          if (previous == null || o.originalDue.isAfter(previous.originalDue)) {
            candidates[at] = o;
          }
          emitted++;
        }
      }
      final times = candidates.keys.toList()..sort();
      for (final at in times) {
        final o = candidates[at]!;
        // One task needs only one banner at a clock time, even with old missed recurrences.
        if (occurrences.any((row) => row.active && row.reminder == at)) {
          continue;
        }
        NotificationRepeat? repeat;
        if (until == null &&
            task.repeat == RepeatUnit.none &&
            (interval == 1 || interval == 7)) {
          var nearest = DateTime(
            now.year,
            now.month,
            now.day,
            at.hour,
            at.minute,
          );
          if (interval == 7) {
            nearest = DateTime(
              now.year,
              now.month,
              now.day + (at.weekday - now.weekday + 7) % 7,
              at.hour,
              at.minute,
            );
          }
          if (!nearest.isAfter(now)) {
            nearest = DateTime(
              nearest.year,
              nearest.month,
              nearest.day + interval,
              nearest.hour,
              nearest.minute,
            );
          }
          // iOS calendar repeats cannot have a deferred start. Do not schedule early.
          if (nearest == at) {
            repeat = interval == 1
                ? NotificationRepeat.daily
                : NotificationRepeat.weekly;
          }
        }
        jobs.add(
          ReminderJob(
            key: 'overdue:${o.id}:${repeat == null ? dayKey(at) : 'repeat'}',
            title: task.title,
            body: '아직 완료하지 않은 일이 있어요. 지금 시작하거나 시간을 바꿔볼까요?',
            payload: o.id,
            at: at,
            repeat: repeat,
          ),
        );
        if (repeat != null) break;
      }
    }
    if (until != null) jobs.removeWhere((job) => !job.at.isBefore(until));
    jobs.sort((a, b) => a.at.compareTo(b.at));
    final selected = jobs.take(capacity).toList();
    final oneShots = selected.where((j) => j.repeat == null).toList();
    return NotificationPlan(
      selected,
      jobs.length - selected.length,
      oneShots.isEmpty ? null : oneShots.last.at,
    );
  }
}
