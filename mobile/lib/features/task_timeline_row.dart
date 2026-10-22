import 'package:flutter/material.dart';

import '../domain/task.dart';
import '../l10n/app_strings.dart';
import 'visual_tokens.dart';

/// The timeline presentation shared by upcoming and completed lists.
/// Calendar rows deliberately keep their existing compact presentation.
class TaskTimelineRow extends StatelessWidget {
  final Occurrence occurrence;
  final bool busy, hasProAccess, showScheduleDate;
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
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final o = occurrence;
    final isCompleted = o.status == TaskStatus.completed;
    final due = o.originalDue.toLocal();
    final completedAt = o.completed?.toLocal();
    final displayTime = isCompleted ? completedAt ?? due : due;
    final showOriginal =
        isCompleted &&
        (completedAt == null ||
            DateTime(
                  completedAt.year,
                  completedAt.month,
                  completedAt.day,
                  completedAt.hour,
                  completedAt.minute,
                ) !=
                DateTime(due.year, due.month, due.day, due.hour, due.minute));
    final priority = switch (o.task.priority) {
      2 => strings.t('높음'),
      0 => strings.t('낮음'),
      _ => strings.t('보통'),
    };
    final time = Semantics(
      label: isCompleted && completedAt != null
          ? strings.t('완료 시각 {time}', args: {'time': strings.time(displayTime)})
          : strings.t(
              '예정 시각 {time}',
              args: {
                'time': showScheduleDate
                    ? '${strings.date(due)} ${strings.time(displayTime)}'
                    : strings.time(displayTime),
              },
            ),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.time(displayTime),
            key: Key('task-time-${o.id}'),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: TaskVisuals.ink,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (showScheduleDate)
            Text(
              due.year == DateTime.now().year
                  ? strings.dateShort(due)
                  : strings.date(due),
              style: const TextStyle(fontSize: 11, color: TaskVisuals.muted),
            ),
        ],
      ),
    );
    final toggle = SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: strings.t(isCompleted ? '완료 해제' : '완료 처리'),
        onPressed: busy || o.status == TaskStatus.skipped ? null : onToggle,
        icon: Icon(
          isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isCompleted ? TaskVisuals.muted : TaskVisuals.ink,
          size: 23,
        ),
      ),
    );
    final start = o.active && o.status != TaskStatus.progressing
        ? SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              key: ValueKey('start-${o.id}'),
              tooltip: strings.t(
                '{title} 지금 시작{pro}',
                args: {
                  'title': o.task.title,
                  'pro': hasProAccess ? '' : ' · Pro',
                },
              ),
              onPressed: busy ? null : onStart,
              icon: Icon(
                hasProAccess ? Icons.play_arrow_rounded : Icons.lock_outline,
                color: TaskVisuals.ink,
                size: 23,
              ),
            ),
          )
        : null;

    Widget content(double maxWidth) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 9),
          child: Text(
            o.task.title,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: isCompleted ? TaskVisuals.muted : TaskVisuals.ink,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: CategoryLabel(
                category: o.task.category,
                label: strings.category(o.task.category),
              ),
            ),
            Tooltip(
              message: strings.t('우선순위'),
              child: Text(
                priority,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  height: 1.5,
                  color: TaskVisuals.priorityInk(o.task.priority),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (o.task.repeat != RepeatUnit.none)
              Tooltip(
                message: strings.t('반복'),
                child: Icon(
                  Icons.repeat_rounded,
                  size: 16,
                  color: TaskVisuals.muted,
                  semanticLabel: strings.t('반복'),
                ),
              ),
          ],
        ),
        if (o.status == TaskStatus.paused) ...[
          const SizedBox(height: 5),
          _SupportingText(
            strings.t(
              '· {time} 재알림',
              args: {'time': strings.time(o.reminder.toLocal())},
            ),
          ),
        ],
        if (isCompleted && completedAt == null) ...[
          const SizedBox(height: 5),
          _SupportingText(strings.t('완료 시각 기록 없음')),
        ],
        if (showOriginal) ...[
          const SizedBox(height: 5),
          _SupportingText(
            strings.t(
              '원래 예정 {date} {time}',
              args: {'date': strings.date(due), 'time': strings.time(due)},
            ),
            key: Key('task-original-schedule-${o.id}'),
          ),
        ],
      ],
    );

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      shape: const Border(
        bottom: BorderSide(color: TaskVisuals.line, width: .7),
      ),
      child: InkWell(
        key: ValueKey('task-row-${o.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final stacked =
                  scale > 1.35 || (constraints.maxWidth < 320 && scale > 1.1);
              final timeWidth = strings.isEnglish ? 68.0 : 54.0;
              final bodyWidth =
                  constraints.maxWidth -
                  44 -
                  (start == null ? 0 : 44) -
                  (stacked ? 0 : timeWidth + 8);
              final body = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  toggle,
                  Expanded(child: content(bodyWidth)),
                  ?start,
                ],
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 44, bottom: 2),
                      child: time,
                    ),
                    body,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: timeWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: time,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: body),
                ],
              );
            },
          ),
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
