import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/task_repository.dart';
import 'app_strings.dart';

/// The same persisted preference is read by the UI and headless reminder worker.
class LocaleController extends ChangeNotifier {
  static const settingKey = 'display_language';

  /// Mirrors the preference loaded for the current UI or headless engine.
  /// Widgets need the choice itself so System can follow an OS language change.
  static String currentPreference = 'system';
  final TaskRepository repository;
  String _preference = 'system';
  Locale _locale = const Locale('ko');
  String _regionCode = '';
  int _firstDayOfWeekIndex = 1;
  int _calendarRefreshGeneration = 0;
  bool _disposed = false;
  static const _deviceCalendar = MethodChannel(
    'com.dabok407.hangeoreum/widget',
  );
  LocaleController(this.repository);
  String get preference => _preference;
  Locale get locale => _locale;
  String get regionCode => _regionCode;
  int get firstDayOfWeekIndex => _firstDayOfWeekIndex;

  static Locale resolve(String preference, Locale systemLocale) => Locale(
    preference == 'system'
        ? (systemLocale.languageCode == 'ko' ? 'ko' : 'en')
        : (preference == 'ko' ? 'ko' : 'en'),
  );

  Future<void> load({Locale? systemLocale}) async {
    final stored = await repository.setting(settingKey);
    _preference = {'system', 'ko', 'en'}.contains(stored) ? stored! : 'system';
    _apply(systemLocale);
    await refreshCalendarPreferences(systemLocale: systemLocale);
  }

  Future<void> setPreference(String value, {Locale? systemLocale}) async {
    if (!{'system', 'ko', 'en'}.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Unsupported display language');
    }
    await repository.setSetting(settingKey, value);
    _preference = value;
    _apply(systemLocale);
    await refreshCalendarPreferences(systemLocale: systemLocale);
  }

  /// Calendar layout follows the device's region/calendar preference, rather
  /// than the app's selected display language. No location access is involved.
  Future<void> refreshCalendarPreferences({Locale? systemLocale}) async {
    final generation = ++_calendarRefreshGeneration;
    final deviceLocale = systemLocale ?? PlatformDispatcher.instance.locale;
    var region = _validRegion(deviceLocale.countryCode);
    int? firstDay;
    try {
      final result = await _deviceCalendar.invokeMethod<Object?>(
        'getCalendarPreferences',
      );
      if (result is Map) {
        final nativeRegion = _validRegion(result['regionCode']);
        if (nativeRegion.isNotEmpty) region = nativeRegion;
        final nativeFirstDay = result['firstDayOfWeek'];
        if (nativeFirstDay is int &&
            nativeFirstDay >= 0 &&
            nativeFirstDay <= 6) {
          firstDay = nativeFirstDay;
        }
      }
    } on MissingPluginException {
      // Browser previews and headless engines may not have the UI channel.
    } on PlatformException {
      // A failed native read must not prevent local tasks from opening.
    }
    if (_disposed || generation != _calendarRefreshGeneration) return;
    final resolvedFirstDay = firstDay ?? _regionalFirstDay(region);
    if (_regionCode == region && _firstDayOfWeekIndex == resolvedFirstDay) {
      return;
    }
    _regionCode = region;
    _firstDayOfWeekIndex = resolvedFirstDay;
    notifyListeners();
  }

  static String _validRegion(Object? value) {
    if (value is! String) return '';
    final region = value.trim().toUpperCase();
    return RegExp(r'^(?:[A-Z]{2}|[0-9]{3})$').hasMatch(region) ? region : '';
  }

  static int _regionalFirstDay(String region) {
    // CLDR weekData fallback for environments without the native channel.
    // Native OS preferences, including a user override, take priority above.
    const sunday = {
      'AG',
      'AS',
      'BD',
      'BR',
      'BS',
      'BT',
      'BW',
      'BZ',
      'CA',
      'CO',
      'DM',
      'DO',
      'ET',
      'GT',
      'GU',
      'HK',
      'HN',
      'ID',
      'IL',
      'IN',
      'IS',
      'JM',
      'JP',
      'KE',
      'KH',
      'KR',
      'LA',
      'MH',
      'MM',
      'MO',
      'MT',
      'MX',
      'MZ',
      'NI',
      'NP',
      'PA',
      'PE',
      'PH',
      'PK',
      'PR',
      'PT',
      'PY',
      'SA',
      'SG',
      'SV',
      'TH',
      'TT',
      'TW',
      'UM',
      'US',
      'VE',
      'VI',
      'WS',
      'YE',
      'ZA',
      'ZW',
    };
    const saturday = {
      'AF',
      'BH',
      'DJ',
      'DZ',
      'EG',
      'IQ',
      'IR',
      'JO',
      'KW',
      'LY',
      'OM',
      'QA',
      'SD',
      'SY',
    };
    if (sunday.contains(region)) return 0;
    if (saturday.contains(region)) return 6;
    if (region == 'MV') return 5;
    return 1;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _apply(Locale? systemLocale) {
    currentPreference = _preference;
    _locale = resolve(
      _preference,
      systemLocale ?? PlatformDispatcher.instance.locale,
    );
    AppStrings.current = AppStrings(_locale.languageCode);
    notifyListeners();
  }
}
