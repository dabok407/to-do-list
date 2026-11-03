import 'dart:async';

import 'package:flutter/material.dart';

import '../app/task_controller.dart';
import '../domain/task.dart';
import '../domain/task_list_sections.dart';
import '../domain/snooze_target.dart';
import 'task_editor.dart';
import 'pro_screen.dart';
import 'persistent_time_picker.dart';
import 'equal_choice_row.dart';
import 'feedback_snackbar.dart';
import 'visual_tokens.dart';
import 'statistics_panel.dart';
import 'task_timeline_row.dart';
import 'task_list_sort_control.dart';
import 'task_list_section_header.dart';
import 'task_detail_metadata.dart';
import 'settings_panel.dart';
import '../services/subscription_service.dart';
import '../l10n/app_strings.dart';

const mutedText = Color(0xff626873);
const priorityRed = Color(0xff8f303a);
const categoryColors = TaskVisuals.categoryColors;
const stateNames = ['예정', '진행 중', '보류', '완료', '건너뜀'];
String timeLabel(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

DateTime defaultQuickDue(DateTime selectedDate, DateTime now) {
  final next = now.add(const Duration(hours: 1));
  final date = dayOf(selectedDate) == dayOf(now) ? next : selectedDate;
  return DateTime(date.year, date.month, date.day, next.hour, next.minute);
}

// Material uses Sunday = 0, while DateTime uses Monday = 1. Keep calendar
// display weeks separate from the Monday-based recurrence and quota logic.
DateTime calendarWeekStart(DateTime date, int firstDayOfWeekIndex) {
  final offset = (date.weekday % 7 - firstDayOfWeekIndex + 7) % 7;
  return DateTime(date.year, date.month, date.day - offset);
}

int calendarMonthCellCount(DateTime month, int firstDayOfWeekIndex) {
  final first = DateTime(month.year, month.month);
  final offset = (first.weekday % 7 - firstDayOfWeekIndex + 7) % 7;
  final days = DateTime(month.year, month.month + 1, 0).day;
  return ((offset + days) / 7).ceil() * 7;
}

class HomeScreen extends StatefulWidget {
  final TaskController controller;
  final SubscriptionService? subscription;
  final int initialPage;
  // Only the date grid uses this inset; task content keeps its 16px margin.
  final double calendarHorizontalInset;
  const HomeScreen({
    super.key,
    required this.controller,
    this.subscription,
    this.initialPage = 0,
    this.calendarHorizontalInset = 8,
  }) : assert(calendarHorizontalInset >= 0 && calendarHorizontalInset <= 16);
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Retains only the acted-on row in its source list while its saved state is
/// visible. Persistence and reminder cancellation never wait for this timer.
class _CompletionFeedback {
  final Occurrence before;
  final Object source;
  final int generation;
  Occurrence? after;
  bool collapsing = false;
  Timer? holdTimer, removeTimer;
  _CompletionFeedback(this.before, this.source, this.generation);

  void cancelTimers() {
    holdTimer?.cancel();
    removeTimer?.cancel();
  }
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  DateTime selected = dayOf(DateTime.now()),
      month = DateTime(DateTime.now().year, DateTime.now().month);
  int page = 0, summary = 0;
  bool week = false, busy = false;
  bool detailVisible = false;
  bool quickExpanded = false;
  bool quickTimeEdited = false;
  TaskListOrder upcomingOrder = TaskListOrder.latest;
  TaskListOrder completedOrder = TaskListOrder.latest;
  bool upcomingOverdueOnly = false;
  String? quickTitleError;
  late TimeOfDay quickTime;
  late DateTime quickDate;
  late final subscription = widget.subscription ?? SubscriptionService();
  final quickTitle = TextEditingController();
  final quickTitleFocus = FocusNode();
  final quickTimeAnchor = GlobalKey();
  final bodyScroll = ScrollController();
  Timer? clockRefresh;
  Completer<void>? busyFinished;
  final completionFeedback = <String, _CompletionFeedback>{};
  final completionGeneration = <String, int>{};
  final sheetChanges = ValueNotifier<int>(0);
  final sheetFeedback = <SheetFeedbackController>[];
  String quickCategory = '생활';
  TaskController get c => widget.controller;
  AppStrings get strings => AppStrings.of(context);

  void updateUi(VoidCallback update) {
    if (!mounted) return;
    setState(update);
    sheetChanges.value++;
  }

  void showFeedback(SnackBar message) {
    if (!mounted) return;
    final sheet = sheetFeedback.where((s) => !s.closed).lastOrNull;
    if (sheet != null) {
      sheet.show(message);
    } else {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(message);
    }
  }

  @override
  void initState() {
    super.initState();
    page = widget.initialPage.clamp(0, 4);
    resetQuickTime();
    WidgetsBinding.instance.addObserver(this);
    quickTitleFocus.addListener(quickTitleFocusChanged);
    c.addListener(changed);
    subscription.addListener(subscriptionChanged);
    clockRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        updateUi(() {});
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
    // A notification action, refresh, or edit can supersede the local feedback.
    // Never collapse a newer state or keep it under the old date heading.
    for (final feedback in completionFeedback.values.toList()) {
      final after = feedback.after;
      if (after == null) continue;
      final current = c.items.where((o) => o.id == after.id).firstOrNull;
      if (current == null || !sameCompletionSnapshot(current, after)) {
        feedback.cancelTimers();
        completionFeedback.remove(after.id);
        completionGeneration[after.id] = feedback.generation + 1;
      }
    }
    if (mounted) updateUi(() {});
    if (mounted && c.pendingOpenId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openRequestedTask());
    }
  }

  bool sameCompletionSnapshot(Occurrence a, Occurrence b) {
    final task = b.task.toMap();
    return a.status == b.status &&
        a.originalDue == b.originalDue &&
        a.reminder == b.reminder &&
        a.completed == b.completed &&
        a.started == b.started &&
        a.beforeComplete == b.beforeComplete &&
        a.snoozes == b.snoozes &&
        a.smallActive == b.smallActive &&
        a.quotaSkipped == b.quotaSkipped &&
        a.task.toMap().entries.every((entry) => task[entry.key] == entry.value);
  }

  void quickTitleFocusChanged() {
    if (mounted) updateUi(() {});
  }

  void openRequestedTask() {
    if (!mounted || detailVisible || c.pendingOpenId == null) return;
    final id = c.pendingOpenId;
    c.pendingOpenId = null;
    final occurrence = c.items.where((o) => o.id == id).firstOrNull;
    if (occurrence == null) return;
    updateUi(() {
      page = 0;
      selectCalendarDate(dayOf(occurrence.originalDue));
    });
    detail(occurrence);
  }

  @override
  void dispose() {
    c.removeListener(changed);
    subscription.removeListener(subscriptionChanged);
    if (widget.subscription == null) subscription.dispose();
    quickTitle.dispose();
    quickTitleFocus.removeListener(quickTitleFocusChanged);
    quickTitleFocus.dispose();
    bodyScroll.dispose();
    clockRefresh?.cancel();
    for (final feedback in completionFeedback.values) {
      feedback.cancelTimers();
    }
    sheetChanges.dispose();
    for (final feedback in sheetFeedback) {
      feedback.dispose();
    }
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
    if (!mounted || busy) return;
    final finished = Completer<void>();
    busyFinished = finished;
    updateUi(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        showFeedback(
          feedbackSnackBar(content: Text(strings.t('처리하지 못했습니다. 다시 시도해주세요.'))),
        );
      }
    } finally {
      if (mounted) updateUi(() => busy = false);
      finished.complete();
      if (identical(busyFinished, finished)) busyFinished = null;
    }
  }

  void resetQuickTime() {
    final due = defaultQuickDue(selected, DateTime.now());
    quickDate = dayOf(due);
    quickTime = TimeOfDay.fromDateTime(due);
  }

  void selectCalendarDate(DateTime date) {
    selected = date;
    month = DateTime(date.year, date.month);
    if (quickTimeEdited) {
      quickDate = dayOf(date);
    } else {
      resetQuickTime();
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
              content: RadioGroup<bool>(
                groupValue: choice,
                onChanged: (value) => setChoice(() => choice = value),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.t('이번 일정만')),
                      value: true,
                    ),
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.t('이번부터 앞으로')),
                      value: false,
                    ),
                  ],
                ),
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
        () => occurrence != null
            ? c.editOccurrence(occurrence, result, onlyThis: onlyThis ?? true)
            : c.save(result),
      );
    }
  }

  Future<void> detail(Occurrence original) async {
    if (detailVisible) return;
    detailVisible = true;
    final feedbackHost = SheetFeedbackController();
    final source = Object();
    sheetFeedback.add(feedbackHost);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SheetFeedbackHost(
        controller: feedbackHost,
        child: ListenableBuilder(
          listenable: Listenable.merge([c, subscription, sheetChanges]),
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
                    TaskDetailMetadata(occurrence: o),
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
                              onPressed:
                                  busy || completionFeedback.containsKey(o.id)
                                  ? null
                                  : () => toggleCompletion(o, source: source),
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
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
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            feedbackSnackBar(
                                              content: Text(
                                                strings.t(
                                                  '오늘 남은 시간이 없어요. 날짜를 변경해주세요.',
                                                ),
                                              ),
                                            ),
                                          );
                                      return;
                                    }
                                    taskAction(
                                      o,
                                      'snooze',
                                      minutes: remaining < 120
                                          ? remaining
                                          : 120,
                                    );
                                  },
                            child: Text(strings.t('오늘 나중에')),
                          ),
                          OutlinedButton(
                            key: const Key('snooze-tomorrow'),
                            onPressed: busy
                                ? null
                                : () async {
                                    if (!subscription.hasAccess) {
                                      openPro();
                                      return;
                                    }
                                    final target = tomorrowAtScheduledTime(
                                      o.originalDue,
                                      DateTime.now(),
                                    );
                                    await run(() => c.snoozeUntil(o, target));
                                  },
                            child: Text(strings.t('내일 같은 시간')),
                          ),
                        ],
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
                                  onPressed: busy
                                      ? null
                                      : () => taskAction(o, 'small'),
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
                        onPressed: busy || completionFeedback.containsKey(o.id)
                            ? null
                            : () => toggleCompletion(o, source: source),
                        child: Text(strings.t('완료 해제')),
                      ),
                    if (o.status == TaskStatus.skipped && !o.quotaSkipped)
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => run(() => c.act(o, 'unskip')),
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
                          onPressed: busy
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  edit(o.task, o);
                                },
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(strings.t('수정')),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  final scope = await showDialog<String>(
                                    context: ctx,
                                    builder: (d) => AlertDialog(
                                      title: Text(strings.t('할 일을 삭제할까요?')),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            strings.t('선택한 범위의 일정과 기록이 삭제됩니다.'),
                                          ),
                                          const SizedBox(height: 12),
                                          ListTile(
                                            title: Text(strings.t('이번 일정만 삭제')),
                                            onTap: () =>
                                                Navigator.pop(d, 'this'),
                                          ),
                                          if (o.task.repeat !=
                                                  RepeatUnit.none ||
                                              o.task.derived) ...[
                                            ListTile(
                                              title: Text(
                                                strings.t('이번부터 앞으로 삭제'),
                                              ),
                                              onTap: () =>
                                                  Navigator.pop(d, 'future'),
                                            ),
                                            ListTile(
                                              title: Text(
                                                strings.t('전체 반복과 기록 삭제'),
                                              ),
                                              onTap: () =>
                                                  Navigator.pop(d, 'series'),
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
      ),
    );
    sheetFeedback.remove(feedbackHost);
    feedbackHost.dispose();
    detailVisible = false;
    openRequestedTask();
  }

  void removeCompletionFeedback(_CompletionFeedback feedback) {
    feedback.cancelTimers();
    if (mounted &&
        identical(completionFeedback[feedback.before.id], feedback)) {
      updateUi(() => completionFeedback.remove(feedback.before.id));
    }
  }

  Future<void> undoCompletion(_CompletionFeedback feedback) async {
    final id = feedback.before.id;
    final after = feedback.after;
    if (after == null || completionGeneration[id] != feedback.generation) {
      return;
    }
    feedback.cancelTimers();
    // Undo remains actionable while a different task is saving. Dropping it
    // through run's double-tap guard would dismiss the snackbar without undoing.
    while (mounted && busy) {
      final finished = busyFinished;
      if (finished == null) return;
      await finished.future;
    }
    if (!mounted || completionGeneration[id] != feedback.generation) return;
    completionGeneration[id] = feedback.generation + 1;
    await run(() => c.undoCompletion(feedback.before, after));
    if (mounted) removeCompletionFeedback(feedback);
  }

  Future<void> toggleCompletion(Occurrence occurrence, {Object? source}) async {
    if (busy || completionFeedback.containsKey(occurrence.id)) return;
    final before = c.items
        .where((item) => item.id == occurrence.id)
        .firstOrNull;
    if (before == null || before.status == TaskStatus.skipped) return;
    final completing = before.status != TaskStatus.completed;
    final generation = (completionGeneration[before.id] ?? 0) + 1;
    completionGeneration[before.id] = generation;
    final feedback = _CompletionFeedback(before, source ?? page, generation);
    updateUi(() => completionFeedback[before.id] = feedback);
    var saved = false;
    await run(() async {
      await c.act(before, completing ? 'complete' : 'uncomplete');
      saved = true;
    });
    if (!mounted) return;
    final updated = c.items.where((item) => item.id == before.id).firstOrNull;
    // act may decline an invalid or stale transition without throwing.
    if (!saved ||
        updated == null ||
        (completing && updated.status != TaskStatus.completed) ||
        (!completing &&
            !updated.active &&
            !(updated.status == TaskStatus.skipped && updated.quotaSkipped))) {
      removeCompletionFeedback(feedback);
      return;
    }
    updateUi(() => feedback.after = updated);
    feedback.holdTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted || !identical(completionFeedback[before.id], feedback)) {
        return;
      }
      if (feedback.source == 0 || MediaQuery.disableAnimationsOf(context)) {
        removeCompletionFeedback(feedback);
        return;
      }
      updateUi(() => feedback.collapsing = true);
      feedback.removeTimer = Timer(
        const Duration(milliseconds: 180),
        () => removeCompletionFeedback(feedback),
      );
    });
    showFeedback(
      feedbackSnackBar(
        content: Text(strings.t(completing ? '할 일을 완료했어요.' : '완료를 해제했어요.')),
        action: SnackBarAction(
          label: strings.t('되돌리기'),
          onPressed: () => undoCompletion(feedback),
        ),
      ),
    );
  }

  Widget swipeBackground(Occurrence o, {required bool trailing}) {
    final done = o.status == TaskStatus.completed;
    final color = done ? mutedText : Colors.white;
    final children = <Widget>[
      Icon(done ? Icons.undo : Icons.check, color: color),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          strings.t(done ? '완료 해제' : '완료 처리'),
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    ];
    return Container(
      alignment: trailing ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: done ? const Color(0xffeceeef) : const Color(0xff252923),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: trailing
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget row(
    Occurrence source, {
    bool timeline = false,
    Object? scope,
    Widget? heading,
  }) {
    final feedback = completionFeedback[source.id];
    final heldHere = feedback != null && feedback.source == (scope ?? page);
    final o = heldHere
        ? c.items.where((item) => item.id == source.id).firstOrNull ?? source
        : source;
    final swipeSource = heldHere ? feedback.before : o;
    final savedHere = heldHere && feedback.after != null;
    final disabled = busy || feedback != null || o.status == TaskStatus.skipped;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      key: ValueKey('task-feedback-${o.id}'),
      tween: Tween(begin: 1, end: heldHere && feedback.collapsing ? 0 : 1),
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      builder: (context, factor, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: factor,
          child: Opacity(opacity: factor, child: child),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?heading,
          Dismissible(
            key: ValueKey('task-swipe-${o.id}'),
            direction: disabled
                ? DismissDirection.none
                : DismissDirection.horizontal,
            dismissThresholds: const {
              DismissDirection.startToEnd: .35,
              DismissDirection.endToStart: .35,
            },
            confirmDismiss: (_) async {
              await toggleCompletion(o, source: scope);
              // The row returns to its position to show the saved check/strike.
              // Filtering happens only after the success hold and collapse.
              return false;
            },
            background: swipeBackground(swipeSource, trailing: false),
            secondaryBackground: swipeBackground(swipeSource, trailing: true),
            child: AnimatedOpacity(
              opacity: savedHere ? .65 : 1,
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              child: TaskTimelineRow(
                occurrence: o,
                busy: disabled,
                hasProAccess: subscription.hasAccess,
                useScheduledTime:
                    !timeline ||
                    (heldHere &&
                        feedback.before.status != TaskStatus.completed),
                showScheduleDate: o.status == TaskStatus.progressing,
                onTap: () => detail(o),
                onToggle: () => toggleCompletion(o, source: scope),
                onStart: () => taskAction(o, 'start'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget swipeHint({bool? completed}) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        const Icon(
          Icons.swap_horiz_rounded,
          size: 16,
          color: TaskVisuals.muted,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            strings.t(
              completed == null
                  ? '좌우로 밀어 완료·해제'
                  : completed
                  ? '좌우로 밀어 완료 해제'
                  : '좌우로 밀어 완료',
            ),
            style: const TextStyle(fontSize: 12, color: TaskVisuals.muted),
          ),
        ),
      ],
    ),
  );

  List<Widget> timelineList({required bool completed}) {
    final now = DateTime.now();
    final order = completed ? completedOrder : upcomingOrder;
    final held = completionFeedback.values
        .where(
          (feedback) =>
              feedback.source == page &&
              c.items.any((item) => item.id == feedback.before.id),
        )
        .toList();
    final heldIds = held.map((feedback) => feedback.before.id).toSet();
    final sections = taskListSections(
      [
        ...(completed ? c.items : c.queue).where(
          (item) => !heldIds.contains(item.id),
        ),
        // The original snapshot determines only its source group/order. The
        // row itself renders the freshly saved occurrence from the controller.
        ...held.map((feedback) => feedback.before),
      ],
      now: now,
      completed: completed,
      order: order,
    );
    final overdueSections = sections
        .where((section) => section.kind == TaskListSectionKind.overdue)
        .toList();
    final overdueCount = overdueSections.fold<int>(
      0,
      (count, section) => count + section.items.length,
    );
    final overdueOnly = !completed && upcomingOverdueOnly;
    final visibleSections = overdueOnly ? overdueSections : sections;
    Widget overdueSummary() => Padding(
      padding: const EdgeInsets.only(top: 20),
      child: TaskListOverdueHeader(
        key: const Key('upcoming-overdue-summary'),
        label: strings.t('기한 지난 일'),
        countLabel: strings.isEnglish ? '$overdueCount' : '$overdueCount개',
        selected: overdueOnly,
        actionLabel: strings.t(overdueOnly ? '전체 예정 목록 보기' : '기한 지난 일만 보기'),
        onToggle: () {
          updateUi(() => upcomingOverdueOnly = !upcomingOverdueOnly);
          if (bodyScroll.hasClients) bodyScroll.jumpTo(0);
        },
      ),
    );
    final firstScheduled = sections.indexWhere(
      (section) => section.kind == TaskListSectionKind.scheduled,
    );
    String heading(TaskListSection section) {
      if (section.kind == TaskListSectionKind.progressing) {
        return strings.t('진행 중');
      }
      if (section.kind == TaskListSectionKind.unknownCompletion) {
        return strings.t('완료 시각 기록 없음');
      }
      final date = section.day!;
      final day = dayOf(now) == date
          ? strings.t('오늘')
          : dayOf(DateTime(now.year, now.month, now.day + 1)) == date
          ? strings.t('내일')
          : date.year == now.year
          ? strings.dateShort(date)
          : strings.date(date);
      final dated = '$day · ${strings.weekday(date.weekday)}';
      return dated;
    }

    return [
      TaskListSortControl(
        completed: completed,
        order: order,
        onChanged: (value) {
          updateUi(() {
            if (completed) {
              completedOrder = value;
            } else {
              upcomingOrder = value;
            }
          });
          if (bodyScroll.hasClients) bodyScroll.jumpTo(0);
        },
      ),
      if (visibleSections.isNotEmpty) swipeHint(completed: completed),
      // Keep the selected filter reachable after its final task is completed.
      if (overdueOnly && overdueSections.isEmpty) ...[
        overdueSummary(),
        Padding(
          key: const Key('upcoming-overdue-empty-state'),
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.t('기한 지난 일이 없어요'),
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.t('상단 버튼을 다시 누르면 전체 예정 목록을 볼 수 있어요.'),
                style: const TextStyle(color: TaskVisuals.muted, height: 1.6),
              ),
            ],
          ),
        ),
      ] else if (visibleSections.isEmpty)
        emptyTaskList(completed: completed),
      for (final section in visibleSections) ...[
        if (overdueSections.isNotEmpty && section == overdueSections.first)
          overdueSummary(),
        if (overdueSections.isNotEmpty &&
            firstScheduled >= 0 &&
            section == sections[firstScheduled])
          const SizedBox(key: Key('upcoming-overdue-boundary'), height: 12),
        Padding(
          key: Key('task-section-${section.id}'),
          padding: const EdgeInsets.fromLTRB(0, 22, 0, 7),
          child: TaskListSectionHeader(label: heading(section)),
        ),
        for (final occurrence in section.items) row(occurrence, timeline: true),
      ],
    ];
  }

  Widget emptyTaskList({required bool completed}) => Padding(
    key: Key(completed ? 'completed-empty-state' : 'upcoming-empty-state'),
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.t(completed ? '아직 완료한 일이 없어요' : '아직 예정된 할 일이 없어요'),
          style: const TextStyle(
            fontSize: 20,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          strings.t(
            completed ? '할 일을 완료하면 이곳에 차곡차곡 모여요.' : '생각난 일 하나를 날짜와 함께 적어보세요.',
          ),
          style: const TextStyle(color: TaskVisuals.muted, height: 1.6),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: completed
              ? () {
                  updateUi(() => page = 1);
                  if (bodyScroll.hasClients) bodyScroll.jumpTo(0);
                }
              : () => edit(),
          icon: Icon(completed ? Icons.list_alt_outlined : Icons.add, size: 20),
          label: Text(strings.t(completed ? '예정된 할 일 보기' : '첫 할 일 추가')),
        ),
      ],
    ),
  );

  Widget calendar() {
    final daySize =
        26.0 *
        (MediaQuery.textScalerOf(context).scale(13) / 13).clamp(1.0, 1.6);
    final firstDayOfWeekIndex = MaterialLocalizations.of(context)
        .firstDayOfWeekIndex;
    final first = week ? selected : DateTime(month.year, month.month);
    final start = calendarWeekStart(first, firstDayOfWeekIndex);
    final count = week ? 7 : calendarMonthCellCount(month, firstDayOfWeekIndex);
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
      key: const Key('calendar-area'),
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
              children: List.generate(7, (i) {
                final weekday = (firstDayOfWeekIndex + i + 6) % 7 + 1;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Center(
                      child: Text(
                        strings.weekday(weekday),
                        key: Key('calendar-weekday-$weekday'),
                        style: TextStyle(
                          color: weekday == DateTime.sunday
                              ? priorityRed
                              : mutedText,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            GridView.builder(
              key: const Key('calendar-grid'),
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
                    key: Key('calendar-date-${dayKey(d)}'),
                    onTap: () {
                      updateUi(() {
                        selectCalendarDate(d);
                        week = true;
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
    updateUi(() {
      if (week) {
        selectCalendarDate(
          DateTime(selected.year, selected.month, selected.day + n * 7),
        );
      } else {
        month = DateTime(month.year, month.month + n);
        selectCalendarDate(month);
      }
    });
    run(() => c.refresh(through: DateTime(month.year, month.month + 1, 0)));
  }

  Future<void> showOverdue() async {
    final scope = Object();
    final feedbackHost = SheetFeedbackController();
    sheetFeedback.add(feedbackHost);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .7,
          child: SheetFeedbackHost(
            controller: feedbackHost,
            child: ListenableBuilder(
              listenable: Listenable.merge([c, sheetChanges]),
              builder: (ctx, _) {
                final held = completionFeedback.values.where(
                  (f) =>
                      f.source == scope &&
                      c.items.any((o) => o.id == f.before.id),
                );
                final heldIds = held.map((f) => f.before.id).toSet();
                final visible = [
                  ...c.overdue.where((o) => !heldIds.contains(o.id)),
                  ...held.map((f) => f.before),
                ]..sort((a, b) => a.reminder.compareTo(b.reminder));
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                  children: [
                    Text(
                      overdueTitle(visible.length),
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(strings.t('예정 시간이 지났지만 아직 완료하지 않은 일이에요.')),
                    if (visible.isNotEmpty) swipeHint(completed: false),
                    const SizedBox(height: 16),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(strings.t('남은 일을 모두 마쳤어요.')),
                      ),
                    for (final o in visible)
                      row(
                        o,
                        scope: scope,
                        heading: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            strings.t(
                              '{date} 예정',
                              args: {'date': strings.date(o.originalDue)},
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: mutedText,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    sheetFeedback.remove(feedbackHost);
    feedbackHost.dispose();
  }

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
            ? calendarWeekStart(
                today,
                MaterialLocalizations.of(context).firstDayOfWeekIndex,
              )
            : DateTime(today.year, today.month);
    final end = summary == 0
        ? begin
        : summary == 1
        ? DateTime(begin.year, begin.month, begin.day + 6)
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
      children:
          <Widget>[
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    updateUi(() {
                      selectCalendarDate(today);
                    });
                  },
                  child: Text(strings.t('오늘로')),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => updateUi(() => week = !week),
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
                    onSelected: (value) => updateUi(() => summary = value),
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
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xff626873),
                    ),
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
            if (todays.isNotEmpty) swipeHint(),
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
                      Flexible(
                        child: CategoryLabel(
                          category: entry.key,
                          label: strings.category(entry.key),
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
            Material(
              key: const Key('quick-add-card'),
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xffe4e6ea)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    button: true,
                    expanded: quickExpanded,
                    child: InkWell(
                      key: const Key('quick-add'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => updateUi(() {
                        quickExpanded = !quickExpanded;
                        if (quickExpanded && !quickTimeEdited) resetQuickTime();
                      }),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text(
                          strings.t('간단히 추가'),
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: Icon(
                          quickExpanded ? Icons.expand_less : Icons.expand_more,
                        ),
                      ),
                    ),
                  ),
                  if (quickExpanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: quickAdd(),
                    ),
                ],
              ),
            ),
            if (!subscription.paidAccess) ...[
              const SizedBox(height: 16),
              accessNotice(),
            ],
          ].map((child) {
            if (widget.calendarHorizontalInset == 16 ||
                child.key == const Key('calendar-area')) {
              return child;
            }
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 16 - widget.calendarHorizontalInset,
              ),
              child: child,
            );
          }).toList(),
    );
  }

  void openPro() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ProScreen(subscription: subscription)),
  );

  Future<void> addQuickTask() async {
    final title = quickTitle.text.trim();
    if (busy) return;
    if (title.isEmpty) {
      updateUi(() => quickTitleError = strings.t('할 일을 입력해주세요.'));
      quickTitleFocus.requestFocus();
      return;
    }
    final now = DateTime.now();
    final due = DateTime(
      quickDate.year,
      quickDate.month,
      quickDate.day,
      quickTime.hour,
      quickTime.minute,
    );
    FocusScope.of(context).unfocus();
    updateUi(() => quickTitleError = null);
    await run(() async {
      String normalized(String value) =>
          value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      final existing = await c.repository.tasks();
      if (!mounted) return;
      if (existing.any((task) => normalized(task.title) == normalized(title))) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(strings.t('중복된 내용입니다.')),
            content: Text(strings.t('같은 내용의 할 일이 있어요. 그래도 등록하시겠습니까?')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(strings.t('취소')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(strings.t('그래도 등록')),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      await c.save(
        Task(
          id: 'task-${now.microsecondsSinceEpoch}',
          title: title,
          due: due,
          created: now,
          category: quickCategory,
        ),
      );
      if (!mounted) return;
      quickTitle.clear();
      updateUi(() {
        quickTimeEdited = false;
        resetQuickTime();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(feedbackSnackBar(content: Text(strings.t('할 일을 등록했어요.'))));
    });
  }

  Widget quickAdd() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        key: quickTimeAnchor,
        child: OutlinedButton.icon(
          key: const Key('quick-add-time'),
          onPressed: busy
              ? null
              : () async {
                  FocusScope.of(context).unfocus();
                  final value = await showPersistentTimePicker(
                    context: context,
                    initialTime: quickTime,
                  );
                  if (value == null || !mounted) return;
                  updateUi(() {
                    quickTime = value;
                    quickTimeEdited = true;
                  });
                },
          icon: const Icon(Icons.schedule, size: 20),
          label: Text(
            strings.t(
              '시간 · {time}',
              args: {
                'time': strings.time(
                  DateTime(2000, 1, 1, quickTime.hour, quickTime.minute),
                ),
              },
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        strings.t(
          '{date} {time}에 등록돼요.',
          args: {
            'date': strings.dateShort(quickDate),
            'time': strings.time(
              DateTime(2000, 1, 1, quickTime.hour, quickTime.minute),
            ),
          },
        ),
        key: const Key('quick-add-time-hint'),
        style: const TextStyle(fontSize: 13, color: mutedText),
      ),
      const SizedBox(height: 12),
      EqualChoiceRow<String>(
        key: const Key('quick-category-row'),
        choices: {
          for (final name in categoryColors.keys) name: strings.category(name),
        },
        value: quickCategory,
        optionKeyPrefix: 'quick-category-option',
        onChanged: busy
            ? null
            : (name) {
                FocusScope.of(context).unfocus();
                updateUi(() => quickCategory = name);
              },
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('quick-add-title'),
        controller: quickTitle,
        focusNode: quickTitleFocus,
        enabled: !busy,
        maxLength: 100,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => addQuickTask(),
        onChanged: (_) {
          if (quickTitleError != null) updateUi(() => quickTitleError = null);
        },
        decoration: InputDecoration(
          hintText: strings.t('생각났을 때, 할 일 하나'),
          errorText: quickTitleError,
          counterText: '',
          suffixIcon: IconButton(
            tooltip: strings.t('빠른 추가'),
            onPressed: busy ? null : addQuickTask,
            icon: const Icon(Icons.arrow_upward),
          ),
        ),
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
    return StatisticsPanel(
      items: c.items,
      statistics: c.statistics,
      loadStatistics: c.statisticsForPeriod,
    );
  }

  Widget statsPage() => insightPanel();

  Widget settingsPage() => SettingsPanel(
    controller: c,
    subscription: subscription,
    busy: busy,
    openPro: openPro,
    setLanguage: (value) => run(() => c.setLanguage(value)),
    requestPermission: () async {
      if (!subscription.hasAccess) {
        openPro();
        return;
      }
      await run(() async {
        await c.reminders.requestPermissions();
        await c.reconcile();
      });
    },
    openDeviceSettings: () => run(c.reminders.openSettings),
    requestExactPermission: () => run(c.reminders.requestExactPermission),
    testReminder: () =>
        subscription.hasAccess ? run(c.testReminder) : openPro(),
  );
  Widget accessNotice() => Padding(
    key: const Key('access-notice'),
    padding: const EdgeInsets.only(bottom: 16),
    // Keep the outline and ink on the tile's own moving surface. Painting the
    // ListTile shape onto Scaffold's Material can leave its old outline behind
    // when the quick-add form above changes height without a scroll event.
    child: Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xffdfe2e6)),
      ),
      child: ListTile(
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
                padding: EdgeInsets.fromLTRB(
                  page == 0 ? widget.calendarHorizontalInset : 16,
                  0,
                  page == 0 ? widget.calendarHorizontalInset : 16,
                  page == 3 ? 20 : 96,
                ),
                children: [
                  if (c.warning != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        page == 0 ? 16 - widget.calendarHorizontalInset : 0,
                        0,
                        page == 0 ? 16 - widget.calendarHorizontalInset : 0,
                        16,
                      ),
                      child: Text(
                        c.warning!,
                        style: const TextStyle(color: priorityRed),
                      ),
                    ),
                  if (page == 0) ...[calendarPage()],
                  if (page == 1) ...timelineList(completed: false),
                  if (page == 2) ...timelineList(completed: true),
                  if (page == 3) statsPage(),
                  if (page == 4) settingsPage(),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    floatingActionButton: page < 3 && !quickTitleFocus.hasFocus
        ? FloatingActionButton.extended(
            onPressed: () => edit(),
            tooltip: strings.t('할 일 추가'),
            icon: const Icon(Icons.add_rounded),
            label: Text(strings.t('할 일')),
          )
        : null,
    bottomNavigationBar: NavigationBar(
      selectedIndex: page,
      onDestinationSelected: (i) {
        updateUi(() => page = i);
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
