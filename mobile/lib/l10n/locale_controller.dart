import 'dart:ui';

import 'package:flutter/foundation.dart';

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
  LocaleController(this.repository);
  String get preference => _preference;
  Locale get locale => _locale;

  static Locale resolve(String preference, Locale systemLocale) => Locale(
    preference == 'system'
        ? (systemLocale.languageCode == 'ko' ? 'ko' : 'en')
        : (preference == 'ko' ? 'ko' : 'en'),
  );

  Future<void> load({Locale? systemLocale}) async {
    final stored = await repository.setting(settingKey);
    _preference = {'system', 'ko', 'en'}.contains(stored) ? stored! : 'system';
    _apply(systemLocale);
  }

  Future<void> setPreference(String value, {Locale? systemLocale}) async {
    if (!{'system', 'ko', 'en'}.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Unsupported display language');
    }
    await repository.setSetting(settingKey, value);
    _preference = value;
    _apply(systemLocale);
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
