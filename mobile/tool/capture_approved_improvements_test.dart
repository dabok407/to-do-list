// Opt-in approved-improvements capture. Uses current production widgets and
// fictional PreviewController data. This is not a native device screenshot,
// store artwork, real purchase, notification delivery, or personal task data.
// flutter test tool/capture_approved_improvements_test.dart
//   --dart-define=APPROVED_IMPROVEMENTS_CAPTURE=true --reporter=expanded
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
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/backup_service.dart';
import 'package:hangeoreum/services/backup_storage.dart';
import 'package:hangeoreum/services/widget_service.dart';

const _enabled = bool.fromEnvironment('APPROVED_IMPROVEMENTS_CAPTURE');
const _outputRoot = String.fromEnvironment(
  'APPROVED_CAPTURE_OUTPUT',
  defaultValue: '../.tools/approved-improvements-2026-10-26/captures',
);
const _ratio = 2.0;
const _devices = [
  (name: 'mini', size: Size(375, 812), top: 50.0),
  (name: 'pro', size: Size(402, 874), top: 62.0),
];
final _date = DateTime(2026, 10, 26);
final _endOfFixtureWindow = DateTime(2026, 10, 31, 23, 59);
final _scenes = <Map<String, Object?>>[];

/// Rendering-only status fixture: no backup creation, restore, file picker,
/// export, or automatic task is performed by these screenshots.
class _ReadOnlyBackupFixture extends BackupService {
  _ReadOnlyBackupFixture(_BaselineController controller)
    : super(controller.repository, storage: MemoryBackupStorage());
  @override
  Future<BackupStatus> loadStatus() async => BackupStatus(
    enabled: true,
    hasBackup: true,
    lastBackupAt: DateTime(2026, 10, 26, 9),
  );
  @override
  Future<void> setAutomatic(bool enabled) async =>
      throw StateError('Capture cannot change backup settings');
  @override
  Future<BackupSnapshot> createBackup() async =>
      throw StateError('Capture cannot create a backup');
  @override
  Future<bool> exportBackup() async =>
      throw StateError('Capture cannot export a backup');
  @override
  Future<BackupSnapshot?> pickBackup() async =>
      throw StateError('Capture cannot import a backup');
  @override
  Future<BackupSnapshot?> latestBackup() async =>
      throw StateError('Capture cannot read a real backup');
  @override
  Future<void> restore(BackupSnapshot snapshot) async =>
      throw StateError('Capture cannot restore a backup');
}

class _PaidSubscription extends SubscriptionService {
  _PaidSubscription() {
    active = true;
    available = true;
  }

  @override
  Future<void> refresh() async {}
  @override
  Future<void> purchase() async => throw StateError('Capture cannot purchase');
  @override
  Future<void> restore() async => throw StateError('Capture cannot restore');
  @override
  Future<void> manage() async => throw StateError('Capture cannot manage');
}

class _BaselineController extends PreviewController {
  _BaselineController() : super(sampleLanguage: 'ko');
  @override
  Future<void> refresh({DateTime? through}) =>
      super.refresh(through: _endOfFixtureWindow);
}

Future<_BaselineController> _fixture({bool empty = false}) async {
  final controller = _BaselineController();
  await controller.localeController.setPreference('ko');
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
  if (!empty) {
    await controller.save(
      Task(
        id: 'sample-4',
        title: '에어컨 필터 청소',
        due: DateTime(2026, 10, 27, 12),
        created: _date,
        category: '생활',
        priority: 1,
        note: '필터를 세척한 뒤 완전히 말리기',
        smallStep: '필터 덮개부터 열어보기',
      ),
    );
    await controller.save(
      Task(
        id: 'review-biweekly-work',
        title: '이번 주 업무 정리',
        due: DateTime(2026, 10, 30, 12),
        created: _date,
        category: '업무',
        priority: 1,
        repeat: RepeatUnit.weekly,
        interval: 2,
        weekdays: const [DateTime.friday],
        note: '진행한 업무와 다음 주 할 일을 정리하기',
      ),
    );
  }
  await controller.refresh();
  return controller;
}

List<String> _visibleText(WidgetTester tester, Size size) {
  final values = <String>[];
  final viewport = Offset.zero & size;
  bool visible(Element element) {
    final render = element.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      return false;
    }
    return (render.localToGlobal(Offset.zero) & render.size).overlaps(viewport);
  }

  for (final element in find.byType(Text).evaluate()) {
    if (!visible(element)) continue;
    final widget = element.widget as Text;
    final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (text.isNotEmpty) values.add(text);
  }
  for (final element in find.byType(EditableText).evaluate()) {
    if (!visible(element)) continue;
    final text = (element.widget as EditableText).controller.text;
    if (text.isNotEmpty) values.add(text);
  }
  return values;
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  ({String name, Size size, double top}) device,
  String scene,
) async {
  await tester.pumpAndSettle();
  expect(
    tester.takeException(),
    isNull,
    reason: '${device.name}/$scene layout',
  );
  final text = _visibleText(tester, device.size);
  final filename = '${device.name}-approved-$scene.png';
  late String hash;
  late int bytes;
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _ratio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(data, isNotNull);
      final png = data!.buffer.asUint8List();
      bytes = png.length;
      hash = sha256.convert(png).toString();
      final file = File('$_outputRoot/$filename');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png, flush: true);
    } finally {
      image.dispose();
    }
  });
  _scenes.add({
    'file': filename,
    'scene': scene,
    'variant': 'approved-implementation',
    'device': device.name,
    'logical_width': device.size.width.toInt(),
    'logical_height': device.size.height.toInt(),
    'png_width': (device.size.width * _ratio).toInt(),
    'png_height': (device.size.height * _ratio).toInt(),
    'safe_area': {'top': device.top, 'bottom': 34},
    'pixel_ratio': _ratio,
    'bytes': bytes,
    'sha256': hash,
    'rendered_text': text,
    'captured_at': DateTime.now().toUtc().toIso8601String(),
  });
}

Future<void> _showDetail(WidgetTester tester, String title) async {
  final row = find.text(title).first;
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

void main() {
  if (!_enabled) {
    test('Approved capture requires explicit opt-in', () {}, skip: true);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(WidgetService.channel, (call) async {
      if (call.method == 'getCalendarPreferences') {
        return {'regionCode': 'KR', 'firstDayOfWeek': 0};
      }
      throw MissingPluginException(
        'Native services are outside review capture',
      );
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(WidgetService.channel, null),
  );
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final device in _devices) {
    testWidgets('${device.name} actual approved production scenes', (
      tester,
    ) async {
      tester.view.devicePixelRatio = _ratio;
      tester.view.physicalSize = device.size * _ratio;
      tester.view.padding = FakeViewPadding(
        top: device.top * _ratio,
        bottom: 68,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      addTearDown(() => AppStrings.current = const AppStrings('ko'));

      final controller = await _fixture();
      final subscription = _PaidSubscription();
      addTearDown(controller.dispose);
      addTearDown(subscription.dispose);
      final boundary = GlobalKey();
      Future<void> mount(
        _BaselineController source, {
        int initialPage = 1,
      }) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: HangeoreumApp(
              controller: source,
              subscription: subscription,
              initialPage: initialPage,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount(controller);
      await _capture(tester, boundary, device, 'upcoming');
      await _showDetail(tester, '에어컨 필터 청소');
      await _capture(tester, boundary, device, 'detail');
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();

      await _showDetail(tester, '이번 주 업무 정리');
      await tester.ensureVisible(find.widgetWithText(TextButton, '수정'));
      await tester.tap(find.widgetWithText(TextButton, '수정'));
      await tester.pumpAndSettle();
      // Follow the production occurrence-scope dialog before the editor.
      await tester.tap(find.text('이번부터 앞으로'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '계속'));
      await tester.pumpAndSettle();
      final intervalHeader = find
          .descendant(
            of: find.byKey(const Key('editor-interval-settings')),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.ensureVisible(intervalHeader);
      await tester.tap(intervalHeader);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('recurrence-preview'))),
        alignment: .95,
      );
      expect(find.text('다음 3회'), findsOneWidget);
      await _capture(tester, boundary, device, 'repeat');

      await mount(controller, initialPage: 4);
      await _capture(tester, boundary, device, 'settings');
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('language-setting'))),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('language-setting')));
      await tester.pumpAndSettle();
      await _capture(tester, boundary, device, 'language');
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('notification-settings'))),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-settings')));
      await tester.pumpAndSettle();
      await _capture(tester, boundary, device, 'notifications');
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => BackupScreen(
            controller: controller,
            service: _ReadOnlyBackupFixture(controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('최신 백업 1개만 보관'), findsOneWidget);
      await _capture(tester, boundary, device, 'backup');

      final emptyController = await _fixture(empty: true);
      addTearDown(emptyController.dispose);
      await mount(emptyController);
      expect(emptyController.items, isEmpty);
      expect(find.byType(NavigationBar), findsOneWidget);
      await _capture(tester, boundary, device, 'empty');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    });
  }

  tearDownAll(() async {
    if (_scenes.isEmpty) return;
    final sourceHashes = <String, String>{};
    for (final path in [
      'lib/features/home_screen.dart',
      'lib/features/task_editor.dart',
      'lib/features/task_timeline_row.dart',
      'lib/features/backup_screen.dart',
      'lib/features/notification_privacy_setting.dart',
      'lib/features/settings_panel.dart',
      'lib/features/settings_widgets.dart',
      'lib/domain/recurrence_preview.dart',
    ]) {
      sourceHashes[path] = sha256
          .convert(await File(path).readAsBytes())
          .toString();
    }
    await File('$_outputRoot/manifest.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        'source': 'Production HangeoreumApp rendered by Flutter widget test',
        'implementation': 'User-approved improvements in current working tree; not a shipped build',
        'source_file_sha256': sourceHashes,
        'fixture': 'Fictional fixed tasks; original PreviewController samples removed',
        'fixture_date': '2026-10-26',
        'fixture_window_through': _endOfFixtureWindow.toIso8601String(),
        'tasks': [
          {'title': '에어컨 필터 청소', 'due': '2026-10-27T12:00:00', 'category': '생활', 'priority': '보통', 'repeat': '한 번', 'note': '필터를 세척한 뒤 완전히 말리기', 'small_step': '필터 덮개부터 열어보기'},
          {
            'title': '이번 주 업무 정리',
            'due': '2026-10-30T12:00:00',
            'category': '업무',
            'priority': '보통',
            'repeat': '매주 · 요일 선택',
            'interval_weeks': 2,
            'weekdays': ['금'],
            'end_date': null,
            'note': '진행한 업무와 다음 주 할 일을 정리하기',
          },
        ],
        'native_device_capture': false,
        'native_or_external_services_called': false,
        'subscription': 'Explicit paid fixture; no StoreKit call',
        'backup': 'Actual BackupScreen with MemoryBackupStorage and read-only fake loadStatus (enabled=true, latest=2026-10-26 09:00); no native file operation or restore',
        'language': 'ko',
        'fonts': ['PretendardVariable.ttf', 'MaterialIcons-Regular.otf'],
        'calendar_preferences': {'regionCode': 'KR', 'firstDayOfWeek': 0},
        'scenes': _scenes,
      })}\n',
    );
  });
}
