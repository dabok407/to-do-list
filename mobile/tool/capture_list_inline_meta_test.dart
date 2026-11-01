// Preview-only response to the rejected first list proposal.
// This file never changes tasks, native services, or production widgets.
// flutter test tool/capture_list_inline_meta_test.dart --dart-define=LIST_INLINE_META_CAPTURE=true
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/domain/task_list_sections.dart';
import 'package:hangeoreum/features/task_list_sort_control.dart';
import 'package:hangeoreum/features/visual_tokens.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/services/widget_service.dart';

import 'capture_seed_comparison_test.dart' as baseline;

const _enabled = bool.fromEnvironment('LIST_INLINE_META_CAPTURE');
const _output = '../.tools/list-inline-meta-2026-10-30';
final _records = <Map<String, Object?>>[];

class InlineMetaList extends StatelessWidget {
  final baseline.CaptureController controller;
  final bool edgeCase;
  const InlineMetaList(this.controller, {super.key, this.edgeCase = false});

  Occurrence presentation(Occurrence source) {
    if (!edgeCase || source.task.id != 'seed-learn') return source;
    final task = Task.fromMap({
      ...source.task.toMap(),
      'title': '읽던 책 한 챕터를 마무리하고 인상 깊은 문장 기록하기',
      'repeat_unit': RepeatUnit.weekly.name,
      'weekdays': jsonEncode([DateTime.saturday]),
    });
    return Occurrence(
      id: source.id,
      task: task,
      originalDue: source.originalDue,
      reminder: source.reminder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final sections = taskListSections(
      controller.queue,
      now: DateTime.now(),
      completed: false,
      order: TaskListOrder.latest,
    );
    return baseline.PreviewShell(
      title: '예정된 할 일',
      page: 1,
      body: ListView(
        key: const Key('refined-list'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          TaskListSortControl(
            completed: false,
            order: TaskListOrder.latest,
            onChanged: (_) {},
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 2),
            child: Text(
              '좌우로 밀어도 완료돼요',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                height: 1.5,
                color: TaskVisuals.muted,
              ),
            ),
          ),
          for (final section in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
              child: Text(
                '${dayOf(section.day!) == dayOf(DateTime.now().add(const Duration(days: 1))) ? '내일' : strings.dateShort(section.day!)} · ${strings.weekday(section.day!.weekday)}',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 19,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: TaskVisuals.ink,
                ),
              ),
            ),
            for (final source in section.items)
              InlineMetaRow(
                presentation(source),
                // The screenshot represents the visible feedback immediately after
                // completing this row. No repository state is changed by capture.
                justCompleted: edgeCase && source.task.id == 'seed-work',
              ),
          ],
        ],
      ),
    );
  }
}

class InlineMetaRow extends StatelessWidget {
  final Occurrence occurrence;
  final bool justCompleted;
  const InlineMetaRow(this.occurrence, {super.key, this.justCompleted = false});

  @override
  Widget build(BuildContext context) {
    final task = occurrence.task;
    final strings = AppStrings.of(context);
    final done = justCompleted || occurrence.status == TaskStatus.completed;
    final scaler = MediaQuery.textScalerOf(context);
    Size measure(String value, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final timeStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 18,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: done ? TaskVisuals.muted : TaskVisuals.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final titleStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 16,
      height: 1.45,
      fontWeight: FontWeight.w500,
      color: done ? TaskVisuals.muted : TaskVisuals.ink,
      decoration: done ? TextDecoration.lineThrough : null,
    );
    const categoryStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 13,
      height: 1.45,
      fontWeight: FontWeight.w500,
    );
    final priorityStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 12,
      height: 1.5,
      fontWeight: FontWeight.w500,
      color: TaskVisuals.priorityInk(task.priority),
    );
    final completionStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 11,
      height: 1.2,
      fontWeight: done ? FontWeight.w600 : FontWeight.w400,
      color: done ? TaskVisuals.ink : TaskVisuals.muted,
    );
    final clock = strings.time(occurrence.originalDue);
    final category = strings.category(task.category);
    final priority = strings.t(
      task.priority == 2
          ? '높음'
          : task.priority == 0
          ? '낮음'
          : '보통',
    );
    final completion = done ? '완료됨' : '완료';
    final timeWidth = (measure(clock, timeStyle).width.ceilToDouble() + 4)
        .clamp(56.0, double.infinity);
    final metadataWidth =
        16 +
        6 +
        measure(category, categoryStyle).width +
        6 +
        measure(priority, priorityStyle).width +
        (task.repeat == RepeatUnit.none ? 0 : 22);
    final labelHeight = measure(completion, completionStyle).height;
    // Keep the checkbox centered. Its caption begins 1 px below the 24 px box;
    // enlarge only at large accessibility text so the caption cannot clip.
    final slotHeight = ((2 * (13 + labelHeight) / 4).ceil() * 4)
        .toDouble()
        .clamp(56.0, double.infinity);
    Widget metadata() => Row(
      key: Key('refined-meta-${task.id}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        CategoryLabel(category: task.category, label: category),
        const SizedBox(width: 6),
        Text(priority, style: priorityStyle, maxLines: 1, softWrap: false),
        if (task.repeat != RepeatUnit.none) ...[
          const SizedBox(width: 6),
          const Icon(
            Icons.repeat_rounded,
            size: 16,
            color: TaskVisuals.muted,
            semanticLabel: '반복',
          ),
        ],
      ],
    );
    Widget title({required bool stacked}) => Text(
      task.title,
      key: Key('refined-title-${task.id}'),
      maxLines: stacked ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      softWrap: stacked,
      style: titleStyle,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleWidth =
            constraints.maxWidth - timeWidth - 8 - 6 - metadataWidth - 4 - 48;
        final stacked = scaler.scale(16) > 16 && titleWidth <= 72;
        final body = stacked
            ? Column(
                key: Key('refined-content-${task.id}'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title(stacked: true),
                  const SizedBox(height: 6),
                  metadata(),
                ],
              )
            : Row(
                key: Key('refined-content-${task.id}'),
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: title(stacked: false)),
                  const SizedBox(width: 6),
                  metadata(),
                ],
              );
        return Material(
          color: Colors.white,
          shape: const Border(
            bottom: BorderSide(color: TaskVisuals.line, width: .7),
          ),
          child: ConstrainedBox(
            key: Key('refined-row-${task.id}'),
            constraints: BoxConstraints(minHeight: slotHeight + 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: timeWidth,
                    height: slotHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Center(
                          child: Text(
                            clock,
                            key: Key('refined-time-${task.id}'),
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.center,
                            style: timeStyle,
                          ),
                        ),
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ExcludeSemantics(
                            child: Icon(
                              Icons.swap_horiz_rounded,
                              size: 14,
                              color: TaskVisuals.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: KeyedSubtree(
                      key: Key(
                        '${stacked ? 'stacked' : 'inline'}-layout-${task.id}',
                      ),
                      child: body,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Semantics(
                    checked: done,
                    label: '${task.title}, ${done ? '완료 해제' : '완료 처리'}',
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        key: Key('refined-target-${task.id}'),
                        width: 48,
                        height: slotHeight,
                        child: Stack(
                          children: [
                            Center(
                              child: Container(
                                key: Key('refined-box-${task.id}'),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: done ? TaskVisuals.ink : Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: done
                                        ? TaskVisuals.ink
                                        : TaskVisuals.muted,
                                    width: 1.8,
                                  ),
                                ),
                                child: done
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: slotHeight / 2 + 13,
                              child: Text(
                                completion,
                                key: Key('refined-caption-${task.id}'),
                                maxLines: 1,
                                softWrap: false,
                                textAlign: TextAlign.center,
                                style: completionStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
  Size size,
  double scale,
) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: '$name layout');
  await tester.runAsync(() async {
    final box =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await box.toImage(pixelRatio: 2);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
  _records.add({
    'file': '$name.png',
    'logicalSize': [size.width, size.height],
    'pixelRatio': 2,
    'textScale': scale,
    'type': name.startsWith('as-is')
        ? 'actual-current-Flutter-source'
        : 'preview-only-proposal',
  });
}

List<Map<String, Object?>> _assertAlignment(WidgetTester tester, String scene) {
  final evidence = <Map<String, Object?>>[];
  for (final task in baseline.fixtures) {
    final content = find.byKey(Key('refined-content-${task.id}'));
    if (content.evaluate().isEmpty) continue;
    final timeRect = tester.getRect(find.byKey(Key('refined-time-${task.id}')));
    final contentRect = tester.getRect(content);
    final boxRect = tester.getRect(find.byKey(Key('refined-box-${task.id}')));
    final targetRect = tester.getRect(
      find.byKey(Key('refined-target-${task.id}')),
    );
    expect(
      timeRect.center.dy,
      closeTo(contentRect.center.dy, .01),
      reason: '$scene ${task.id} time/text center',
    );
    expect(
      boxRect.center.dy,
      closeTo(contentRect.center.dy, .01),
      reason: '$scene ${task.id} box/text center',
    );
    expect(boxRect.size, const Size(24, 24));
    expect(targetRect.width, 48);
    expect(targetRect.height, greaterThanOrEqualTo(56));
    final rowRect = tester.getRect(find.byKey(Key('refined-row-${task.id}')));
    final titleRect = tester.getRect(
      find.byKey(Key('refined-title-${task.id}')),
    );
    final metadataRect = tester.getRect(
      find.byKey(Key('refined-meta-${task.id}')),
    );
    final captionRect = tester.getRect(
      find.byKey(Key('refined-caption-${task.id}')),
    );
    final inline = find
        .byKey(Key('inline-layout-${task.id}'))
        .evaluate()
        .isNotEmpty;
    if (inline) {
      expect(
        titleRect.center.dy,
        closeTo(contentRect.center.dy, .01),
        reason: '$scene ${task.id} title center',
      );
      expect(
        metadataRect.center.dy,
        closeTo(contentRect.center.dy, .01),
        reason: '$scene ${task.id} metadata center',
      );
    }
    if (scene.startsWith('inline-upcoming')) {
      expect(rowRect.height, 64, reason: '$scene ${task.id} compact height');
    }
    expect(
      captionRect.bottom,
      lessThanOrEqualTo(targetRect.bottom + .01),
      reason: '$scene ${task.id} caption within touch target',
    );
    for (final rect in [
      timeRect,
      titleRect,
      metadataRect,
      boxRect,
      captionRect,
    ]) {
      expect(rect.left, greaterThanOrEqualTo(rowRect.left - .01));
      expect(rect.right, lessThanOrEqualTo(rowRect.right + .01));
      expect(rect.top, greaterThanOrEqualTo(rowRect.top - .01));
      expect(rect.bottom, lessThanOrEqualTo(rowRect.bottom + .01));
    }
    expect(
      timeRect.height,
      lessThan(36),
      reason: '$scene ${task.id} single-line clock',
    );
    evidence.add({
      'task': task.id,
      'timeCenterY': timeRect.center.dy,
      'contentCenterY': contentRect.center.dy,
      'checkboxCenterY': boxRect.center.dy,
      'titleCenterY': titleRect.center.dy,
      'metadataCenterY': metadataRect.center.dy,
      'inline': inline,
      'rowHeight': rowRect.height,
      'titleWidth': titleRect.width,
      'target': [targetRect.width, targetRect.height],
    });
  }
  expect(
    evidence.length,
    greaterThanOrEqualTo(2),
    reason: '$scene rendered rows',
  );
  return evidence;
}

void main() {
  if (!_enabled) {
    test('Inline metadata capture requires explicit opt-in', () {}, skip: true);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(
    () =>
        messenger.setMockMethodCallHandler(WidgetService.channel, (call) async {
          if (call.method == 'getCalendarPreferences') {
            return {'regionCode': 'KR', 'firstDayOfWeek': 0};
          }
          throw MissingPluginException('Capture has no native services');
        }),
  );
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
  const cases = [
    (name: 'inline-upcoming', width: 375.0, scale: 1.0, edge: false),
    (name: 'inline-long-completed', width: 375.0, scale: 1.0, edge: true),
    (name: 'qa-320-long', width: 320.0, scale: 1.0, edge: true),
    (name: 'qa-402-long', width: 402.0, scale: 1.0, edge: true),
    (name: 'qa-375-large-text', width: 375.0, scale: 1.3, edge: true),
    (name: 'qa-320-large-text', width: 320.0, scale: 1.3, edge: true),
  ];
  for (final scene in cases) {
    testWidgets('${scene.name}: render and verify visible center alignment', (
      tester,
    ) async {
      final size = Size(scene.width, 812);
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = size * 2;
      tester.view.padding = const FakeViewPadding(top: 100, bottom: 68);
      tester.platformDispatcher.textScaleFactorTestValue = scene.scale;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      addTearDown(() => AppStrings.current = const AppStrings('ko'));
      final controller = await baseline.fixture();
      final subscription = baseline.PaidFixture();
      addTearDown(controller.dispose);
      addTearDown(subscription.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: HangeoreumApp(
            controller: controller,
            subscription: subscription,
            initialPage: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (scene.name == 'inline-upcoming') {
        await _capture(tester, boundary, 'as-is-upcoming', size, scene.scale);
      }
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => InlineMetaList(controller, edgeCase: scene.edge),
            ),
          );
      await tester.pumpAndSettle();
      final evidence = _assertAlignment(tester, scene.name);
      if (scene.name == 'qa-320-large-text') {
        expect(
          evidence.any((row) => row['inline'] == false),
          isTrue,
          reason: 'Narrow large text uses the <=72px title-space exception',
        );
      }
      await _capture(tester, boundary, scene.name, size, scene.scale);
      _records.last['alignment'] = evidence;
      if (!scene.edge) {
        final fab = tester.getRect(find.byType(FloatingActionButton).last);
        final nav = tester.getRect(find.byType(NavigationBar).last);
        for (final task in baseline.fixtures) {
          final target = tester.getRect(
            find.byKey(Key('refined-target-${task.id}')),
          );
          expect(
            target.overlaps(fab),
            isFalse,
            reason: '${task.id} completion target versus FAB',
          );
          expect(
            target.bottom,
            lessThanOrEqualTo(nav.top),
            reason: '${task.id} completion target visible',
          );
        }
      }
      await tester.drag(
        find.byKey(const Key('refined-list')),
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '${scene.name} scrolled layout',
      );
      _assertAlignment(tester, '${scene.name} scrolled');
      final lastTarget = find.byKey(const Key('refined-target-seed-clean'));
      await Scrollable.ensureVisible(
        tester.element(lastTarget),
        alignment: .35,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(lastTarget)
            .overlaps(tester.getRect(find.byType(FloatingActionButton).last)),
        isFalse,
        reason:
            '${scene.name} last completion target reachable after scrolling',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }
  tearDownAll(() async {
    await File('$_output/manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'preview-only; not deployed',
        'source': 'Actual HangeoreumApp theme, Pretendard, CategoryLabel. Revised rows are screenshot-only fixtures.',
        'limitations': 'No actual task toggle, purchase, notification or device screenshot. Start action remains on production detail; the proposal removes only list shortcut.',
        'captures': _records,
      }),
    );
  });
}
