import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/app/task_controller.dart';
import 'package:hangeoreum/data/task_repository.dart';
import 'package:hangeoreum/features/notification_privacy_setting.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/services/notification_privacy.dart';
import 'package:hangeoreum/services/reminder_scheduler.dart';
import 'package:sqflite/sqflite.dart';

class _NoDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('This setting fixture only reads preferences');
}

class _Repository extends TaskRepository {
  final values = <String, String>{};
  _Repository() : super(_NoDatabase());
  @override
  Future<String?> setting(String key) async => values[key];
  @override
  Future<void> setSetting(String key, String value) async =>
      values[key] = value;
}

class _Controller extends TaskController {
  _Controller() : super(_Repository(), ReminderScheduler());
  // Represents a restored preference followed by the controller notification.
  // The real restore/lease path is covered by controller_backup_privacy_test.
  Future<void> publishRestoredPreference(bool show) async {
    await NotificationPrivacy(repository).setShowTitles(show);
    notifyListeners();
  }
}

void main() {
  Future<void> open(WidgetTester tester, TaskController controller) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationPrivacySetting(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SwitchListTile toggle(WidgetTester tester) => tester.widget<SwitchListTile>(
    find.byKey(const Key('notification-title-toggle')),
  );

  setUp(() => AppStrings.current = const AppStrings('ko'));

  testWidgets('mounted setting reflects privacy restored in both directions', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await controller.publishRestoredPreference(false);
    await open(tester, controller);
    expect(toggle(tester).value, isFalse);
    expect(find.text('제목 숨김 · 앱에서 내용을 확인해요'), findsOneWidget);
    await controller.publishRestoredPreference(true);
    await tester.pumpAndSettle();
    expect(toggle(tester).value, isTrue);
    expect(find.text('제목 표시 · 기본 설정'), findsOneWidget);
    await controller.publishRestoredPreference(false);
    await tester.pumpAndSettle();
    expect(toggle(tester).value, isFalse);
    expect(toggle(tester).onChanged, isNotNull);
  });

  testWidgets(
    'replacing or disposing settings detaches the old controller listener',
    (tester) async {
      final first = _Controller(), second = _Controller();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.publishRestoredPreference(false);
      await open(tester, first);
      expect(toggle(tester).value, isFalse);
      await open(tester, second);
      expect(toggle(tester).value, isTrue);
      await second.publishRestoredPreference(false);
      await tester.pumpAndSettle();
      expect(toggle(tester).value, isFalse);
      await first.publishRestoredPreference(true);
      await tester.pumpAndSettle();
      expect(toggle(tester).value, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await second.publishRestoredPreference(true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
