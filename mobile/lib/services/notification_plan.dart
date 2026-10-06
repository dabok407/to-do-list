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
        if (o.status == TaskStatus.paused) {
          // Keep future follow-ups even if the first snooze alert was already due.
          for (final minutes in [30, 60]) {
            final at = o.reminder.add(Duration(minutes: minutes));
            if (at.isAfter(now) && dayOf(at) == dayOf(o.reminder)) {
              jobs.add(
                ReminderJob(
                  key: '${o.id}:$minutes',
                  title: task.title,
                  body: '아까 하기로 한 일이 있어요. 5분만 시작해볼까요?',
                  payload: o.id,
                  at: at,
                ),
              );
            }
          }
        }
      }
    }
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
