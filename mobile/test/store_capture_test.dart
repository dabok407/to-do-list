// Production-widget artwork capture fixture. It runs only when explicitly
// requested with STORE_CAPTURE=true and --update-goldens; ordinary tests skip it.
// This is a Flutter rendering, not a claim of a native-device screenshot.
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/task_editor.dart';
import 'package:hangeoreum/features/privacy_card.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart';
import 'package:hangeoreum/l10n/app_strings.dart';

const _enabled = bool.fromEnvironment('STORE_CAPTURE');
const _onlyPrivacy = bool.fromEnvironment('STORE_CAPTURE_PRIVACY_ONLY');
const _language = String.fromEnvironment(
  'STORE_CAPTURE_LANGUAGE',
  defaultValue: 'ko',
);
const _strings = AppStrings(_language);
const _outputRoot = _language == 'en' ? 'store/captures/en' : 'store/captures';

String _sample(String korean, String english) =>
    _language == 'en' ? english : korean;

Finder _navigation(String korean) => find.descendant(
  of: find.byType(NavigationBar),
  matching: find.text(_strings.t(korean)),
);

class _CaptureSubscription extends PreviewSubscription {
  _CaptureSubscription() {
    active = true;
    previewTrial = false;
  }
  @override
  bool get paidAccess => true;
  @override
  Future<void> refresh() async {}
}

const _devices = [
  (name: 'iphone', size: Size(393, 852), ratio: 3.0, ios: true),
  (name: 'ipad', size: Size(1032, 1376), ratio: 2.0, ios: true),
  (name: 'android', size: Size(360, 640), ratio: 3.0, ios: false),
];

Future<PreviewController> _fixture() async {
  final c = PreviewController(sampleLanguage: _language);
  await c.localeController.setPreference(_language);
  final now = DateTime.now();
  final today = dayOf(now);
  final oldest = today.subtract(const Duration(days: 89));
  final recent = today.subtract(const Duration(days: 18));
  await c.save(
    Task(
      id: 'sample-1',
      title: _sample('책 10쪽 읽기', 'Read 10 pages'),
      category: '배움',
      due: DateTime(oldest.year, oldest.month, oldest.day, 21),
      created: recent,
      repeat: RepeatUnit.daily,
      smallStep: _sample('책을 펴고 한 문단 읽기', 'Open a book and read one paragraph'),
    ),
  );
  await c.save(
    Task(
      id: 'running',
      title: _sample('가볍게 달리기', 'Go for a light run'),
      category: '건강',
      due: DateTime(oldest.year, oldest.month, oldest.day, 19),
      created: recent,
      repeat: RepeatUnit.weekly,
      weekdays: const [2, 4, 6],
      end: DateTime(today.year, today.month + 2, 0),
      smallStep: _sample('운동복 입고 5분만 걷기', 'Get dressed and walk for 5 minutes'),
    ),
  );
  await c.save(
    Task(
      id: 'weekly-plan',
      title: _sample('다음 주 계획', 'Plan next week'),
      category: '업무',
      due: DateTime(oldest.year, oldest.month, oldest.day, 20),
      created: recent,
      repeat: RepeatUnit.weekly,
      weekdays: const [7],
    ),
  );
  await c.save(
    Task(
      id: 'sample-3',
      title: _sample('안방 대청소', 'Clean the bedroom'),
      category: '생활',
      priority: 2,
      due: DateTime(today.year, today.month, today.day, 9),
      created: recent,
      note: _sample(
        '한 번에 전부 하지 않아도 괜찮아요.',
        'You do not have to finish everything at once.',
      ),
      smallStep: _sample(
        '바닥에 놓인 물건 3개만 제자리에 두기',
        'Put away just 3 things from the floor',
      ),
    ),
  );
  await c.save(
    Task(
      id: 'sample-4',
      title: _sample('에어컨 필터 청소', 'Clean the AC filter'),
      category: '생활',
      priority: 2,
      due: DateTime(today.year, today.month, today.day - 1, 12),
      created: recent,
      note: _sample(
        '필터를 꺼내 먼지만 먼저 털어내기',
        'Take out the filter and dust it off first',
      ),
    ),
  );
  await c.save(
    Task(
      id: 'receipts',
      title: _sample('영수증 정리', 'Sort receipts'),
      category: '업무',
      due: DateTime(today.year, today.month, today.day - 2, 20),
      created: recent,
    ),
  );
  await c.save(
    Task(
      id: 'grocery',
      title: _sample('주말 장보기', 'Weekend groceries'),
      category: '생활',
      due: DateTime(today.year, today.month, today.day + 1, 11),
      created: recent,
      note: _sample('우유 · 달걀 · 토마토', 'Milk · Eggs · Tomatoes'),
    ),
  );
  await c.save(
    Task(
      id: 'budget',
      title: _sample('가계부 정리', 'Review the household budget'),
      category: '생활',
      due: DateTime(today.year, today.month, 1, 20),
      created: recent,
      repeat: RepeatUnit.monthly,
    ),
  );
  // Seed the real preview action flow so the detail's repository-backed
  // todaySnoozes query renders the actual three-snooze small-step card.
  for (var i = 0; i < 3; i++) {
    await c.act(
      c.items.firstWhere((o) => o.task.id == 'sample-3'),
      'snooze',
      minutes: i == 1 ? 30 : 10,
    );
  }
  // A lived-in sample calendar. Replace statuses in the same list referenced
  // by PreviewRepository; no production code or private user data is changed.
  for (var i = 0; i < c.items.length; i++) {
    final o = c.items[i];
    if (o.task.id == 'sample-3') continue;
    final todayDone = o.task.id == 'sample-0' && dayOf(o.originalDue) == today;
    final unfinished = {'sample-4', 'receipts'}.contains(o.task.id);
    final isPast = o.originalDue.isBefore(now);
    final done =
        !unfinished && (todayDone || (isPast && o.originalDue.day % 5 != 0));
    final snoozes = done && o.originalDue.day % 7 == 0 ? 1 : 0;
    c.items[i] = Occurrence(
      id: o.id,
      task: o.task,
      originalDue: o.originalDue,
      reminder: o.reminder,
      status: unfinished
          ? TaskStatus.pending
          : done
          ? TaskStatus.completed
          : isPast
          ? TaskStatus.skipped
          : TaskStatus.pending,
      completed: done
          ? o.originalDue.add(Duration(minutes: snoozes == 1 ? 15 : 5))
          : null,
      snoozes: snoozes,
    );
  }
  final begin = today.subtract(const Duration(days: 29));
  final inMonth = c.items
      .where(
        (o) =>
            !dayOf(o.originalDue).isBefore(begin) &&
            !dayOf(o.originalDue).isAfter(today),
      )
      .toList();
  final done = inMonth.where((o) => o.status == TaskStatus.completed).toList();
  final snoozes = inMonth.fold<int>(0, (sum, o) => sum + o.snoozes);
  final total = inMonth
      .where(
        (o) => !o.originalDue.isAfter(now) || o.status == TaskStatus.completed,
      )
      .length;
  final minutes = inMonth.fold<int>(
    0,
    (sum, o) => sum + (o.task.id == 'sample-3' ? 50 : o.snoozes * 15),
  );
  final hours = <int, int>{};
  for (final o in done) {
    hours.update(o.completed!.hour, (n) => n + 1, ifAbsent: () => 1);
  }
  final most = hours.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final tasks = {for (final o in c.items) o.task.id: o.task};
  c.statistics = {
    'registered': tasks.values
        .where((t) => !dayOf(t.created).isBefore(begin))
        .length,
    'total': total,
    'completed': done.length,
    'snoozes': snoozes,
    'average': snoozes == 0 ? 0.0 : minutes / snoozes,
    'hour': most.isEmpty ? '기록 없음' : '${most.first.key}시',
  };
  return c;
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String device,
  String name,
  double ratio,
) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = File('$_outputRoot/$device/$name.png');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  if (!_enabled || !autoUpdateGoldenFiles) {
    test(
      'Store artwork is generated only on explicit request',
      () {},
      skip: true,
    );
    return;
  }
  if (!{'ko', 'en'}.contains(_language)) {
    throw ArgumentError.value(
      _language,
      'STORE_CAPTURE_LANGUAGE',
      'Use ko or en',
    );
  }
  setUpAll(() async {
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final d in _devices) {
    testWidgets('${d.name} $_language production-widget store captures', (
      tester,
    ) async {
      tester.view.devicePixelRatio = d.ratio;
      tester.view.physicalSize = d.size * d.ratio;
      tester.view.padding = FakeViewPadding(
        top:
            (d.name == 'iphone'
                ? 47
                : d.ios
                ? 24
                : 24) *
            d.ratio,
        bottom:
            (d.name == 'iphone'
                ? 34
                : d.ios
                ? 20
                : 24) *
            d.ratio,
      );
      debugDefaultTargetPlatformOverride = d.ios
          ? TargetPlatform.iOS
          : TargetPlatform.android;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      addTearDown(() => AppStrings.current = const AppStrings('ko'));
      final c = await _fixture();
      final subscription = _CaptureSubscription();
      addTearDown(c.dispose);
      addTearDown(subscription.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: HangeoreumApp(controller: c, subscription: subscription),
        ),
      );
      if (_onlyPrivacy) {
        await tester.pumpAndSettle();
        await tester.tap(_navigation('설정'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(PrivacyCard));
        await _capture(tester, key, d.name, '07-privacy', d.ratio);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
        return;
      }
      await _capture(tester, key, d.name, '01-calendar', d.ratio);

      await tester.tap(find.byKey(const Key('overdue-banner')));
      await _capture(tester, key, d.name, '02-overdue', d.ratio);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Selecting a calendar day is the real one-tap route to that day's list.
      final day = find
          .descendant(
            of: find.byType(GridView),
            matching: find.text('${DateTime.now().day}'),
          )
          .first;
      await tester.tap(day);
      await tester.pumpAndSettle();
      final cleaning = find.text(_sample('안방 대청소', 'Clean the bedroom')).last;
      await tester.ensureVisible(cleaning);
      await tester.tap(cleaning);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(_strings.t('5분 시작')));
      await _capture(tester, key, d.name, '03-small-start', d.ratio);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Open an existing repeating task via the production edit flow.
      final running = find.text(_sample('가볍게 달리기', 'Go for a light run')).last;
      await tester.ensureVisible(running);
      await tester.tap(running);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(_strings.t('수정')));
      await tester.tap(find.text(_strings.t('수정')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_strings.t('이번부터 앞으로')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_strings.t('계속')));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditor), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.byType(DropdownButtonFormField<RepeatUnit>)),
        alignment: .12,
      );
      await _capture(tester, key, d.name, '04-repeat', d.ratio);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(_navigation('통계'));
      await _capture(tester, key, d.name, '06-statistics', d.ratio);
      await tester.ensureVisible(find.text(_strings.t('자주 완료한 시간대')));
      await _capture(tester, key, d.name, '06-statistics-detail', d.ratio);

      await tester.tap(_navigation('설정'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(PrivacyCard));
      await _capture(tester, key, d.name, '07-privacy', d.ratio);
      await tester.ensureVisible(find.byIcon(Icons.auto_graph));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.auto_graph));
      await _capture(tester, key, d.name, '08-pro', d.ratio);
      await tester.runAsync(() async {
        await File('$_outputRoot/${d.name}/source.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'source': 'Production HangeoreumApp widgets rendered by Flutter widget test',
            'fixture': 'PreviewController with fictional household tasks; no private records',
            'language': _language,
            'display_name': AppStrings.appName,
            'sample_titles_are_localized_fixtures': true,
            'user_records_are_translated': false,
            'native_device_capture': false,
            'fonts': ['PretendardVariable.ttf', 'MaterialIcons-Regular.otf'],
            'logical_width': d.size.width.toInt(),
            'logical_height': d.size.height.toInt(),
            'pixel_ratio': d.ratio,
            'png_width': (d.size.width * d.ratio).toInt(),
            'png_height': (d.size.height * d.ratio).toInt(),
            'sample_day': dayKey(DateTime.now()),
            'statistics_30_days': c.statistics,
            'scene_labels': {
              '01-calendar': _sample('할 일 캘린더', 'Task calendar'),
              '02-overdue': _sample('아직 남은 일', 'Overdue tasks'),
              '03-small-start': _sample('5분부터 시작', 'Start with 5 minutes'),
              '04-repeat': _sample('반복 일정', 'Repeating tasks'),
              '06-statistics': _sample('나의 흐름', 'My progress'),
              '06-statistics-detail': _sample('30일 통계', '30-day insights'),
              '07-privacy': _sample(
                '개인정보와 언어 설정',
                'Privacy and language settings',
              ),
              '08-pro': _sample('투두닉 Pro', 'Todoniq Pro'),
            },
            'screens': [
              '01-calendar.png',
              '02-overdue.png',
              '03-small-start.png',
              '04-repeat.png',
              '06-statistics.png',
              '06-statistics-detail.png',
              '07-privacy.png',
              '08-pro.png',
            ],
          }),
        );
      });
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
