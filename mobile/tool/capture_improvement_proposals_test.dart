// Review-only design proposals. These screens are not shipping features.
// Run explicitly with --dart-define=IMPROVEMENT_PROPOSALS=true.
// PNGs are Flutter widget renders, not physical-device or OS notification captures.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/features/task_timeline_row.dart';
import 'package:hangeoreum/features/visual_tokens.dart';
import 'package:hangeoreum/l10n/app_strings.dart';
import 'package:hangeoreum/main.dart';
import 'package:hangeoreum/preview.dart';
import 'package:hangeoreum/services/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = bool.fromEnvironment('IMPROVEMENT_PROPOSALS');
const _output = '../.tools/improvement-review-2026-10-26/captures';
const _ink = TaskVisuals.ink;
const _muted = TaskVisuals.muted;
const _line = TaskVisuals.line;
const _devices = [
  (name: 'mini', width: 375.0, height: 812.0, top: 50.0, bottom: 34.0),
  (name: 'pro', width: 402.0, height: 874.0, top: 62.0, bottom: 34.0),
];
const _scenes = [
  'reminder',
  'search',
  'snooze',
  'backup',
  'repeat',
  'bulk',
  'trash',
  'empty',
  'privacy',
];
void _noop() {}

Task _task(
  String id,
  String title, {
  int hour = 12,
  int minute = 0,
  int day = 27,
  String category = '생활',
  RepeatUnit repeat = RepeatUnit.none,
}) => Task(
  id: id,
  title: title,
  category: category,
  priority: 1,
  due: DateTime(2026, 10, day, hour, minute),
  created: DateTime(2026, 10, 26, 9),
  note: '필터를 세척한 뒤 완전히 말리기',
  repeat: repeat,
  interval: repeat == RepeatUnit.weekly ? 2 : 1,
  weekdays: repeat == RepeatUnit.weekly ? const [5] : const [],
);

Occurrence _occurrence(
  String id,
  String title, {
  int hour = 12,
  int minute = 0,
  int day = 27,
  String category = '생활',
  RepeatUnit repeat = RepeatUnit.none,
}) {
  final task = _task(
    id,
    title,
    hour: hour,
    minute: minute,
    day: day,
    category: category,
    repeat: repeat,
  );
  return Occurrence(
    id: '$id@${task.due.toIso8601String()}',
    task: task,
    originalDue: task.due,
    reminder: task.due,
  );
}

Widget _title(String value, {double size = 20}) => Text(
  value,
  style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, height: 1.4),
);
Widget _hint(String value) => Text(
  value,
  style: const TextStyle(fontSize: 13, color: _muted, height: 1.55),
);
Widget _label(String value) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Text(
    value,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  ),
);
Widget _divider() => const Divider(height: 28, thickness: .7, color: _line);
Widget _gap([double height = 16]) => SizedBox(height: height);

Widget _navigation(int selected) => NavigationBar(
  selectedIndex: selected,
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

Widget _screen(
  String title,
  Widget body, {
  bool back = false,
  int? navigation,
  List<Widget>? actions,
  Widget? footer,
}) => Scaffold(
  appBar: AppBar(
    automaticallyImplyLeading: false,
    leading: back ? const BackButton(onPressed: _noop) : null,
    title: Text(title),
    actions: actions,
  ),
  body: body,
  bottomNavigationBar:
      footer ?? (navigation == null ? null : _navigation(navigation)),
);

Widget _content(List<Widget> children, {EdgeInsets? padding}) => ListView(
  padding: padding ?? const EdgeInsets.fromLTRB(20, 16, 20, 24),
  children: children,
);

Widget _outline(List<Widget> children, {EdgeInsets? padding}) => Container(
  padding: padding ?? const EdgeInsets.all(16),
  decoration: BoxDecoration(
    border: Border.all(color: _line),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  ),
);

Widget _settingRow(
  IconData icon,
  String title, {
  String? subtitle,
  Widget? trailing,
}) => ListTile(
  contentPadding: EdgeInsets.zero,
  leading: Icon(icon, color: _ink, size: 23),
  title: Text(
    title,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
  ),
  subtitle: subtitle == null
      ? null
      : Padding(padding: const EdgeInsets.only(top: 4), child: _hint(subtitle)),
  trailing:
      trailing ?? const Icon(Icons.chevron_right, size: 21, color: _muted),
  onTap: _noop,
);

Widget _timeline(Occurrence occurrence) => TaskTimelineRow(
  occurrence: occurrence,
  busy: false,
  hasProAccess: true,
  onTap: _noop,
  onToggle: _noop,
  onStart: _noop,
);

Widget _detailBody({bool condensed = false}) => _content([
  _title('에어컨 필터 청소', size: 24),
  _gap(8),
  _hint('10월 27일 (화) · 오후 12:00'),
  _gap(14),
  const Row(
    children: [
      CategoryLabel(category: '생활', label: '생활'),
      SizedBox(width: 16),
      Text('보통', style: TextStyle(fontSize: 13, color: TaskVisuals.blue)),
    ],
  ),
  if (!condensed) ...[
    _gap(22),
    const Text('필터를 세척한 뒤 완전히 말리기'),
    _gap(18),
    _outline([
      const Row(
        children: [
          Icon(Icons.notifications_outlined, size: 21),
          SizedBox(width: 9),
          Expanded(
            child: Text('다음 알림', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          Icon(Icons.check_circle_outline, size: 16, color: _muted),
          SizedBox(width: 4),
          Text('예약됨', style: TextStyle(fontSize: 12, color: _muted)),
        ],
      ),
      _gap(12),
      _title('10월 27일 (화) 오후 12:00', size: 17),
      _gap(8),
      _hint('미완료라면 다음 날 같은 시각에 다시 알려요.'),
      _gap(12),
      const Divider(height: 1, color: _line),
      _settingRow(
        Icons.tune_rounded,
        '알림 상태 확인',
        subtitle: '기기 알림 허용 · Pro 이용 중',
      ),
    ]),
    _gap(24),
    Row(
      children: [
        Expanded(
          child: FilledButton(onPressed: _noop, child: const Text('지금 시작')),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(onPressed: _noop, child: const Text('완료했어요')),
        ),
      ],
    ),
    _gap(14),
    OutlinedButton.icon(
      onPressed: _noop,
      icon: const Icon(Icons.snooze_outlined, size: 19),
      label: const Text('다시 알림 시간 바꾸기'),
    ),
    _gap(14),
    _hint('집중 모드 등 기기 설정에 따라 표시 방식은 달라질 수 있어요.'),
  ],
]);

Widget _reminder() => _screen(
  '할 일 상세',
  _detailBody(),
  back: true,
  actions: [
    IconButton(
      onPressed: _noop,
      icon: const Icon(Icons.edit_outlined),
      tooltip: '수정',
    ),
  ],
);

Widget _search() => _screen(
  '예정',
  _content([
    const TextField(
      readOnly: true,
      decoration: InputDecoration(
        hintText: '필터',
        prefixIcon: Icon(Icons.search),
        suffixIcon: Icon(Icons.close, size: 19),
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    ),
    _gap(12),
    Row(
      children: [
        FilterChip(
          selected: true,
          onSelected: (_) {},
          avatar: const Icon(Icons.home_outlined, size: 16),
          label: const Text('생활'),
        ),
        const Spacer(),
        TextButton(onPressed: _noop, child: const Text('필터 초기화')),
      ],
    ),
    _gap(16),
    _hint('검색 결과 1개'),
    _gap(22),
    _title('10월 27일 (화)', size: 17),
    _gap(4),
    _timeline(_occurrence('filter', '에어컨 필터 청소')),
    _gap(20),
    _hint('제목과 메모에서 찾고 있어요.'),
  ]),
  navigation: 1,
);

Widget _snooze() => Stack(
  children: [
    _screen('할 일 상세', _detailBody(condensed: true), back: true),
    Positioned.fill(
      child: ColoredBox(color: Colors.black.withValues(alpha: .22)),
    ),
    Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xffd3d6d9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                _gap(22),
                _title('언제 다시 알려드릴까요?'),
                _gap(8),
                _hint('에어컨 필터 청소'),
                _gap(22),
                Row(
                  children: [
                    for (final label in ['10분 뒤', '30분 뒤', '1시간 뒤']) ...[
                      if (label != '10분 뒤') const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _noop,
                          child: Text(label),
                        ),
                      ),
                    ],
                  ],
                ),
                _gap(16),
                _settingRow(
                  Icons.wb_sunny_outlined,
                  '내일 오후 12:00',
                  subtitle: '10월 28일 (수) · 같은 시각',
                ),
                const Divider(height: 1, color: _line),
                _settingRow(Icons.calendar_today_outlined, '날짜와 시간 직접 선택'),
                _gap(18),
                _hint('이번 회차의 알림만 바뀌어요.\n반복 일정과 다음 회차는 그대로 유지돼요.'),
                _gap(16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(onPressed: _noop, child: const Text('취소')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ],
);

Widget _backup() => _screen(
  '설정',
  _content([
    _title('내 데이터'),
    _gap(8),
    _hint('데이터는 이 기기에 저장돼요.'),
    _gap(18),
    _settingRow(
      Icons.file_upload_outlined,
      '백업 파일 만들기',
      subtitle: '할 일·메모·반복·완료 기록을 함께 저장',
    ),
    _gap(8),
    _outline([
      _label('최근 백업'),
      const Text('10월 26일 오전 9:00'),
      _gap(4),
      _hint('내가 선택한 위치에 파일로 저장했어요.'),
    ]),
    _gap(16),
    _settingRow(
      Icons.file_download_outlined,
      '백업 파일 가져오기',
      subtitle: '미리 내용을 확인한 뒤 적용해요.',
    ),
    _divider(),
    _settingRow(Icons.delete_outline, '휴지통', subtitle: '삭제한 할 일 2개 · 30일 보관'),
    _gap(24),
    _hint('백업 파일에는 할 일과 메모가 포함돼요.\n보관할 위치와 공유 대상을 직접 확인해주세요.'),
  ]),
  navigation: 4,
);

Widget _field(String label, Widget child) => InputDecorator(
  decoration: InputDecoration(
    labelText: label,
    floatingLabelBehavior: FloatingLabelBehavior.always,
  ),
  child: ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 24),
    child: child,
  ),
);

Widget _repeat() => _screen(
  '반복 설정',
  _content([
    _title('이번 주 업무 정리'),
    _gap(8),
    _hint('이번부터 앞으로 적용'),
    _gap(24),
    _field(
      '반복',
      const Row(
        children: [
          Expanded(child: Text('매주 · 요일 선택')),
          Icon(Icons.keyboard_arrow_down, size: 22),
        ],
      ),
    ),
    _gap(18),
    Row(
      children: [
        Expanded(child: _field('반복 간격', const Text('2주마다'))),
        const SizedBox(width: 12),
        Expanded(child: _field('시간', const Text('오후 12:00'))),
      ],
    ),
    _gap(14),
    Row(
      children: [
        for (final day in ['월', '화', '수', '목', '금', '토', '일'])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Material(
                color: day == '금' ? TaskVisuals.quietSurface : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: day == '금' ? _ink : _line),
                ),
                child: InkWell(
                  onTap: _noop,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 44,
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          fontWeight: day == '금'
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
    _gap(16),
    _outline([
      _label('다음 3회'),
      for (final date in ['10월 30일 (금)', '11월 13일 (금)', '11월 27일 (금)'])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(date)),
              const Text(
                '오후 12:00',
                style: TextStyle(fontSize: 14, color: _muted),
              ),
            ],
          ),
        ),
    ]),
    _gap(14),
    _hint('2주마다 금요일에 새 회차가 생겨요.\n미완료 재알림은 이 반복과 별도로 적용돼요.'),
  ]),
  back: true,
  footer: SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
    child: FilledButton(onPressed: _noop, child: const Text('저장')),
  ),
);

Widget _selectionRow(Occurrence occurrence) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 15),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 0),
        child: SizedBox(
          width: 40,
          height: 44,
          child: Checkbox(value: true, onChanged: (_) {}),
        ),
      ),
      const SizedBox(width: 5),
      const Padding(
        padding: EdgeInsets.only(top: 10),
        child: SizedBox(
          width: 54,
          child: Text(
            '오후 12:00',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                occurrence.task.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
              _gap(8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CategoryLabel(
                    category: occurrence.task.category,
                    label: occurrence.task.category,
                  ),
                  const Text(
                    '보통',
                    style: TextStyle(fontSize: 12, color: TaskVisuals.blue),
                  ),
                  if (occurrence.task.repeat != RepeatUnit.none)
                    const Icon(Icons.repeat_rounded, size: 16, color: _muted),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  ),
);

Widget _bulk() => _screen(
  '2개 선택됨',
  _content([
    _hint('선택한 할 일에 함께 적용해요.'),
    _gap(20),
    _title('10월 27일 (화)', size: 17),
    _gap(6),
    _selectionRow(_occurrence('filter', '에어컨 필터 청소')),
    const Divider(height: 1, color: _line),
    _gap(26),
    _title('10월 30일 (금)', size: 17),
    _gap(6),
    _selectionRow(
      _occurrence(
        'weekly-review',
        '이번 주 업무 정리',
        day: 30,
        category: '업무',
        repeat: RepeatUnit.weekly,
      ),
    ),
    const Divider(height: 1, color: _line),
    _gap(18),
    _hint('선택한 2개에 같은 작업을 적용해요.\n반복 일정은 적용 범위를 한 번 더 확인해요.'),
  ]),
  actions: [TextButton(onPressed: _noop, child: const Text('취소'))],
  footer: SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _noop,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('완료'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(onPressed: _noop, child: const Text('날짜 변경')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(onPressed: _noop, child: const Text('분류 변경')),
        ),
      ],
    ),
  ),
);

Widget _trashItem(String title, String subtitle, {String? scope}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_title(title, size: 17), _gap(7), _hint(subtitle)],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(onPressed: _noop, child: const Text('복구')),
        ],
      ),
      if (scope != null) ...[_gap(12), _hint(scope)],
    ],
  ),
);

Widget _trash() => _screen(
  '휴지통',
  _content([
    _title('삭제한 할 일 2개'),
    _gap(8),
    _hint('삭제한 날부터 30일 동안 복구할 수 있어요.'),
    _gap(18),
    _trashItem('에어컨 필터 청소', '10월 26일 삭제 · 30일 남음', scope: '할 일과 메모를 함께 복구해요.'),
    const Divider(height: 1, color: _line),
    _trashItem(
      '이번 주 업무 정리',
      '10월 25일 삭제 · 29일 남음',
      scope: '반복 일정 전체를 삭제했어요. 복구하면 해당 범위의 일정과 기록을 함께 복구해요.',
    ),
    const Divider(height: 1, color: _line),
    _gap(24),
    _hint('복구 전에 알림 시각을 확인해요.\n이미 지난 알림을 한꺼번에 보내지 않아요.'),
  ]),
  back: true,
);

Widget _empty() => _screen(
  '예정',
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _gap(80),
        const Icon(Icons.calendar_today_outlined, size: 32, color: _muted),
        _gap(22),
        _title('아직 예정된 할 일이 없어요.', size: 22),
        _gap(12),
        _hint('기억해둘 일 하나만 적어보세요.\n날짜와 시간을 정하면 그때 알려드려요.'),
        _gap(28),
        FilledButton.icon(
          onPressed: _noop,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('첫 할 일 추가'),
        ),
      ],
    ),
  ),
  navigation: 1,
  actions: [
    IconButton(onPressed: _noop, icon: const Icon(Icons.search), tooltip: '검색'),
  ],
);

Widget _radioOption(String title, String subtitle, bool selected) => InkWell(
  onTap: _noop,
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 15),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 22,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              _gap(5),
              _hint(subtitle),
            ],
          ),
        ),
      ],
    ),
  ),
);

Widget _privacy() => _screen(
  '알림 내용',
  _content([
    _title('잠금 화면의 알림 내용'),
    _gap(8),
    _hint('주변에서 알림 내용을 볼 수 있다면\n제목을 숨겨둘 수 있어요.'),
    _gap(22),
    _radioOption('제목 표시', '에어컨 필터 청소처럼 할 일 이름을 보여요.', false),
    const Divider(height: 1, color: _line),
    _radioOption('제목 숨기기', '앱을 열었을 때 할 일 내용을 확인해요.', true),
    _gap(24),
    _label('알림 내용 예시'),
    _outline([
      const Row(
        children: [
          Icon(Icons.notifications_none_outlined, size: 19),
          SizedBox(width: 8),
          Text(
            '투두닉',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      _gap(12),
      _title('처리할 일이 있어요.', size: 17),
      _gap(5),
      const Text(
        '앱을 열어 확인해주세요.',
        style: TextStyle(fontSize: 14, color: _muted),
      ),
    ]),
    _gap(14),
    _hint('위 내용은 앱 안의 예시예요. 실제 표시 방식은 기기 알림 설정에 따라 달라져요.'),
  ]),
  back: true,
);

Widget _scene(String name) => switch (name) {
  'reminder' => _reminder(),
  'search' => _search(),
  'snooze' => _snooze(),
  'backup' => _backup(),
  'repeat' => _repeat(),
  'bulk' => _bulk(),
  'trash' => _trash(),
  'empty' => _empty(),
  'privacy' => _privacy(),
  _ => throw ArgumentError.value(name),
};

void main() {
  testWidgets('review-only improvement proposals render in both phone sizes', (
    tester,
  ) async {
    // This opt-in capture is a Flutter test outside test/.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          WidgetService.channel,
          (call) async => call.method == 'getCalendarPreferences'
              ? {'regionCode': 'KR', 'firstDayOfWeek': 0}
              : null,
        );
    await (FontLoader(
      'Pretendard',
    )..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final controller = PreviewController();
    final subscription = PreviewSubscription();
    await controller.localeController.setPreference('ko');
    await tester.pumpWidget(
      HangeoreumApp(controller: controller, subscription: subscription),
    );
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.byType(NavigationBar)));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.dispose();
    subscription.dispose();
    final captures = <Map<String, Object?>>[];
    for (final device in _devices) {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = Size(device.width * 2, device.height * 2);
      tester.view.padding = FakeViewPadding(
        top: device.top * 2,
        bottom: device.bottom * 2,
      );
      for (final scene in _scenes) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              locale: const Locale('ko'),
              supportedLocales: const [Locale('ko'), Locale('en')],
              localizationsDelegates: const [
                AppStrings.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: _scene(scene),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${device.name}/$scene layout',
        );
        final png = await tester.runAsync(() async {
          final rendered =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await rendered.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          return data!.buffer.asUint8List();
        });
        final filename = '${device.name}-tobe-$scene.png';
        await tester.runAsync(() async {
          final file = File('$_output/$filename');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png!, flush: true);
        });
        captures.add({
          'file': filename,
          'scene': scene,
          'device': device.name,
          'logicalWidth': device.width,
          'logicalHeight': device.height,
          'safeTop': device.top,
          'safeBottom': device.bottom,
          'pixelRatio': 2,
          'scenarioDate': scene == 'snooze' ? '2026-10-27' : '2026-10-26',
          if (scene == 'snooze')
            'scenarioNote': '10월 27일의 회차를 10월 28일 오후 12시로 미루는 검토용 상황',
          'reviewOnly': true,
          'shippingImplementation': false,
          'physicalDeviceScreenshot': false,
          'osNotificationCapture': false,
        });
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WidgetService.channel, null);
    await tester.runAsync(
      () => File('$_output/proposal-manifest.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'createdFor': '2026-10-26 improvement comparison',
          'captureType': 'review-only Flutter widget rendering',
          'productionThemeReused': true,
          'productionWidgetsReused': [
            'TaskTimelineRow',
            'TaskVisuals',
            'CategoryLabel',
          ],
          'functionalityImplemented': false,
          'captures': captures,
        }),
        flush: true,
      ),
    );
    expect(captures.length, 18);
  }, skip: !_enabled);
}
