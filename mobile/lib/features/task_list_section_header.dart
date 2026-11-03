import 'package:flutter/material.dart';

import 'visual_tokens.dart';

/// Date headings use the same hierarchy in upcoming and completed lists.
class TaskListSectionHeader extends StatelessWidget {
  final String label;

  const TaskListSectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      label,
      style: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 19,
        height: 1.5,
        fontWeight: FontWeight.w700,
        color: TaskVisuals.ink,
      ),
    ),
  );
}

/// One accessible toggle above all overdue dates.
class TaskListOverdueHeader extends StatelessWidget {
  final String label, countLabel, actionLabel;
  final bool selected;
  final VoidCallback onToggle;

  const TaskListOverdueHeader({
    super.key,
    required this.label,
    required this.countLabel,
    required this.actionLabel,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    hint: actionLabel,
    child: Tooltip(
      message: actionLabel,
      child: OutlinedButton(
        onPressed: onToggle,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.all(12),
          backgroundColor: selected ? TaskVisuals.quietSurface : Colors.white,
          foregroundColor: TaskVisuals.ink,
          side: BorderSide(
            color: selected
                ? TaskVisuals.muted.withValues(alpha: 0.30)
                : TaskVisuals.line,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                selected ? Icons.check_rounded : Icons.filter_alt_outlined,
                size: 20,
                color: selected ? TaskVisuals.ink : TaskVisuals.muted,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? Colors.white : TaskVisuals.quietSurface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  countLabel,
                  style: const TextStyle(fontSize: 13, height: 1.3),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
