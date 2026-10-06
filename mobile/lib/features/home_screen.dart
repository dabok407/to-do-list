import 'package:flutter/material.dart';

import '../app/task_controller.dart';
import '../domain/task.dart';
import 'task_editor.dart';

const priorityRed = Color(0xff8f303a);
const stateNames = ['예정', '진행 중', '보류', '완료', '건너뜀'];
String timeLabel(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class HomeScreen extends StatefulWidget {
  final TaskController controller;
  const HomeScreen({super.key, required this.controller});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  DateTime selected = dayOf(DateTime.now()),
      month = DateTime(DateTime.now().year, DateTime.now().month);
  int page = 0, summary = 0;
  bool week = false, busy = false;
  TaskController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) run(c.reconcile);
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('처리하지 못했습니다. 다시 시도해주세요.')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([Task? task]) async {
    final result = await Navigator.push<Task>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskEditor(task: task, initialDate: selected),
      ),
    );
    if (result != null) await run(() => c.save(result));
  }

  Future<void> detail(Occurrence original) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => ListenableBuilder(
        listenable: c,
        builder: (ctx, _) {
          final o = c.items.where((x) => x.id == original.id).firstOrNull;
          if (o == null) return const SizedBox.shrink();
          return FractionallySizedBox(
            heightFactor: .9,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                      tooltip: '닫기',
                    ),
                  ),
                  Text(
                    o.task.title,
                    style: Theme.of(ctx).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${dayKey(o.originalDue)} · ${timeLabel(o.originalDue)} · ${stateNames[o.status.index]}',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  if (o.task.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(o.task.note),
                    ),
                  if (o.status == TaskStatus.paused ||
                      o.status == TaskStatus.progressing)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        '다시 확인할 시간: ${dayKey(o.reminder)} ${timeLabel(o.reminder)}',
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (o.active) ...[
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: busy
                                ? null
                                : () => run(() => c.act(o, 'start')),
                            child: const Text('지금 시작'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => run(() => c.act(o, 'complete')),
                            child: const Text('완료했어요'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text('지금 어렵다면', style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [10, 30, 60]
                          .map(
                            (m) => OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => run(
                                      () => c.act(o, 'snooze', minutes: m),
                                    ),
                              child: Text(m == 60 ? '1시간 뒤' : '$m분 뒤'),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => run(() => c.act(o, 'snooze', minutes: 120)),
                      child: const Text('오늘 나중에 · 2시간 뒤'),
                    ),
                    FutureBuilder<int>(
                      future: c.repository.todaySnoozes(o.id),
                      builder: (ctx, s) {
                        if ((s.data ?? 0) < 3) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(top: 20),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xfff6f2ed),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('오늘 ${s.data}번째 미루고 있어요.\n5분만 해볼까요?'),
                              const SizedBox(height: 10),
                              Text(
                                o.task.smallStep.isEmpty
                                    ? '준비물 하나 꺼내기부터 시작해요.'
                                    : o.task.smallStep,
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => run(() => c.act(o, 'small')),
                                child: const Text('5분 시작'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => run(() => c.act(o, 'skip')),
                      child: const Text('오늘 못함 · 이번 회차 건너뛰기'),
                    ),
                  ],
                  if (o.status == TaskStatus.completed)
                    OutlinedButton(
                      onPressed: () => run(() => c.act(o, 'uncomplete')),
                      child: const Text('완료 해제'),
                    ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          edit(o.task);
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('수정'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: ctx,
                            builder: (d) => AlertDialog(
                              title: const Text('할 일을 삭제할까요?'),
                              content: const Text('이 할 일의 반복 일정과 기록도 삭제됩니다.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(d, false),
                                  child: const Text('취소'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(d, true),
                                  child: const Text('삭제'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await run(() => c.delete(o.task));
                            if (ctx.mounted) Navigator.pop(ctx);
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('삭제'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget row(Occurrence o) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 5),
    leading: IconButton(
      tooltip: o.status == TaskStatus.completed ? '완료 해제' : '완료 처리',
      onPressed: busy || o.status == TaskStatus.skipped
          ? null
          : () => run(
              () => c.act(
                o,
                o.status == TaskStatus.completed ? 'uncomplete' : 'complete',
              ),
            ),
      icon: Icon(
        o.status == TaskStatus.completed
            ? Icons.check_circle
            : Icons.radio_button_unchecked,
        color: o.status == TaskStatus.completed
            ? Colors.grey
            : const Color(0xffb6bec9),
      ),
    ),
    title: Text(
      o.task.title,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: o.status == TaskStatus.completed ? Colors.grey : null,
        decoration: o.status == TaskStatus.completed
            ? TextDecoration.lineThrough
            : null,
      ),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        children: [
          if (o.task.priority == 2)
            const Text('● 높음', style: TextStyle(color: priorityRed)),
          Text(stateNames[o.status.index]),
          if (o.task.repeat != RepeatUnit.none) const Text('· 반복'),
          if (o.status == TaskStatus.paused)
            Text('· ${timeLabel(o.reminder)} 재알림'),
        ],
      ),
    ),
    trailing: Text(timeLabel(o.originalDue)),
    onTap: () => detail(o),
  );
  Widget calendar() {
    final first = week
        ? selected.subtract(Duration(days: selected.weekday - 1))
        : DateTime(month.year, month.month);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final count = week
        ? 7
        : ((first.weekday - 1 + DateTime(month.year, month.month + 1, 0).day) /
                      7)
                  .ceil() *
              7;
    final now = dayOf(DateTime.now());
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffe6eaf0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${month.year}년 ${month.month}월',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '이전',
                  onPressed: () => move(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: '다음',
                  onPressed: () => move(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Row(
            children: List.generate(
              7,
              (i) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: Text(
                      ['월', '화', '수', '목', '금', '토', '일'][i],
                      style: TextStyle(
                        color: i == 6 ? priorityRed : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: week ? 82 : 62,
            ),
            itemCount: count,
            itemBuilder: (ctx, i) {
              final d = DateTime(start.year, start.month, start.day + i),
                  all = c.items
                      .where((o) => dayOf(o.originalDue) == d)
                      .toList();
              return Semantics(
                label: '${dayKey(d)}, 할 일 ${all.length}개',
                selected: d == selected,
                child: InkWell(
                  onTap: () => setState(() => selected = d),
                  child: Container(
                    decoration: BoxDecoration(
                      color: d == selected ? const Color(0xfff1f5ff) : null,
                      border: Border.all(
                        color: const Color(0xffedf0f4),
                        width: .5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: d == now ? const Color(0xff3569ed) : null,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 13,
                              color: d == now
                                  ? Colors.white
                                  : d.month != month.month
                                  ? Colors.grey.shade400
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: all
                              .take(4)
                              .map(
                                (o) => Container(
                                  width: 4,
                                  height: 4,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: o.status == TaskStatus.completed
                                        ? Colors.grey.shade400
                                        : o.task.priority == 2
                                        ? priorityRed
                                        : const Color(0xff859abd),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '● 높은 우선순위',
              style: TextStyle(color: priorityRed, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  void move(int n) {
    setState(() {
      if (week) {
        selected = DateTime(
          selected.year,
          selected.month,
          selected.day + n * 7,
        );
        month = DateTime(selected.year, selected.month);
      } else {
        month = DateTime(month.year, month.month + n);
        selected = month;
      }
    });
    run(() => c.refresh(through: DateTime(month.year, month.month + 1, 0)));
  }

  Widget calendarPage() {
    final todays = c.items
        .where((o) => dayOf(o.originalDue) == selected)
        .toList();
    final today = dayOf(DateTime.now()),
        begin = summary == 0
            ? today
            : summary == 1
            ? today.subtract(Duration(days: today.weekday - 1))
            : DateTime(today.year, today.month);
    final end = summary == 0
        ? begin
        : summary == 1
        ? begin.add(const Duration(days: 6))
        : DateTime(today.year, today.month + 1, 0);
    final summarized = c.items
        .where(
          (o) =>
              !dayOf(o.originalDue).isBefore(begin) &&
              !dayOf(o.originalDue).isAfter(end),
        )
        .toList();
    final next = c.queue.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          children: List.generate(
            3,
            (i) => ChoiceChip(
              label: Text(['오늘', '이번 주', '이번 달'][i]),
              selected: summary == i,
              onSelected: (_) => setState(() => summary = i),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${summarized.where((o) => o.active).length}개 남음 · ${summarized.where((o) => o.status == TaskStatus.completed).length}개 완료',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            TextButton(
              onPressed: () {
                setState(() {
                  selected = today;
                  month = DateTime(today.year, today.month);
                });
              },
              child: const Text('오늘로'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => week = !week),
              child: Text(week ? '월 보기' : '주 보기'),
            ),
          ],
        ),
        calendar(),
        if (next != null)
          Container(
            margin: const EdgeInsets.only(top: 20),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xffedf3ff),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '다음 한 가지',
                  style: TextStyle(color: Color(0xff6580ad)),
                ),
                const SizedBox(height: 10),
                Text(
                  next.task.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => run(() => c.act(next, 'start')),
                      child: const Text('지금 시작'),
                    ),
                    OutlinedButton(
                      onPressed: () => detail(next),
                      child: const Text('상태 확인'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 28),
        Text(
          '${selected.month}월 ${selected.day}일',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (todays.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('예정된 할 일이 없어요. 새로운 할 일을 추가해보세요.'),
          ),
        ...todays.map(row),
      ],
    );
  }

  Widget statsPage() {
    final s = c.statistics;
    final total = s['total'] as int? ?? 0, done = s['completed'] as int? ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('최근 30일', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        ...{
          '등록한 할 일': '${s['registered'] ?? 0}개',
          '완료한 회차': '$done개',
          '완료율': total == 0 ? '기록 없음' : '${(done / total * 100).round()}%',
          '미룬 횟수': '${s['snoozes'] ?? 0}회',
          '평균 미룬 시간': '${((s['average'] as num?) ?? 0).round()}분',
          '자주 완료한 시간대': '${s['hour'] ?? '기록 없음'}',
        }.entries.map(
          (e) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e.key),
            trailing: Text(
              e.value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '완료율은 최근 30일 동안 예정 시간이 지난 회차를 기준으로 계산합니다. 반복 일정의 각 회차를 별도로 집계합니다.',
        ),
      ],
    );
  }

  Widget settingsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '데이터는 이 기기에만 저장됩니다. 회원가입·서버·클라우드 동기화가 없습니다. 앱 삭제 또는 기기 변경 시 기록이 사라질 수 있습니다.',
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: () async {
          await run(() async {
            await c.reminders.requestPermissions();
            await c.reconcile();
          });
        },
        icon: const Icon(Icons.notifications_outlined),
        label: const Text('알림 권한 설정'),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => run(c.reminders.requestExactPermission),
        child: const Text('Android 정확한 알림 설정'),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => run(c.reminders.testNotification),
        child: const Text('10초 뒤 테스트 알림'),
      ),
      const SizedBox(height: 20),
      const Text(
        '보류 후에는 선택한 시간에 다시 알립니다. 진행 중 확인은 30분 뒤, 작은 시작 확인은 5분 뒤입니다. 권한·집중 모드·배터리 설정에 따라 알림 전달이 달라질 수 있습니다.',
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(['캘린더', '예정된 할 일', '완료한 일', '나의 흐름', '설정'][page]),
      actions: [
        if (busy)
          const Padding(
            padding: EdgeInsets.all(18),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: c.reconcile,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          if (c.warning != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                c.warning!,
                style: const TextStyle(color: priorityRed),
              ),
            ),
          if (page == 0) calendarPage(),
          if (page == 1) ...c.queue.map(row),
          if (page == 2)
            ...c.items
                .where((o) => o.status == TaskStatus.completed)
                .toList()
                .reversed
                .map(row),
          if (page == 3) statsPage(),
          if (page == 4) settingsPage(),
        ],
      ),
    ),
    floatingActionButton: page < 3
        ? FloatingActionButton(
            onPressed: () => edit(),
            tooltip: '할 일 추가',
            child: const Icon(Icons.add),
          )
        : null,
    bottomNavigationBar: NavigationBar(
      selectedIndex: page,
      onDestinationSelected: (i) => setState(() => page = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          label: '캘린더',
        ),
        NavigationDestination(icon: Icon(Icons.list_alt_outlined), label: '예정'),
        NavigationDestination(
          icon: Icon(Icons.check_circle_outline),
          label: '완료',
        ),
        NavigationDestination(
          icon: Icon(Icons.bar_chart_outlined),
          label: '통계',
        ),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: '설정'),
      ],
    ),
  );
}
