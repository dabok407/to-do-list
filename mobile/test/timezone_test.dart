import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:hangeoreum/services/reminder_scheduler.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);
  test('iOS GMT 식별자에서도 미래 알림 시간을 구성할 수 있다', () {
    final zone = ReminderScheduler.resolveTimeZone('GMT');
    final due = tz.TZDateTime(zone, 2026, 10, 8, 19);
    expect(due.toUtc(), DateTime.utc(2026, 10, 8, 19));
  });
  test('지역 시간대는 일광 절약 시간 규칙을 유지한다', () {
    final zone = ReminderScheduler.resolveTimeZone('America/New_York');
    expect(
      tz.TZDateTime(zone, 2026, 1, 8, 19).timeZoneOffset,
      const Duration(hours: -5),
    );
    expect(
      tz.TZDateTime(zone, 2026, 7, 8, 19).timeZoneOffset,
      const Duration(hours: -4),
    );
  });
}
