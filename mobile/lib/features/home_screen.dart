import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/task_controller.dart';
import '../domain/task.dart';
import 'task_editor.dart';
import 'pro_screen.dart';
import 'privacy_card.dart';
import 'store_policy_links.dart';
import '../services/subscription_service.dart';
import '../l10n/app_strings.dart';

const mutedText = Color(0xff626873);
const priorityRed = Color(0xff8f303a);
const categoryColors = {
  '생활': Color(0xffad5618),
  '업무': Color(0xff315dca),
  '건강': Color(0xff267447),
  '배움': Color(0xff7546ba),
};
const stateNames = ['예정', '진행 중', '보류', '완료', '건너뜀'];
String timeLabel(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class HomeScreen extends StatefulWidget {
  final TaskController controller;
  final SubscriptionService? subscription;
  const HomeScreen({super.key, required this.controller, this.subscription});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  DateTime selected = dayOf(DateTime.now()),
      month = DateTime(DateTime.now().year, DateTime.now().month);
  int page = 0, summary = 0;
  bool week = false, busy = false;
  bool detailVisible = false;
  late final subscription = widget.subscription ?? SubscriptionService();
  final quickTitle = TextEditingController();
  final bodyScroll = ScrollController();
  Timer? clockRefresh;
  String quickCategory = '생활';
  TaskController get c => widget.controller;
  AppStrings get strings => AppStrings.of(context);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(changed);
    subscription.addListener(subscriptionChanged);
    clockRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
        if (c.access != null) run(c.reconcile);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      openRequestedTask();
      subscription.refresh();
    });
  }

  void subscriptionChanged() {
    changed();
    if (!subscription.busy && c.access != null) {
      c.reconcile().catchError((Object _) {});
    }
  }

  Future<void> taskAction(
    Occurrence o,
    String action, {
    int minutes = 10,
  }) async {
    if ({'start', 'small', 'snooze'}.contains(action) &&
        !subscription.hasAccess) {
      openPro();
      return;
    }
    await run(() => c.act(o, action, minutes: minutes));
  }

  void changed() {
    if (mounted) setState(() {});
    if (mounted && c.pendingOpenId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openRequestedTask());
    }
  }

  void openRequestedTask() {
    if (!mounted || detailVisible || c.pendingOpenId == null) return;
    final id = c.pendingOpenId;
    c.pendingOpenId = null;
    final occurrence = c.items.where((o) => o.id == id).firstOrNull;
    if (occurrence == null) return;
    setState(() {
      page = 0;
      selected = dayOf(occurrence.originalDue);
      month = DateTime(selected.year, selected.month);
    });
    detail(occurrence);
  }

  @override
  void dispose() {
    c.removeListener(changed);
    subscription.removeListener(subscriptionChanged);
    if (widget.subscription == null) subscription.dispose();
    quickTitle.dispose();
    bodyScroll.dispose();
    clockRefresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      run(c.reconcile);
      subscription.refresh();
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.t('처리하지 못했습니다. 다시 시도해주세요.'))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([Task? task, Occurrence? occurrence]) async {
    bool? onlyThis;
    if (occurrence != null && task!.repeat != RepeatUnit.none) {
      onlyThis = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          bool? choice;
          return StatefulBuilder(
            builder: (ctx, setChoice) => AlertDialog(
              title: Text(strings.t('어떤 일정을 수정할까요?')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.t('이번 일정만')),
                    value: choice == true,
                    onChanged: (v) =>
                        setChoice(() => choice = v == true ? true : null),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.t('이번부터 앞으로')),
                    value: choice == false,
                    onChanged: (v) =>
                        setChoice(() => choice = v == true ? false : null),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(strings.t('취소')),
                ),
                FilledButton(
                  onPressed: choice == null
                      ? null
                      : () => Navigator.pop(ctx, choice),
                  child: Text(strings.t('계속')),
                ),
              ],
            ),
          );
        },
      );
      if (onlyThis == null || !mounted) return;
      task = Task.fromMap({
        ...task.toMap(),
        'due': occurrence.originalDue.toIso8601String(),
        if (onlyThis) 'repeat_unit': 'none',
        if (onlyThis) 'end_date': null,
      });
    }
    if (!mounted) return;
    final result = await Navigator.push<Task>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskEditor(
          task: task,
          initialDate: selected,
          premium: subscription.hasAccess,
        ),
      ),
    );
    if (result != null) {
      await run(
        () => onlyThis != null
            ? c.editOccurrence(occurrence!, result, onlyThis: onlyThis)
            : c.save(result),
      );
    }
  }

  Future<void> detail(Occurrence original) async {
    if (detailVisible) return;
    detailVisible = true;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => ListenableBuilder(
        listenable: Listenable.merge([c, subscription]),
        builder: (ctx, _) {
          final o = c.items.where((x) => x.id == original.id).firstOrNull;
          if (o == null) return const SizedBox.shrink();
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * .86,
            ),
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
                      tooltip: strings.t('닫기'),
                    ),
                  ),
                  Text(
                    o.task.title,
                    style: Theme.of(ctx).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${strings.date(o.originalDue)} · ${strings.time(o.originalDue)} · ${strings.t(stateNames[o.status.index])}',
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
                        strings.t(
                          '다시 확인할 시간: {date} {time}',
                          args: {
                            'date': strings.date(o.reminder),
                            'time': strings.time(o.reminder),
                          },
                        ),
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
                                : () => taskAction(o, 'start'),
                            child: Text(strings.t('지금 시작')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => run(() => c.act(o, 'complete')),
                            child: Text(strings.t('완료했어요')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    const Divider(),
                    const SizedBox(height: 16),
                    if (!subscription.hasAccess) ...[
                      Text(
                        strings.t(
                          '알림·미루기·실행 보조는 Pro 기능이에요. 완료와 일정 수정은 계속 사용할 수 있어요.',
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      strings.t('지금 어렵다면'),
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [10, 30, 60]
                          .map(
                            (m) => OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => taskAction(o, 'snooze', minutes: m),
                              child: Text(
                                m == 60
                                    ? strings.t('1시간 뒤')
                                    : strings.t('{n}분 뒤', args: {'n': m}),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () {
                              final now = DateTime.now();
                              final remaining = DateTime(
                                now.year,
                                now.month,
                                now.day,
                                23,
                                59,
                              ).difference(now).inMinutes;
                              if (remaining < 1) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      strings.t('오늘 남은 시간이 없어요. 날짜를 변경해주세요.'),
                                    ),
                                  ),
                                );
                                return;
                              }
                              taskAction(
                                o,
                                'snooze',
                                minutes: remaining < 120 ? remaining : 120,
                              );
                            },
                      child: Text(strings.t('오늘 나중에')),
                    ),
                    FutureBuilder<int>(
                      future: c.repository.todaySnoozes(o.id),
                      builder: (ctx, s) {
                        if ((s.data ?? 0) < 3) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(top: 20),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xfff1f2f4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.t(
                                  '오늘 {n}번째 미루고 있어요.\n5분만 해볼까요?',
                                  args: {'n': s.data ?? 0},
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                o.task.smallStep.isEmpty
                                    ? strings.t('준비물 하나 꺼내기부터 시작해요.')
                                    : o.task.smallStep,
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => taskAction(o, 'small'),
                                child: Text(strings.t('5분 시작')),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => run(() => c.act(o, 'skip')),
                      child: Text(strings.t('오늘 못함 · 이번 회차 건너뛰기')),
                    ),
                  ],
                  if (o.status == TaskStatus.completed)
                    OutlinedButton(
                      onPressed: () => run(() => c.act(o, 'uncomplete')),
                      child: Text(strings.t('완료 해제')),
                    ),
                  if (o.status == TaskStatus.skipped && !o.quotaSkipped)
                    OutlinedButton(
                      onPressed: () => run(() => c.act(o, 'unskip')),
                      child: Text(strings.t('다시 할 일로')),
                    ),
                  if (o.task.repeat == RepeatUnit.weeklyGoal)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        o.quotaSkipped
                            ? strings.t('이번 주 목표를 채웠어요. 다음 주에 다시 시작해요.')
                            : strings.t(
                                '요일 자유 · 주 {n}회 목표',
                                args: {'n': o.task.countPerWeek},
                              ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          edit(o.task, o);
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(strings.t('수정')),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          final scope = await showDialog<String>(
                            context: ctx,
                            builder: (d) => AlertDialog(
                              title: Text(strings.t('할 일을 삭제할까요?')),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(strings.t('선택한 범위의 일정과 기록이 삭제됩니다.')),
                                  const SizedBox(height: 12),
                                  ListTile(
                                    title: Text(strings.t('이번 일정만 삭제')),
                                    onTap: () => Navigator.pop(d, 'this'),
                                  ),
                                  if (o.task.repeat != RepeatUnit.none ||
                                      o.task.derived) ...[
                                    ListTile(
                                      title: Text(strings.t('이번부터 앞으로 삭제')),
                                      onTap: () => Navigator.pop(d, 'future'),
                                    ),
                                    ListTile(
                                      title: Text(strings.t('전체 반복과 기록 삭제')),
                                      onTap: () => Navigator.pop(d, 'series'),
                                    ),
                                  ],
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(d),
                                  child: Text(strings.t('취소')),
                                ),
                              ],
                            ),
                          );
                          if (scope != null) {
                            await run(
                              () => c.deleteOccurrence(o, scope: scope),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: Text(strings.t('삭제')),
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
    detailVisible = false;
    openRequestedTask();
  }

  Widget row(Occurrence o) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 5),
    leading: IconButton(
      tooltip: o.status == TaskStatus.completed
          ? strings.t('완료 해제')
          : strings.t('완료 처리'),
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
            ? mutedText
            : o.task.priority == 2
            ? priorityRed
            : categoryColors[o.task.category],
      ),
    ),
    title: Text(
      o.task.title,
      style: TextStyle(
        fontWeight: FontWeight.w500,
        color: o.status == TaskStatus.completed ? mutedText : null,
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
            Text(strings.t('● 높음'), style: TextStyle(color: priorityRed)),
          Text(
            o.quotaSkipped
                ? strings.t('이번 주 목표 달성')
                : strings.t(stateNames[o.status.index]),
          ),
          if (page != 0) Text('· ${strings.date(o.originalDue)}'),
          if (o.task.repeat != RepeatUnit.none) Text(strings.t('· 반복')),
          if (o.status == TaskStatus.paused)
            Text(
              strings.t(
                '· {time} 재알림',
                args: {'time': strings.time(o.reminder)},
              ),
            ),
        ],
      ),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          strings.time(o.originalDue),
          style: const TextStyle(fontSize: 12, color: Color(0xff626873)),
        ),
        if (o.active && o.status != TaskStatus.progressing)
          IconButton(
            key: ValueKey('start-${o.id}'),
            tooltip: strings.t(
              '{title} 지금 시작{pro}',
              args: {
                'title': o.task.title,
                'pro': subscription.hasAccess ? '' : ' · Pro',
              },
            ),
            onPressed: busy ? null : () => taskAction(o, 'start'),
            icon: Icon(
              subscription.hasAccess
                  ? Icons.play_arrow_rounded
                  : Icons.lock_outline,
              size: 23,
            ),
          ),
      ],
    ),
    onTap: () => detail(o),
  );
  Widget calendar() {
    final daySize =
        26.0 *
        (MediaQuery.textScalerOf(context).scale(13) / 13).clamp(1.0, 1.6);
    final first = week ? weekOf(selected) : DateTime(month.year, month.month);
    final start = weekOf(first);
    final count = week
        ? 7
        : ((first.weekday - 1 + DateTime(month.year, month.month + 1, 0).day) /
                      7)
                  .ceil() *
              7;
    final now = dayOf(DateTime.now());
    final scale = (MediaQuery.textScalerOf(context).scale(11) / 11).clamp(
      1.0,
      1.6,
    );
    final reservedHeight = c.overdue.isEmpty ? 300 : 390;
    final cellHeight =
        ((MediaQuery.sizeOf(context).height - reservedHeight) / (count / 7))
            .clamp(60.0, 86.0);
    final previewCount = cellHeight < 82 ? 1 : 2;
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() > 250) move(velocity < 0 ? 1 : -1);
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: const Color(0xffe7e5df))),
        ),
        child: Column(
          children: [
            Row(
              children: List.generate(
                7,
                (i) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Center(
                      child: Text(
                        strings.weekday(i + 1),
                        style: TextStyle(
                          color: i == 6 ? priorityRed : mutedText,
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
                mainAxisExtent: (week ? 48 : cellHeight) * scale,
              ),
              itemCount: count,
              itemBuilder: (ctx, i) {
                final d = DateTime(start.year, start.month, start.day + i),
                    all = c.items
                        .where((o) => dayOf(o.originalDue) == d)
                        .toList();
                all.sort((a, b) {
                  final active = (a.active ? 0 : 1).compareTo(b.active ? 0 : 1);
                  if (active != 0) return active;
                  final priority = b.task.priority.compareTo(a.task.priority);
                  return priority != 0
                      ? priority
                      : a.originalDue.compareTo(b.originalDue);
                });
                return Semantics(
                  label: strings.t(
                    '{date}, 할 일 {n}개',
                    args: {'date': strings.date(d), 'n': all.length},
                  ),
                  selected: d == selected,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        selected = d;
                        month = DateTime(d.year, d.month);
                        week = true;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && bodyScroll.hasClients) {
                          bodyScroll.animateTo(
                            0,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                          );
                        }
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: !week && d == selected
                            ? const Color(0xfff2f3f5)
                            : null,
                        border: week
                            ? null
                            : const Border(
                                top: BorderSide(
                                  color: Color(0xffeae7e0),
                                  width: .5,
                                ),
                              ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Container(
                            width: daySize,
                            height: daySize,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: d == selected
                                  ? const Color(0xff30332e)
                                  : null,
                              border: d == now && d != selected
                                  ? Border.all(color: const Color(0xffaaa99f))
                                  : null,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${d.day}',
                              style: TextStyle(
                                fontSize: 13,
                                color: d == selected
                                    ? Colors.white
                                    : d.month != month.month
                                    ? Colors.grey.shade400
                                    : null,
                              ),
                            ),
                          ),
                          SizedBox(height: previewCount == 1 ? 2 : 6),
                          if (!week)
                            ...all.take(previewCount).map((o) {
                              final color = o.task.priority == 2
                                  ? priorityRed
                                  : categoryColors[o.task.category] ??
                                        mutedText;
                              return Container(
                                width: double.infinity,
                                margin: const EdgeInsets.fromLTRB(2, 0, 2, 3),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: o.active
                                      ? color
                                      : const Color(0xff747a83),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  o.task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    height: 1.1,
                                    color: Colors.white,
                                    decoration: o.status == TaskStatus.completed
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              );
                            }),
                          if (!week && all.length > previewCount)
                            Text(
                              '+${all.length - previewCount}',
                              style: const TextStyle(
                                fontSize: 9,
                                height: 1.1,
                                color: mutedText,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
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

  Future<void> showOverdue() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .7,
        child: ListenableBuilder(
          listenable: c,
          builder: (ctx, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                overdueTitle(c.overdue.length),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(strings.t('예정 시간이 지났지만 아직 완료하지 않은 일이에요.')),
              const SizedBox(height: 16),
              if (c.overdue.isEmpty)
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(strings.t('남은 일을 모두 마쳤어요.')),
                ),
              ...c.overdue.map(
                (o) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.t(
                        '{date} 예정',
                        args: {'date': strings.date(o.originalDue)},
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xff626873),
                      ),
                    ),
                    row(o),
                    const Divider(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget overdueBanner() {
    final remaining = c.overdue;
    if (remaining.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xffb6bbc3)),
        ),
        child: InkWell(
          key: const Key('overdue-banner'),
          borderRadius: BorderRadius.circular(12),
          onTap: showOverdue,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.pending_actions_outlined,
                  size: 22,
                  color: Color(0xff292c29),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        overdueTitle(remaining.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        remaining.length > 1
                            ? strings.t(
                                '{title} 외 {n}개',
                                args: {
                                  'title': remaining.first.task.title,
                                  'n': remaining.length - 1,
                                },
                              )
                            : remaining.first.task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xff626873),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String overdueTitle(int count) => strings.isEnglish && count == 1
      ? strings.t('아직 남은 일 1개')
      : strings.t('아직 남은 일 {n}개', args: {'n': count});

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton(
              onPressed: () {
                setState(() {
                  selected = today;
                  month = DateTime(today.year, today.month);
                });
              },
              child: Text(strings.t('오늘로')),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => week = !week),
              child: Text(week ? strings.t('월 보기') : strings.t('주 보기')),
            ),
          ],
        ),
        calendar(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              PopupMenuButton<int>(
                tooltip: strings.t('요약 기간'),
                initialValue: summary,
                onSelected: (value) => setState(() => summary = value),
                itemBuilder: (_) => List.generate(
                  3,
                  (i) => PopupMenuItem(
                    value: i,
                    child: Text(
                      [
                        strings.t('오늘'),
                        strings.t('이번 주'),
                        strings.t('이번 달'),
                      ][i],
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        [
                          strings.t('오늘'),
                          strings.t('이번 주'),
                          strings.t('이번 달'),
                        ][summary],
                      ),
                      const Icon(Icons.expand_more, size: 18),
                    ],
                  ),
                ),
              ),
              Text(
                strings.t(
                  '{left}개 남음  ·  {done}개 완료',
                  args: {
                    'left': summarized.where((o) => o.active).length,
                    'done': summarized
                        .where((o) => o.status == TaskStatus.completed)
                        .length,
                  },
                ),
                style: const TextStyle(fontSize: 13, color: Color(0xff626873)),
              ),
            ],
          ),
        ),
        if (!week)
          Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              strings.t('날짜를 누르면 그날의 할 일이 바로 펼쳐져요.'),
              style: TextStyle(fontSize: 12, color: Color(0xff626873)),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          strings.dateShort(selected),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (todays.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text(strings.t('예정된 할 일이 없어요. 새로운 할 일을 추가해보세요.')),
          ),
        ...categoryColors.entries.expand((entry) {
          final items = todays
              .where((o) => o.task.category == entry.key)
              .toList();
          if (items.isEmpty) return <Widget>[];
          return <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 2),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 12,
                    decoration: BoxDecoration(
                      color: entry.value,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    strings.category(entry.key),
                    style: TextStyle(
                      color: entry.value,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${items.where((o) => o.status == TaskStatus.completed).length}/${items.length}',
                    style: const TextStyle(fontSize: 12, color: mutedText),
                  ),
                ],
              ),
            ),
            ...items.map(row),
          ];
        }),
        const SizedBox(height: 20),
        ExpansionTile(
          key: const Key('quick-add'),
          title: Text(strings.t('간단히 추가'), style: TextStyle(fontSize: 14)),
          children: [quickAdd()],
        ),
      ],
    );
  }

  void openPro() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ProScreen(subscription: subscription)),
  );

  Future<void> addQuickTask() async {
    final title = quickTitle.text.trim();
    if (title.isEmpty || busy) return;
    final now = DateTime.now();
    final due = dayOf(now) == selected
        ? now.add(const Duration(hours: 1))
        : DateTime(selected.year, selected.month, selected.day, 9);
    await run(() async {
      await c.save(
        Task(
          id: 'task-${now.microsecondsSinceEpoch}',
          title: title,
          due: due,
          created: now,
          category: quickCategory,
        ),
      );
      quickTitle.clear();
    });
  }

  Widget quickAdd() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 6,
        runSpacing: 8,
        children: categoryColors.keys
            .map(
              (name) => ChoiceChip(
                label: Text(strings.category(name)),
                selected: quickCategory == name,
                onSelected: (_) => setState(() => quickCategory = name),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: quickTitle,
        maxLength: 100,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => addQuickTask(),
        decoration: InputDecoration(
          hintText: strings.t('생각났을 때, 할 일 하나'),
          counterText: '',
          suffixIcon: IconButton(
            tooltip: strings.t('빠른 추가'),
            onPressed: busy ? null : addQuickTask,
            icon: const Icon(Icons.arrow_upward),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        dayOf(DateTime.now()) == selected
            ? strings.t('지금부터 1시간 뒤로 등록돼요. 상세 화면에서 시간을 바꿀 수 있어요.')
            : strings.t(
                '{date} 오전 9시로 등록돼요.',
                args: {'date': strings.dateShort(selected)},
              ),
        style: const TextStyle(fontSize: 13, color: Color(0xff626873)),
      ),
    ],
  );

  Widget insightPanel() {
    if (!subscription.hasAccess) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xfff1f2f4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subscription.access?.paidUntil != null
                  ? strings.t('구독을 다시 확인해주세요')
                  : strings.t('꾸준함을 눈으로 확인해요'),
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              subscription.access?.paidUntil != null
                  ? strings.t(
                      '확인된 구독 이용 기간이 끝났어요. 인터넷에 연결한 뒤 구매 복원으로 구독을 확인해주세요. 기존 기록은 그대로 남아 있어요.',
                    )
                  : strings.t(
                      '7일 체험이 끝났어요. Pro를 구독하면 알림·미루기와 30일·90일 통계를 계속 사용할 수 있어요. 기존 기록은 그대로 남아 있어요.',
                    ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: openPro,
              child: Text(strings.t('Pro 알아보기')),
            ),
          ],
        ),
      );
    }
    final today = dayOf(DateTime.now());
    final start = today.subtract(const Duration(days: 89));
    final completed = c.items
        .where(
          (o) =>
              o.completed != null &&
              !dayOf(o.completed!).isBefore(start) &&
              !dayOf(o.completed!).isAfter(today) &&
              o.status == TaskStatus.completed,
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.t('지난 90일, {n}번의 작은 시작', args: {'n': completed.length}),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          strings.t('진한 칸일수록 더 많이 완료한 날이에요.'),
          style: TextStyle(color: mutedText, fontSize: 12),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 15,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: 90,
          itemBuilder: (_, i) {
            final date = DateTime(start.year, start.month, start.day + i);
            final count = completed
                .where((o) => dayOf(o.completed!) == date)
                .length;
            return Tooltip(
              message: strings.t(
                '{date} · {n}개 완료',
                args: {'date': strings.date(date), 'n': count},
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: count == 0
                      ? const Color(0xffedf0ea)
                      : count < 3
                      ? const Color(0xffb2c4a5)
                      : const Color(0xff4d6b45),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 22),
        ...categoryColors.entries.map((entry) {
          final count = completed
              .where((o) => o.task.category == entry.key)
              .length;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: strings.languageCode == 'en' ? 96 : 48,
                  child: Text(strings.category(entry.key)),
                ),
                Expanded(
                  child: LinearProgressIndicator(
                    value: completed.isEmpty ? 0 : count / completed.length,
                    color: entry.value,
                    backgroundColor: const Color(0xfff0efed),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                Text(strings.t('{n}개', args: {'n': count})),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget statsPage() {
    if (!subscription.hasAccess) return insightPanel();
    final s = c.statistics;
    final total = s['total'] as int? ?? 0, done = s['completed'] as int? ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        insightPanel(),
        const SizedBox(height: 28),
        Text(strings.t('최근 30일'), style: TextStyle(color: mutedText)),
        const SizedBox(height: 20),
        ...{
          strings.t('등록한 할 일'): strings.t(
            '{n}개',
            args: {'n': s['registered'] ?? 0},
          ),
          strings.t('완료한 회차'): strings.t('{n}개', args: {'n': done}),
          strings.t('완료율'): total == 0
              ? strings.t('기록 없음')
              : '${(done / total * 100).round()}%',
          strings.t('미룬 횟수'): strings.t('{n}회', args: {'n': s['snoozes'] ?? 0}),
          strings.t('평균 미룬 시간'): strings.t(
            '{n}분',
            args: {'n': ((s['average'] as num?) ?? 0).round()},
          ),
          strings.t('자주 완료한 시간대'): statisticsHour(s['hour']),
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
        Text(
          strings.t(
            '완료율은 최근 30일 예정 시간이 지난 회차와 미리 완료한 회차를 기준으로 계산합니다. 반복 일정은 각 회차를 별도로 집계합니다.',
          ),
        ),
      ],
    );
  }

  String statisticsHour(Object? value) {
    if (value == null || value == '기록 없음') return strings.t('기록 없음');
    final hour = int.tryParse(value.toString().replaceAll('시', ''));
    if (!strings.isEnglish || hour == null) return value.toString();
    return strings.time(DateTime(2000, 1, 1, hour));
  }

  Widget settingsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.auto_graph),
        title: Text(
          subscription.paidAccess
              ? strings.t('첫칸 Pro 이용 중')
              : subscription.trialActive
              ? strings.t('전체 기능 7일 체험 중')
              : strings.t('무료 캘린더 이용 중'),
        ),
        subtitle: Text(strings.t('연간 구독 · 구매 복원 · 구독 관리')),
        trailing: const Icon(Icons.chevron_right),
        onTap: openPro,
      ),
      const Divider(height: 32),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonFormField<String>(
          key: const Key('language-setting'),
          initialValue: c.localeController.preference,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: strings.t('언어'),
            prefixIcon: const Icon(Icons.language),
          ),
          items: [
            DropdownMenuItem(
              value: 'system',
              child: Text(strings.t('기기 설정 사용')),
            ),
            const DropdownMenuItem(value: 'ko', child: Text('한국어')),
            const DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: busy
              ? null
              : (value) {
                  if (value != null) run(() => c.setLanguage(value));
                },
        ),
      ),
      const Divider(height: 32),
      const PrivacyCard(),
      const SizedBox(height: 12),
      const StorePolicyLinks(),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: () async {
          if (!subscription.hasAccess) {
            openPro();
            return;
          }
          await run(() async {
            await c.reminders.requestPermissions();
            await c.reconcile();
          });
        },
        icon: const Icon(Icons.notifications_outlined),
        label: Text(strings.t('알림 권한 설정')),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => run(c.reminders.openSettings),
        child: Text(strings.t('기기 알림 설정 열기')),
      ),
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => run(c.reminders.requestExactPermission),
          child: Text(strings.t('Android 정확한 알림 설정')),
        ),
      ],
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => subscription.hasAccess
            ? run(c.reminders.testNotification)
            : openPro(),
        child: Text(strings.t('10초 뒤 테스트 알림')),
      ),
      const SizedBox(height: 20),
      Text(
        strings.t(
          '미완료 재알림은 기본 매일 한 번, 예정 시간과 같은 시각입니다. 각 할 일의 수정 화면에서 간격·시각을 바꾸거나 끌 수 있어요. 미루기는 선택한 시간까지 기다립니다. 진행 중 확인은 30분 뒤, 작은 시작 확인은 5분 뒤입니다. 배너 표시 여부는 기기 알림 권한·집중 모드·배터리 설정을 따릅니다.',
        ),
      ),
    ],
  );
  Widget accessNotice() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xffdfe2e6)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        subscription.paidAccess
            ? strings.t('Pro 이용 중')
            : subscription.trialActive
            ? strings.t('전체 기능 7일 체험 중')
            : strings.t('무료 캘린더 이용 중'),
      ),
      subtitle: Text(
        subscription.trialActive && subscription.trialEnds != null
            ? strings.t(
                '{date} {time}까지 · 체험만으로 결제되지 않아요',
                args: {
                  'date': strings.date(subscription.trialEnds!),
                  'time': strings.time(subscription.trialEnds!),
                },
              )
            : strings.t('캘린더·메모·완료는 무료 · 알림·미루기·통계는 Pro'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: openPro,
    ),
  );

  Widget pageHeader() => AppBar(
    primary: false,
    title: Text(
      page == 0
          ? strings.month(
              month,
              short:
                  strings.isEnglish && MediaQuery.sizeOf(context).width < 380,
            )
          : [
              strings.t('캘린더'),
              strings.t('예정된 할 일'),
              strings.t('완료한 일'),
              strings.t('나의 흐름'),
              strings.t('설정'),
            ][page],
    ),
    actions: [
      if (page == 0) ...[
        IconButton(
          tooltip: strings.t('이전'),
          onPressed: () => move(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: strings.t('다음'),
          onPressed: () => move(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
      if (busy)
        Padding(
          padding: EdgeInsets.all(18),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          if (page == 0) overdueBanner(),
          SizedBox(height: kToolbarHeight, child: pageHeader()),
          Expanded(
            child: RefreshIndicator(
              onRefresh: c.reconcile,
              child: ListView(
                controller: bodyScroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                  if (c.warning != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        c.warning!,
                        style: const TextStyle(color: priorityRed),
                      ),
                    ),
                  if (page == 0) ...[
                    calendarPage(),
                    const SizedBox(height: 16),
                    accessNotice(),
                  ],
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
          ),
        ],
      ),
    ),
    floatingActionButton: page < 3
        ? FloatingActionButton.extended(
            onPressed: () => edit(),
            tooltip: strings.t('할 일 추가'),
            icon: const Icon(Icons.add, size: 21),
            label: Text(strings.t('할 일')),
          )
        : null,
    bottomNavigationBar: NavigationBar(
      selectedIndex: page,
      onDestinationSelected: (i) {
        setState(() => page = i);
        if (bodyScroll.hasClients) bodyScroll.jumpTo(0);
      },
      destinations: [
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          label: strings.t('캘린더'),
        ),
        NavigationDestination(
          icon: Icon(Icons.list_alt_outlined),
          label: strings.t('예정'),
        ),
        NavigationDestination(
          icon: Icon(Icons.check_circle_outline),
          label: strings.t('완료'),
        ),
        NavigationDestination(
          icon: Icon(Icons.bar_chart_outlined),
          label: strings.t('통계'),
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          label: strings.t('설정'),
        ),
      ],
    ),
  );
}
