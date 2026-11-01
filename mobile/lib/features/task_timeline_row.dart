import 'package:flutter/material.dart';

import '../domain/task.dart';
import '../l10n/app_strings.dart';
import 'visual_tokens.dart';
import 'task_completion_checkbox.dart';

/// Calendar and timeline rows must distinguish a next-day reminder from the
/// original due time while keeping same-day reminder labels compact.
String taskReminderLabel(Occurrence occurrence, AppStrings strings) {
  final due = occurrence.originalDue.toLocal();
  final reminder = occurrence.reminder.toLocal();
  final time = dayOf(due) == dayOf(reminder)
      ? strings.time(reminder)
      : '${strings.date(reminder)} ${strings.time(reminder)}';
  return strings.t('· {time} 재알림', args: {'time': time});
}

/// Shared calendar, upcoming and completed rows. List completion is the primary
/// action; starting a task remains available in its detail sheet.
class TaskTimelineRow extends StatelessWidget {
  final Occurrence occurrence;
  final bool busy, hasProAccess, showScheduleDate;

  /// Calendar dates and pending-to-completed feedback keep the scheduled clock.
  /// The completed timeline otherwise shows the actual completion timestamp.
  final bool useScheduledTime;
  // Retained for caller compatibility; the inline start shortcut was removed
  // from the approved compact row, not from the task detail screen.
  final VoidCallback onTap, onToggle, onStart;

  const TaskTimelineRow({
    super.key,
    required this.occurrence,
    required this.busy,
    required this.hasProAccess,
    required this.onTap,
    required this.onToggle,
    required this.onStart,
    this.showScheduleDate = false,
    this.useScheduledTime = false,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final o = occurrence;
    final task = o.task;
    final isCompleted = o.status == TaskStatus.completed;
    final due = o.originalDue.toLocal();
    final completedAt = o.completed?.toLocal();
    final displayTime = isCompleted && !useScheduledTime
        ? completedAt ?? due
        : due;
    DateTime minute(DateTime value) =>
        DateTime(value.year, value.month, value.day, value.hour, value.minute);
    final showOriginal =
        isCompleted &&
        !useScheduledTime &&
        (completedAt == null || minute(completedAt) != minute(due));
    final priority = strings.t(switch (task.priority) {
      2 => '높음',
      0 => '낮음',
      _ => '보통',
    });
    final category = strings.category(task.category);
    final clock = strings.time(displayTime);
    final scaler = MediaQuery.textScalerOf(context);
    final timeStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 18,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: isCompleted ? TaskVisuals.muted : TaskVisuals.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final titleStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 16,
      height: 1.45,
      fontWeight: FontWeight.w500,
      color: isCompleted ? TaskVisuals.muted : TaskVisuals.ink,
      decoration: isCompleted ? TextDecoration.lineThrough : null,
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
    double width(String value, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final result = painter.width;
      painter.dispose();
      return result;
    }

    final timeWidth = (width(clock, timeStyle).ceilToDouble() + 4).clamp(
      56.0,
      double.infinity,
    );
    final toggleSize = TaskCompletionCheckbox.labeledSize(context);
    final metaWidth =
        16 +
        6 +
        width(category, categoryStyle) +
        6 +
        width(priority, priorityStyle) +
        (task.repeat == RepeatUnit.none ? 0 : 22);
    final toggle = TaskCompletionCheckbox(
      key: ValueKey('task-completion-${o.id}'),
      completed: isCompleted,
      enabled: !busy && o.status != TaskStatus.skipped,
      showLabel: true,
      semanticLabel:
          '${task.title}, ${strings.t(isCompleted ? '완료 해제' : '완료 처리')}',
      onToggle: onToggle,
    );
    final time = Semantics(
      label: isCompleted && completedAt != null && !useScheduledTime
          ? strings.t('완료 시각 {time}', args: {'time': clock})
          : strings.t(
              '예정 시각 {time}',
              args: {
                'time': showScheduleDate
                    ? '${strings.date(due)} $clock'
                    : clock,
              },
            ),
      excludeSemantics: true,
      child: SizedBox(
        width: timeWidth,
        height: toggleSize.height,
        child: Stack(
          children: [
            Center(
              child: Text(
                clock,
                key: Key('task-time-${o.id}'),
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                style: timeStyle,
              ),
            ),
            if (o.status != TaskStatus.skipped)
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
    );

    Widget title({required bool stacked}) => Text(
      task.title,
      key: Key('task-title-${o.id}'),
      // Full text remains in semantics and in the detail opened by the row.
      maxLines: stacked ? null : 1,
      overflow: stacked ? TextOverflow.clip : TextOverflow.ellipsis,
      softWrap: stacked,
      style: titleStyle,
    );
    List<Widget> metadataChildren(double maxWidth) => [
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: CategoryLabel(category: task.category, label: category),
      ),
      Tooltip(
        message: strings.t('우선순위'),
        child: Text(priority, style: priorityStyle),
      ),
      if (task.repeat != RepeatUnit.none)
        Tooltip(
          message: strings.t('반복'),
          child: Icon(
            Icons.repeat_rounded,
            size: 16,
            color: TaskVisuals.muted,
            semanticLabel: strings.t('반복'),
          ),
        ),
    ];
    Widget body(double maxWidth, {required bool stacked}) {
      final children = metadataChildren(maxWidth);
      final metadata = stacked
          ? Wrap(
              key: Key('task-metadata-${o.id}'),
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children,
            )
          : Row(
              key: Key('task-metadata-${o.id}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0) const SizedBox(width: 6),
                  children[index],
                ],
              ],
            );
      return stacked
          ? Column(
              key: Key('task-content-${o.id}'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title(stacked: true),
                const SizedBox(height: 6),
                metadata,
              ],
            )
          : Row(
              key: Key('task-content-${o.id}'),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: title(stacked: false)),
                const SizedBox(width: 6),
                metadata,
              ],
            );
    }

    final supporting = <Widget>[
      if (showScheduleDate)
        _SupportingText(
          due.year == DateTime.now().year
              ? strings.dateShort(due)
              : strings.date(due),
          key: Key('task-schedule-date-${o.id}'),
        ),
      if (o.status == TaskStatus.paused)
        _SupportingText(taskReminderLabel(o, strings)),
      if (isCompleted && completedAt == null)
        _SupportingText(strings.t('완료 시각 기록 없음')),
      if (showOriginal)
        _SupportingText(
          strings.t(
            '원래 예정 {date} {time}',
            args: {'date': strings.date(due), 'time': strings.time(due)},
          ),
          key: Key('task-original-schedule-${o.id}'),
        ),
    ];

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      shape: const Border(
        bottom: BorderSide(color: TaskVisuals.line, width: .7),
      ),
      child: InkWell(
        key: ValueKey('task-row-${o.id}'),
        onTap: busy ? null : onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available =
                constraints.maxWidth - timeWidth - 8 - toggleSize.width - 4;
            // English AM/PM and large accessibility text can consume most of a
            // narrow row. Keep the clock readable and move the body below it.
            final stackedClock = available < 96 && scaler.scale(16) > 20;
            final bodyWidth = stackedClock ? constraints.maxWidth : available;
            final titleWidth = bodyWidth - metaWidth - 6;
            final stackedMeta =
                stackedClock ||
                (titleWidth <= 72 &&
                    (scaler.scale(16) > 16 || strings.isEnglish)) ||
                titleWidth < 32;
            final main = stackedClock
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [time, const Spacer(), toggle]),
                      const SizedBox(height: 6),
                      body(bodyWidth, stacked: true),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      time,
                      const SizedBox(width: 8),
                      Expanded(child: body(bodyWidth, stacked: stackedMeta)),
                      const SizedBox(width: 4),
                      toggle,
                    ],
                  );
            return ConstrainedBox(
              key: Key('task-row-layout-${o.id}'),
              constraints: BoxConstraints(minHeight: toggleSize.height + 8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    main,
                    if (supporting.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(
                          left: stackedClock ? 0 : timeWidth + 8,
                          top: 5,
                          bottom: 4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < supporting.length; i++) ...[
                              if (i > 0) const SizedBox(height: 3),
                              supporting[i],
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SupportingText extends StatelessWidget {
  final String text;
  const _SupportingText(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 12,
      height: 1.5,
      color: TaskVisuals.muted,
    ),
  );
}
