import '../data/task_repository.dart';
import '../l10n/app_strings.dart';

/// Read from SQLite for every scheduling pass so the foreground and OS
/// background isolates use the same preference after a restart.
class NotificationPrivacy {
  NotificationPrivacy(this.repository);

  static const settingKey = 'notification_show_titles';
  final TaskRepository repository;

  Future<bool> load() async {
    final value = await repository.setting(settingKey);
    // A missing preference is the documented initial default. An unexpected
    // stored value should not accidentally expose a previously hidden title.
    return value == null || value == 'true';
  }

  Future<void> setShowTitles(bool showTitles) =>
      repository.setSetting(settingKey, showTitles.toString());

  static ({String title, String body}) get hiddenContent => (
    title: AppStrings.current.brandName,
    body: AppStrings.current.isEnglish
        ? 'Open the app to see your scheduled task.'
        : '예정된 할 일을 확인해주세요.',
  );

  static ({String? title, String? body}) content({
    required bool showTitles,
    required String? title,
    required String? body,
  }) => showTitles ? (title: title, body: body) : hiddenContent;
}
