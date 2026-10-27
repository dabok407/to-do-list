/// Tomorrow's wall-clock time, preserving the task's scheduled hour/minute.
/// Calendar arithmetic (not +24h) preserves local time across DST changes.
DateTime tomorrowAtScheduledTime(DateTime due, DateTime now) {
  final localDue = due.toLocal();
  final localNow = now.toLocal();
  return DateTime(
    localNow.year,
    localNow.month,
    localNow.day + 1,
    localDue.hour,
    localDue.minute,
  );
}
