import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import 'core_catalog.dart';
import 'home_catalog.dart';
import 'editor_catalog.dart';

/// UI copy only. Task titles, notes and stored category identifiers are never
/// changed when the user switches the display language.
class AppStrings {
  final String languageCode;
  const AppStrings(this.languageCode);

  static AppStrings current = const AppStrings('ko');
  static String get appName => current.brandName;
  bool get isEnglish => languageCode == 'en';
  String get brandName => isEnglish ? 'Todoniq' : '투두닉';
  String get slogan => isEnglish ? 'Your tasks. Your way.' : '나만의 할 일, 투두닉';
  static final english = <String, String>{
    ...coreEnglish,
    ...homeEnglish,
    ...editorEnglish,
  };

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings) ?? current;
  }

  static const delegate = _AppStringsDelegate();

  String t(String key, {Map<String, Object> args = const {}}) {
    var value = isEnglish ? english[key] ?? key : key;
    for (final entry in args.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value.toString());
    }
    return value;
  }

  String category(String key) =>
      const {'생활', '업무', '운동', '공부', '건강', '배움', '기타'}.contains(key)
      ? t(key)
      : key;
  String date(DateTime value) => isEnglish
      ? '${value.month}/${value.day}/${value.year}'
      : '${value.year}-${_two(value.month)}-${_two(value.day)}';
  String time(DateTime value) => isEnglish
      ? '${value.hour % 12 == 0 ? 12 : value.hour % 12}:${_two(value.minute)} ${value.hour >= 12 ? 'PM' : 'AM'}'
      : '${_two(value.hour)}:${_two(value.minute)}';
  String month(DateTime value, {bool short = false}) => isEnglish
      ? '${(short ? _monthsShort : _months)[value.month - 1]} ${value.year}'
      : '${value.year}년 ${value.month}월';
  String dateShort(DateTime value) => isEnglish
      ? '${_monthsShort[value.month - 1]} ${value.day}'
      : '${value.month}월 ${value.day}일';
  String weekday(int day, {bool short = true}) => isEnglish
      ? (short ? _weekdaysShort : _weekdays)[(day - 1) % 7]
      : '${_koreanWeekdays[(day - 1) % 7]}${short ? '' : '요일'}';
  String dayLabel(DateTime value, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final distance = DateTime.utc(
      value.year,
      value.month,
      value.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    if (distance == 0) return t('오늘');
    if (distance == 1) return t('내일');
    if (distance == -1) return t('어제');
    return isEnglish
        ? '${_monthsShort[value.month - 1]} ${value.day}'
        : '${value.month}월 ${value.day}일';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _weekdaysShort = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const _koreanWeekdays = ['월', '화', '수', '목', '금', '토', '일'];
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();
  @override
  bool isSupported(Locale locale) => {'ko', 'en'}.contains(locale.languageCode);
  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture(AppStrings(locale.languageCode));
  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
