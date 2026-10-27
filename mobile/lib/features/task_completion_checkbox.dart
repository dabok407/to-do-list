import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'visual_tokens.dart';

/// A task's independent done state, not selection for a bulk action.
class TaskCompletionCheckbox extends StatelessWidget {
  final bool completed, enabled;
  final VoidCallback onToggle;
  const TaskCompletionCheckbox({
    super.key,
    required this.completed,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final label = AppStrings.of(context).t(completed ? '완료 해제' : '완료 처리');
    return Tooltip(
      message: label,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Checkbox(
          value: completed,
          semanticLabel: label,
          activeColor: TaskVisuals.muted,
          checkColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          side: const BorderSide(color: TaskVisuals.muted, width: 1.6),
          onChanged: enabled ? (_) => onToggle() : null,
        ),
      ),
    );
  }
}
