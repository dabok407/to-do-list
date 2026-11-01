// Opt-in rendering fixture only. Production widgets are not changed.
// flutter test tool/capture_seed_comparison_test.dart --dart-define=SEED_CAPTURE=true
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
import 'package:hangeoreum/features/equal_choice_row.dart';
import 'package:hangeoreum/features/settings_widgets.dart';
import 'package:hangeoreum/features/task_completion_checkbox.dart';
import 'package:hangeoreum/features/task_editor.dart';
import 'package:hangeoreum/features/task_list_sort_control.dart';
import 'package:hangeoreum/features/visual_tokens.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart';
import 'package:hangeoreum/services/subscription_service.dart';
import 'package:hangeoreum/services/widget_service.dart';

const output = '../.tools/seed-comparison-2026-10-29';
const enabled = bool.fromEnvironment('SEED_CAPTURE');
final records = <Map<String, Object?>>[];

class PaidFixture extends SubscriptionService {
  PaidFixture() {
    active = true;
    available = true;
  }
  @override
  Future<void> refresh() async {}
  @override
  Future<void> purchase() async => throw StateError('Rendering only');
  @override
  Future<void> restore() async => throw StateError('Rendering only');
  @override
  Future<void> manage() async => throw StateError('Rendering only');
}

class CaptureController extends PreviewController {
  CaptureController() : super(sampleLanguage: 'ko');
  @override
  Future<void> refresh({DateTime? through}) =>
      super.refresh(through: DateTime(2026, 10, 31, 23, 59));
}

final fixtures = [
  Task(
    id: 'seed-clean',
    title: '에어컨 필터 청소',
    due: DateTime(2026, 10, 30, 12),
    created: DateTime(2026, 10, 29),
    category: '생활',
    priority: 1,
    note: '필터를 세척한 뒤 완전히 말리기',
  ),
  Task(
    id: 'seed-work',
    title: '이번 주 업무 정리',
    due: DateTime(2026, 10, 30, 15, 30),
    created: DateTime(2026, 10, 29),
    category: '업무',
    priority: 2,
  ),
  Task(
    id: 'seed-health',
    title: '가볍게 스트레칭',
    due: DateTime(2026, 10, 30, 20),
    created: DateTime(2026, 10, 29),
    category: '건강',
    priority: 0,
  ),
  Task(
    id: 'seed-learn',
    title: '읽던 책 한 챕터 마무리',
    due: DateTime(2026, 10, 31, 9),
    created: DateTime(2026, 10, 29),
    category: '배움',
    priority: 1,
  ),
];

Future<CaptureController> fixture() async {
  final c = CaptureController();
  await c.localeController.setPreference('ko');
  await c.refresh();
  for (final t in await c.repository.tasks()) {
    await c.deleteOccurrence(
      Occurrence(
        id: '${t.id}@${t.due.toIso8601String()}',
        task: t,
        originalDue: t.due,
        reminder: t.due,
      ),
      scope: 'series',
    );
  }
  for (final t in fixtures) {
    await c.save(t);
  }
  await c.refresh();
  return c;
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: '$name layout');
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$output/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    image.dispose();
  });
  records.add({
    'file': '$name.png',
    'variant': name.startsWith('as-is')
        ? 'production-widget-render'
        : 'preview-only-proposal',
    'logicalSize': [375, 812],
    'pixelSize': [750, 1624],
    'fixture': 'fictional, same tasks and settings',
    'safeArea': {'top': 50, 'bottom': 34},
  });
}

NavigationBar nav(int page) => NavigationBar(
  selectedIndex: page,
  onDestinationSelected: (_) {},
  destinations: const [
    NavigationDestination(
      icon: Icon(Icons.calendar_month_outlined),
      label: '캘린더',
    ),
    NavigationDestination(icon: Icon(Icons.list_alt_outlined), label: '예정'),
    NavigationDestination(icon: Icon(Icons.check_circle_outline), label: '완료'),
    NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: '통계'),
    NavigationDestination(icon: Icon(Icons.settings_outlined), label: '설정'),
  ],
);

class PreviewShell extends StatelessWidget {
  final String title;
  final int page;
  final Widget body;
  const PreviewShell({
    super.key,
    required this.title,
    required this.page,
    required this.body,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          SizedBox(
            height: kToolbarHeight,
            child: AppBar(
              primary: false,
              automaticallyImplyLeading: false,
              title: Text(title),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    ),
    floatingActionButton: page == 1
        ? FloatingActionButton.extended(
            onPressed: () {},
            icon: const Icon(Icons.add, size: 21),
            label: const Text('할 일'),
          )
        : null,
    bottomNavigationBar: nav(page),
  );
}

class ProposedList extends StatelessWidget {
  final CaptureController controller;
  const ProposedList(this.controller, {super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final sections = taskListSections(
      controller.queue,
      now: DateTime.now(),
      completed: false,
      order: TaskListOrder.latest,
    );
    return PreviewShell(
      title: '예정된 할 일',
      page: 1,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          TaskListSortControl(
            completed: false,
            order: TaskListOrder.latest,
            onChanged: (_) {},
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  Icons.swap_horiz_rounded,
                  size: 17,
                  color: TaskVisuals.muted,
                ),
                SizedBox(width: 6),
                Text(
                  '어느 쪽으로 밀어도 완료할 수 있어요',
                  style: TextStyle(fontSize: 12, color: TaskVisuals.muted),
                ),
              ],
            ),
          ),
          for (final section in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
              child: Text(
                '${dayOf(section.day!) == dayOf(DateTime.now().add(const Duration(days: 1))) ? '내일' : s.dateShort(section.day!)} · ${s.weekday(section.day!.weekday)}',
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: TaskVisuals.ink,
                ),
              ),
            ),
            for (final o in section.items) ProposedRow(o),
          ],
        ],
      ),
    );
  }
}

class ProposedRow extends StatelessWidget {
  final Occurrence o;
  const ProposedRow(this.o, {super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: TaskVisuals.line, width: .7)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.swap_horiz_rounded,
            size: 16,
            color: TaskVisuals.muted,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 46,
            child: Text(
              s.time(o.originalDue),
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: TaskVisuals.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.task.title,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: TaskVisuals.ink,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CategoryLabel(
                      category: o.task.category,
                      label: o.task.category,
                    ),
                    Text(
                      s.t(
                        o.task.priority == 2
                            ? '높음'
                            : o.task.priority == 0
                            ? '낮음'
                            : '보통',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: TaskVisuals.priorityInk(o.task.priority),
                      ),
                    ),
                    if (o.task.repeat != RepeatUnit.none)
                      const Icon(
                        Icons.repeat_rounded,
                        size: 16,
                        color: TaskVisuals.muted,
                      ),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        onPressed: () {},
                        tooltip: '지금 시작',
                        icon: const Icon(
                          Icons.play_arrow_rounded,
                          size: 21,
                          color: TaskVisuals.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          TaskCompletionCheckbox(
            completed: false,
            enabled: true,
            onToggle: () {},
          ),
        ],
      ),
    );
  }
}

class ProposedEditor extends StatelessWidget {
  const ProposedEditor({super.key});
  InputDecoration deco(BuildContext c, String label, {EdgeInsets? padding}) =>
      InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: Theme.of(c).inputDecorationTheme.border,
        contentPadding: padding ?? const EdgeInsets.all(16),
      );
  Widget field(
    BuildContext c,
    String label,
    Widget child, {
    EdgeInsets? padding,
  }) => InputDecorator(
    decoration: deco(c, label, padding: padding),
    child: child,
  );
  Widget helper(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        height: 1.45,
        color: TaskVisuals.muted,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('반복·할 일 수정')),
    bottomNavigationBar: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: FilledButton(
        onPressed: () {},
        child: const Padding(padding: EdgeInsets.all(12), child: Text('저장')),
      ),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field(
            context,
            '날짜/시간',
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: TextButton.icon(
                    onPressed: () {},
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    icon: const Icon(
                      Icons.calendar_today_outlined,
                      size: 17,
                      color: TaskVisuals.muted,
                    ),
                    label: const Text(
                      '2026-10-30',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: Theme.of(context).dividerColor,
                ),
                Expanded(
                  flex: 4,
                  child: TextButton.icon(
                    onPressed: () {},
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    icon: const Icon(
                      Icons.schedule_outlined,
                      size: 18,
                      color: TaskVisuals.muted,
                    ),
                    label: const Text('12:00', style: TextStyle(fontSize: 15)),
                  ),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          const SizedBox(height: 20),
          field(
            context,
            '분류',
            EqualChoiceRow<String>(
              choices: const {
                '생활': '생활',
                '업무': '업무',
                '건강': '건강',
                '배움': '배움',
                '기타': '기타',
              },
              value: '생활',
              onChanged: (_) {},
              optionKeyPrefix: 'proposal-category',
            ),
            padding: const EdgeInsets.all(12),
          ),
          const SizedBox(height: 20),
          field(
            context,
            '우선순위',
            EqualChoiceRow<int>(
              choices: const {2: '높음', 1: '보통', 0: '낮음'},
              value: 1,
              onChanged: (_) {},
              optionKeyPrefix: 'proposal-priority',
            ),
            padding: const EdgeInsets.all(12),
          ),
          const SizedBox(height: 20),
          TextFormField(
            initialValue: '에어컨 필터 청소',
            readOnly: true,
            decoration: deco(context, '할 일'),
            maxLength: 100,
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: '필터를 세척한 뒤 완전히 말리기',
            readOnly: true,
            decoration: deco(context, '메모'),
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 20),
          field(
            context,
            '미완료 재알림',
            const SizedBox(
              height: 40,
              child: Row(
                children: [
                  Expanded(child: Text('매일 · 예정 시간과 같게')),
                  Icon(Icons.expand_more_rounded, size: 20),
                ],
              ),
            ),
          ),
          helper('기한이 지난 같은 일을 완료할 때까지 다시 알려요.'),
          const SizedBox(height: 20),
          field(
            context,
            '반복',
            const SizedBox(
              height: 40,
              child: Row(
                children: [
                  Expanded(child: Text('한 번')),
                  Icon(Icons.expand_more_rounded, size: 20),
                ],
              ),
            ),
          ),
          helper('반복을 설정하면 패턴대로 새로운 회차가 생겨요.'),
          const SizedBox(height: 20),
          field(context, '작은 첫걸음', const Text('시작하기 쉬운 작은 행동을 적어보세요')),
        ],
      ),
    ),
  );
}

class ProposedSettings extends StatelessWidget {
  const ProposedSettings({super.key});
  Widget entry(
    IconData icon,
    String title, {
    String? subtitle,
    String? value,
    bool toggle = false,
  }) => InkWell(
    onTap: () {},
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Row(
          children: [
            SettingsIcon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: settingsInk,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: settingsMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (toggle)
              SizedBox(
                width: 48,
                child: Switch.adaptive(value: true, onChanged: (_) {}),
              )
            else ...[
              if (value != null) ...[
                const SizedBox(width: 6),
                Text(
                  value,
                  style: const TextStyle(fontSize: 13, color: settingsMuted),
                ),
              ],
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xff929a94),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PreviewShell(
    title: '설정',
    page: 4,
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        SettingsGroup(
          children: [
            entry(
              Icons.workspace_premium_outlined,
              '투두닉 Pro 이용 중',
              subtitle: '연간 구독 · 구매 복원 · 구독 관리',
            ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsGroup(
          title: '알림',
          children: [
            entry(
              Icons.visibility_outlined,
              '알림에 할 일 제목 표시',
              subtitle: '제목 표시 · 기본 설정',
              toggle: true,
            ),
            entry(
              Icons.notifications_none_rounded,
              '알림 설정·테스트',
              subtitle: '권한 확인과 테스트 알림',
            ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsGroup(
          title: '데이터·사용 환경',
          children: [
            entry(
              Icons.folder_outlined,
              '백업·복원',
              subtitle: '주 1회 자동 백업 · 최신 백업 1개 보관',
            ),
            entry(Icons.language_rounded, '언어', value: '한국어'),
          ],
        ),
        const SizedBox(height: 20),
        SettingsGroup(
          title: '지원·앱 정보',
          children: [
            entry(
              Icons.shield_outlined,
              '나의 일정은, 나의 기기에만',
              subtitle: '데이터 보관과 개인정보 안내',
            ),
            entry(Icons.help_outline_rounded, '고객 지원'),
            entry(Icons.policy_outlined, '개인정보처리방침'),
            entry(Icons.description_outlined, '이용약관'),
          ],
        ),
      ],
    ),
  );
}

void main() {
  if (!enabled) {
    test('SEED capture requires explicit opt-in', () {}, skip: true);
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
      throw MissingPluginException('Rendering fixture only');
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
  testWidgets('same-data production and preview-only SEED comparison', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 1624);
    tester.view.padding = const FakeViewPadding(top: 100, bottom: 68);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    addTearDown(() => AppStrings.current = const AppStrings('ko'));
    final c = await fixture();
    final subscription = PaidFixture();
    addTearDown(c.dispose);
    addTearDown(subscription.dispose);
    final boundary = GlobalKey();
    Future<void> mount(int page) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: HangeoreumApp(
            controller: c,
            subscription: subscription,
            initialPage: page,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> push(Widget w) async {
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(MaterialPageRoute<void>(builder: (_) => w));
      await tester.pumpAndSettle();
    }

    await mount(1);
    await capture(tester, boundary, 'as-is-upcoming');
    await push(ProposedList(c));
    await capture(tester, boundary, 'to-be-upcoming');
    await mount(1);
    await push(
      TaskEditor(task: fixtures.first, initialDate: fixtures.first.due),
    );
    await capture(tester, boundary, 'as-is-editor');
    await mount(1);
    await push(const ProposedEditor());
    await capture(tester, boundary, 'to-be-editor');
    await mount(4);
    await capture(tester, boundary, 'as-is-settings');
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    await capture(tester, boundary, 'as-is-settings-bottom');
    await mount(4);
    await push(const ProposedSettings());
    await capture(tester, boundary, 'to-be-settings');
    await tester.drag(find.byType(ListView).last, const Offset(0, -420));
    await tester.pumpAndSettle();
    await capture(tester, boundary, 'to-be-settings-bottom');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
    await tester.runAsync(() async {
      await File('$output/manifest.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'generatedAt': DateTime.now().toUtc().toIso8601String(),
          'version': '1.0.3+1401 source plus local theme fix',
          'source': 'Actual Flutter production baseline; separately composed proposal widgets. Not iPhone device screenshots.',
          'captures': records,
        }),
      );
    });
  });
}
