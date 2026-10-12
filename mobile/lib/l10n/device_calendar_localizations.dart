import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

/// Preserve the selected UI language's translations and date formats, while
/// every Material calendar (including date pickers) follows the device week.
class DeviceCalendarMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  final int firstDayOfWeekIndex;

  const DeviceCalendarMaterialDelegate({required this.firstDayOfWeekIndex})
    : assert(firstDayOfWeekIndex >= 0 && firstDayOfWeekIndex <= 6);

  @override
  bool isSupported(Locale locale) => {'ko', 'en'}.contains(locale.languageCode);

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    // The SDK delegate initializes the bundled intl symbols without networking.
    // Preserve its SynchronousFuture so an initialized locale does not introduce
    // an empty first frame when opening the app or a calendar route.
    return GlobalMaterialLocalizations.delegate.load(locale).then((_) {
      final formats = _CalendarFormats(locale.languageCode);
      return locale.languageCode == 'ko'
          ? _DeviceMaterialKo(formats, firstDayOfWeekIndex)
          : _DeviceMaterialEn(formats, firstDayOfWeekIndex);
    });
  }

  @override
  bool shouldReload(DeviceCalendarMaterialDelegate old) =>
      firstDayOfWeekIndex != old.firstDayOfWeekIndex;
}

class _CalendarFormats {
  final DateFormat fullYear;
  final DateFormat compactDate;
  final DateFormat shortDate;
  final DateFormat mediumDate;
  final DateFormat longDate;
  final DateFormat yearMonth;
  final DateFormat shortMonthDay;
  final NumberFormat decimal;
  final NumberFormat twoDigit;

  _CalendarFormats(String language)
    : fullYear = DateFormat.y(language),
      compactDate = DateFormat.yMd(language),
      shortDate = DateFormat.yMMMd(language),
      mediumDate = DateFormat.MMMEd(language),
      longDate = DateFormat.yMMMMEEEEd(language),
      yearMonth = DateFormat.yMMMM(language),
      shortMonthDay = DateFormat.MMMd(language),
      decimal = NumberFormat.decimalPattern(language),
      twoDigit = NumberFormat('00', language);
}

class _DeviceMaterialKo extends MaterialLocalizationKo {
  @override
  final int firstDayOfWeekIndex;

  _DeviceMaterialKo(_CalendarFormats f, this.firstDayOfWeekIndex)
    : super(
        fullYearFormat: f.fullYear,
        compactDateFormat: f.compactDate,
        shortDateFormat: f.shortDate,
        mediumDateFormat: f.mediumDate,
        longDateFormat: f.longDate,
        yearMonthFormat: f.yearMonth,
        shortMonthDayFormat: f.shortMonthDay,
        decimalFormat: f.decimal,
        twoDigitZeroPaddedFormat: f.twoDigit,
      );
}

class _DeviceMaterialEn extends MaterialLocalizationEn {
  @override
  final int firstDayOfWeekIndex;

  _DeviceMaterialEn(_CalendarFormats f, this.firstDayOfWeekIndex)
    : super(
        fullYearFormat: f.fullYear,
        compactDateFormat: f.compactDate,
        shortDateFormat: f.shortDate,
        mediumDateFormat: f.mediumDate,
        longDateFormat: f.longDate,
        yearMonthFormat: f.yearMonth,
        shortMonthDayFormat: f.shortMonthDay,
        decimalFormat: f.decimal,
        twoDigitZeroPaddedFormat: f.twoDigit,
      );
}
