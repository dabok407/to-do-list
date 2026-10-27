import 'package:flutter/material.dart';

import '../domain/task.dart';
import '../l10n/app_strings.dart';
import 'visual_tokens.dart';

/// Keep the compact detail sheet; improve the hierarchy without extra panels.
class TaskDetailMetadata extends StatelessWidget {
  final Occurrence occurrence;
  const TaskDetailMetadata({super.key, required this.occurrence});

  @override
  Widget build(BuildContext context) {
    final o = occurrence;
    final strings = AppStrings.of(context);
    final due = o.originalDue.toLocal();
    final color = TaskVisuals.categoryInk(o.task.category);
    Widget datePart(IconData icon, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 19, color: color)),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: TaskVisuals.ink,
            ),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            datePart(
              Icons.calendar_today_outlined,
              '${due.year == DateTime.now().year ? strings.dateShort(due) : strings.date(due)} (${strings.weekday(due.weekday)})',
            ),
            datePart(Icons.schedule, strings.time(due)),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CategoryLabel(
              category: o.task.category,
              label: strings.category(o.task.category),
            ),
            Text(
              strings.t(switch (o.task.priority) {
                2 => '높음',
                0 => '낮음',
                _ => '보통',
              }),
              style: TextStyle(
                fontSize: 13,
                color: TaskVisuals.priorityInk(o.task.priority),
              ),
            ),
            Text(
              strings.t(['예정', '진행 중', '보류', '완료', '건너뜀'][o.status.index]),
              style: const TextStyle(fontSize: 13, color: TaskVisuals.muted),
            ),
            if (o.task.repeat != RepeatUnit.none)
              Icon(
                Icons.repeat_rounded,
                size: 16,
                color: TaskVisuals.muted,
                semanticLabel: strings.t('반복'),
              ),
          ],
        ),
      ],
    );
  }
}
