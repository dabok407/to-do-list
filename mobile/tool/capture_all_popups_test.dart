// Opt-in full popup inventory capture with fictional, in-memory tasks only.
// From mobile/: ../.tools/flutter/bin/flutter.bat test
// tool/capture_all_popups_test.dart --dart-define=ALL_POPUPS_CAPTURE=true
// --reporter=expanded --concurrency=1
// These renders are not native-device screenshots or a deployed build.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/backup_screen.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart';
import 'package:hangeoreum/services/backup_service.dart';
import 'package:hangeoreum/services/backup_storage.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _output = String.fromEnvironment(
  'ALL_POPUPS_CAPTURE_OUTPUT',
  defaultValue: '../.tools/popup-consistency-2026-11-09',
);

/// This fixture never opens a system file picker or reads/writes a real backup.
/// The restore confirmation is cancelled in every scenario.
class _CaptureBackup extends BackupService {
  _CaptureBackup(PreviewController controller, this.snapshot)
    : super(controller.repository, storage: MemoryBackupStorage());
  final BackupSnapshot snapshot;
  @override
  Future<BackupStatus> loadStatus() async => BackupStatus(
    enabled: true,
    hasBackup: true,
    lastBackupAt: snapshot.createdAt,
  );
  @override
  Future<BackupSnapshot?> latestBackup() async => snapshot;
  @override
  Future<BackupSnapshot?> pickBackup() async => snapshot;
  @override
  Future<void> setAutomatic(bool enabled) async =>
      throw StateError('Capture cannot change backups');
  @override
  Future<BackupSnapshot> createBackup() async =>
      throw StateError('Capture cannot create backups');
  @override
  Future<bool> exportBackup() async =>
      throw StateError('Capture cannot export backups');
  @override
  Future<void> restore(BackupSnapshot snapshot) async =>
      throw StateError('Capture cannot restore backups');
}

Future<BackupSnapshot> _backupSnapshot(PreviewController controller) async {
  final tasks = await controller.repository.tasks();
  final payload = jsonEncode({
    'createdAt': DateTime.now()
        .subtract(const Duration(days: 1))
        .toUtc()
        .toIso8601String(),
    'data': {
      'tasks': tasks.map((task) => task.toMap()).toList(),
      'occurrences': [],
      'events': [],
      'recurrence_exceptions': [],
      'settings': [],
    },
  });
  return BackupSnapshot.parse(
    jsonEncode({
      'format': 'todoniq-backup',
      'version': 1,
      'payload': payload,
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
    }),
  );
}

class _PaidCaptureSubscription extends SubscriptionService {
  _PaidCaptureSubscription() {
    active = true;
    available = true;
  }

  @override
  Future<void> refresh() async {}
  @override
  Future<void> purchase() async => throw StateError('Render-only fixture');
  @override
  Future<void> restore() async => throw StateError('Render-only fixture');
  @override
  Future<void> manage() async => throw StateError('Render-only fixture');
}

Future<PreviewController> _fixture(String language) async {
  final controller = PreviewController(sampleLanguage: language);
  await controller.localeController.setPreference(language);
  await controller.refresh();
  for (final task in await controller.repository.tasks()) {
    await controller.deleteOccurrence(
      Occurrence(
        id: '${task.id}@${task.due.toIso8601String()}',
        task: task,
        originalDue: task.due,
        reminder: task.due,
      ),
      scope: 'series',
    );
  }
  final now = DateTime.now();
  DateTime at(int days, int hour, [int minute = 0]) =>
      DateTime(now.year, now.month, now.day + days, hour, minute);
  await controller.save(
    Task(
      id: 'popup-repeat',
      title: language == 'ko' ? '가볍게 스트레칭' : 'A few minutes of stretching',
      due: at(0, 23, 30),
      created: now,
      category: '건강',
      priority: 1,
      repeat: RepeatUnit.daily,
      end: at(1, 23, 59),
      note: language == 'ko'
          ? '편한 자세에서 천천히 시작하기'
          : 'Start slowly and comfortably',
    ),
  );
  await controller.save(
    Task(
      id: 'popup-clean',
      title: language == 'ko'
          ? '에어컨 필터 청소'
          : 'Clean the air conditioner filter',
      due: at(0, 21),
      created: now,
      category: '생활',
      priority: 1,
    ),
  );
  await controller.refresh();
  await controller.save(
    Task(
      id: 'popup-overdue',
      title: language == 'ko' ? '택배 상자 정리' : 'Tidy the delivery boxes',
      due: at(-1, 18),
      created: now,
      category: '생활',
    ),
  );
  await controller.act(
    controller.items.firstWhere((o) => o.task.id == 'popup-overdue'),
    'uncomplete',
  );
  await controller.save(
    Task(
      id: 'popup-completed',
      title: language == 'ko' ? '읽은 책 기록' : 'Write a reading note',
      due: at(0, 8),
      created: now,
      category: '배움',
    ),
  );
  await controller.act(
    controller.items.firstWhere((o) => o.task.id == 'popup-completed'),
    'complete',
  );
  return controller;
}

void main() {
  if (!const bool.fromEnvironment('ALL_POPUPS_CAPTURE')) {
    test(
      'Full popup inventory screenshots require explicit opt-in',
      () {},
      skip: true,
    );
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  const configurations = [
    (width: 375.0, language: 'ko', scale: 1.0),
    (width: 320.0, language: 'en', scale: 2.0),
  ];
  for (final configuration in configurations) {
    final tag =
        '${configuration.width.toInt()}-${configuration.language}-${configuration.scale.toString().replaceAll('.0', '')}x';
    testWidgets('all actual popup surfaces fit and render $tag', (
      tester,
    ) async {
      // This opt-in tool is a Flutter test using isolated in-memory preferences.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = Size(configuration.width * 2, 1624);
      tester.view.padding = const FakeViewPadding(top: 100, bottom: 68);
      tester.platformDispatcher.textScaleFactorTestValue = configuration.scale;
      final previousPlatform = debugDefaultTargetPlatformOverride;
      final previousShadows = debugDisableShadows;
      final previousStrings = AppStrings.current;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      debugDisableShadows = false;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);
      addTearDown(() => debugDisableShadows = previousShadows);
      addTearDown(() => AppStrings.current = previousStrings);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(WidgetService.channel, (call) async {
        return call.method == 'getCalendarPreferences'
            ? {'regionCode': 'KR', 'firstDayOfWeek': 0}
            : null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(WidgetService.channel, null),
      );

      final controller = await _fixture(configuration.language);
      final subscription = _PaidCaptureSubscription();
      final strings = AppStrings(configuration.language);
      addTearDown(controller.dispose);
      addTearDown(subscription.dispose);
      final boundary = GlobalKey();
      final scenes = <Map<String, Object?>>[];

      try {
        Future<void> mount(int page) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: HangeoreumApp(
                controller: controller,
                subscription: subscription,
                initialPage: page,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$tag initial page $page',
          );
        }

        Future<void> tap(Finder finder, {bool settle = true}) async {
          if (finder.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              finder,
              220,
              scrollable: find.byType(Scrollable).last,
              maxScrolls: 70,
            );
          }
          expect(finder, findsOneWidget);
          await tester.ensureVisible(finder);
          await tester.pump(const Duration(milliseconds: 20));
          expect(finder.hitTestable(), findsOneWidget);
          await tester.tap(finder);
          if (settle) {
            await tester.pumpAndSettle();
          } else {
            await tester.pump(const Duration(milliseconds: 350));
          }
        }

        Future<void> capture(String name) async {
          // Backup confirmation leaves a busy spinner in the covered route.
          // A bounded frame pump allows that real state without waiting forever.
          await tester.pump(const Duration(milliseconds: 350));
          expect(tester.takeException(), isNull, reason: '$tag $name layout');
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('$_output/$tag/$name.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
            } finally {
              image.dispose();
            }
          });
          scenes.add({
            'file': '$name.png',
            'surface': name,
            'render': 'actual-production-Flutter-widgets',
            'data': 'fictional in-memory fixtures',
            'nativeDeviceScreenshot': false,
            'logicalWidth': configuration.width,
            'logicalHeight': 812,
            'textScale': configuration.scale,
            'language': configuration.language,
          });
        }

        Future<void> openEditor() async {
          await mount(1);
          await tap(find.byType(FloatingActionButton));
        }

        Future<void> closeOverlay() async {
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await tester.pumpAndSettle();
        }

        Future<void> openTask(String taskId) async {
          await mount(taskId == 'popup-completed' ? 2 : 1);
          final item = controller.items.firstWhere((o) => o.task.id == taskId);
          await tap(find.byKey(ValueKey('task-row-${item.id}')));
        }

        Future<void> selectRepeat(String label) async {
          await tap(find.byKey(const Key('editor-repeat')));
          await tap(find.text(strings.t(label)).last);
        }

        final originalTaskCount = (await controller.repository.tasks()).length;
        await mount(0);
        await tap(find.byKey(const Key('quick-add')));
        final quickTitle = find.byKey(const Key('quick-add-title'));
        await tester.ensureVisible(quickTitle);
        await tester.enterText(
          quickTitle,
          configuration.language == 'ko'
              ? '에어컨 필터 청소'
              : 'Clean the air conditioner filter',
        );
        await tester.pumpAndSettle();
        await capture('01-quick-add');
        await tap(find.byKey(const Key('quick-add-time')));
        await capture('02-time-wheel');
        await tap(find.byTooltip(strings.t('취소')));
        // Duplicate confirmation keeps the covered quick-add action busy.
        await tap(find.byKey(const Key('quick-add-submit')), settle: false);
        expect(find.text(strings.t('중복된 내용입니다.')), findsOneWidget);
        await capture('03-duplicate-confirm');
        await tap(find.text(strings.t('취소')));
        expect((await controller.repository.tasks()).length, originalTaskCount);

        await openEditor();
        await tap(find.byKey(const Key('editor-date')));
        await capture('04-date-calendar');
        await tap(find.byKey(const Key('date-picker-entry-toggle')));
        await capture('05-date-input');
        final input = find.descendant(
          of: find.byKey(const Key('date-picker-input')),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(input, 'invalid');
        await tap(find.byKey(const Key('picker-confirm')));
        expect(find.byKey(const Key('date-picker-input')), findsOneWidget);
        await capture('06-date-error');
        await tap(find.byTooltip(strings.t('취소')));

        await openTask('popup-repeat');
        await capture('07-task-detail');
        await tap(find.text(strings.t('수정')));
        await tap(find.text(strings.t('이번 일정만')));
        await capture('08-repeat-scope');
        await tap(find.text(strings.t('취소')));
        await openTask('popup-repeat');
        await tap(find.text(strings.t('삭제')));
        await capture('09-delete-repeat');
        await tap(find.text(strings.t('취소')));
        expect((await controller.repository.tasks()).length, originalTaskCount);
        await openTask('popup-clean');
        await tap(find.text(strings.t('삭제')));
        await capture('10-delete-single');
        await tap(find.text(strings.t('취소')));
        expect((await controller.repository.tasks()).length, originalTaskCount);
        await openTask('popup-completed');
        await capture('11-completed-detail');

        await mount(0);
        await tap(find.byKey(const Key('overdue-banner')));
        await capture('12-overdue-list');

        await mount(4);
        await tap(find.byKey(const Key('language-setting')));
        await capture('13-language');
        await tap(find.byTooltip(strings.t('닫기')));
        await tap(find.byKey(const Key('notification-settings')));
        await capture('14-notifications');
        await tap(find.byTooltip(strings.t('닫기')));
        await tap(find.byKey(const Key('privacy-details')));
        await capture('15-privacy');
        await tap(find.byTooltip(strings.t('닫기')));

        await mount(4);
        await tap(find.text(strings.t('투두닉 Pro 이용 중')));
        await tap(find.text(strings.t('이용약관·개인정보 안내')));
        await capture('16-pro-terms');
        await tap(find.text(strings.t('닫기')));

        await mount(4);
        final backup = _CaptureBackup(
          controller,
          await _backupSnapshot(controller),
        );
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    BackupScreen(controller: controller, service: backup),
              ),
            );
        await tester.pumpAndSettle();
        await tap(find.text(strings.t('기기의 최신 백업으로 복원')), settle: false);
        expect(find.text(strings.t('이 백업으로 복원할까요?')), findsOneWidget);
        await capture('17-backup-restore');
        await tap(find.text(strings.t('취소')));
        expect((await controller.repository.tasks()).length, originalTaskCount);
        // Also exercise the file-import entry with a memory-only picker result.
        await tap(find.text(strings.t('파일에서 복원')), settle: false);
        expect(find.text(strings.t('이 백업으로 복원할까요?')), findsOneWidget);
        await tap(find.text(strings.t('취소')));
        expect((await controller.repository.tasks()).length, originalTaskCount);

        await mount(0);
        await tap(find.byTooltip(strings.t('요약 기간')));
        await capture('18-calendar-summary');

        await mount(1);
        await tap(find.byKey(const Key('task-sort-menu-upcoming')));
        expect(
          find.byKey(const Key('task-sort-option-latest')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('task-sort-option-oldest')),
          findsOneWidget,
        );
        await capture('19-sort-upcoming');
        await mount(2);
        await tap(find.byKey(const Key('task-sort-menu-completed')));
        await capture('20-sort-completed');

        await openEditor();
        final overdueHeader = find
            .descendant(
              of: find.byKey(const Key('overdue-settings')),
              matching: find.byType(InkWell),
            )
            .first;
        await tap(overdueHeader);
        await tap(find.byKey(const Key('overdue-interval')));
        await capture('21-overdue-interval');
        await closeOverlay();
        await tap(find.byKey(const Key('editor-repeat')));
        await capture('22-repeat-type');
        await tap(find.text(strings.t('요일 자유 · 주 N회')).last);
        await tap(find.byKey(const Key('editor-weekly-goal')));
        await capture('23-weekly-goal');
        await closeOverlay();
        await selectRepeat('매월 특정 번째 요일');
        await tap(find.byKey(const Key('editor-month-week')));
        await capture('24-monthly-order');
        await closeOverlay();
        await tap(find.byKey(const Key('editor-end-date')));
        await capture('25-repeat-end-date');

        await mount(3);
        await tap(find.byKey(const Key('statistics-period-select')));
        final rangeDialog = find.byType(DateRangePickerDialog);
        expect(rangeDialog, findsOneWidget);
        await capture('26-statistics-period');
        final material = MaterialLocalizations.of(tester.element(rangeDialog));
        await tap(find.byTooltip(material.inputDateModeButtonLabel));
        await capture('27-statistics-period-input');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final file = File('$_output/$tag/manifest.json');
          await file.writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'capturedAt': DateTime.now().toUtc().toIso8601String(),
              'device': tag,
              'scenes': scenes,
            }),
            flush: true,
          );
        });
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
        debugDisableShadows = previousShadows;
      }
    });
  }
}
