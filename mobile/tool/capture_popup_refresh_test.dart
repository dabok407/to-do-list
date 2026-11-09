// Opt-in real Flutter screen capture with fictional, in-memory tasks only.
// From mobile/: ../.tools/flutter/bin/flutter.bat test
// tool/capture_popup_refresh_test.dart --dart-define=POPUP_CAPTURE=true
// --reporter=expanded --concurrency=1
// These renders are not native-device screenshots or a deployed build.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _output = String.fromEnvironment(
  'POPUP_CAPTURE_OUTPUT',
  defaultValue: '../.tools/popup-refresh-2026-11-07',
);

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
  return controller;
}

void main() {
  if (!const bool.fromEnvironment('POPUP_CAPTURE')) {
    test(
      'Popup refresh screenshots require explicit opt-in',
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
    (width: 375.0, language: 'ko', scale: 1.3),
    (width: 320.0, language: 'ko', scale: 2.0),
    (width: 375.0, language: 'en', scale: 1.0),
    (width: 320.0, language: 'en', scale: 2.0),
  ];
  for (final configuration in configurations) {
    final tag =
        '${configuration.width.toInt()}-${configuration.language}-${configuration.scale.toString().replaceAll('.0', '')}x';
    testWidgets('actual popup surfaces fit and render $tag', (tester) async {
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

        Future<void> tap(Finder finder) async {
          expect(finder, findsOneWidget);
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          expect(finder.hitTestable(), findsOneWidget);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        Future<void> capture(String name) async {
          await tester.pumpAndSettle();
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

        await mount(0);
        await tap(find.byKey(const Key('quick-add')));
        final quickTitle = find.byKey(const Key('quick-add-title'));
        await tester.ensureVisible(quickTitle);
        await tester.enterText(
          quickTitle,
          configuration.language == 'ko' ? '에어컨 필터 청소' : 'Clean the air filter',
        );
        await tester.pumpAndSettle();
        await capture('01-quick-add');
        await tap(find.byKey(const Key('quick-add-time')));
        await capture('02-time-wheel');
        await tap(find.byTooltip(strings.t('취소')));

        await openEditor();
        await tap(find.byKey(const Key('editor-date')));
        await capture('03-date-picker');
        await tap(find.byTooltip(strings.t('취소')));

        await mount(1);
        final repeated = controller.items.firstWhere(
          (item) => item.task.id == 'popup-repeat',
        );
        await tap(find.byKey(ValueKey('task-row-${repeated.id}')));
        await tap(find.text(strings.t('수정')));
        await tap(find.text(strings.t('이번 일정만')));
        await capture('04-repeat-scope');
        await tap(find.text(strings.t('취소')));

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
        await capture('05-sort-menu');

        await openEditor();
        final overdueHeader = find
            .descendant(
              of: find.byKey(const Key('overdue-settings')),
              matching: find.byType(InkWell),
            )
            .first;
        await tap(overdueHeader);
        await tap(find.byKey(const Key('overdue-interval')));
        await capture('06-editor-menu');

        await mount(3);
        await tap(find.byKey(const Key('statistics-period-select')));
        expect(find.byType(DateRangePickerDialog), findsOneWidget);
        await capture('07-statistics-period');

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
