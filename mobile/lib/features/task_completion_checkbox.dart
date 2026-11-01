import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'visual_tokens.dart';

/// A task's independent done state, not selection for a bulk action.
class TaskCompletionCheckbox extends StatelessWidget {
  final bool completed, enabled;
  final VoidCallback onToggle;

  /// The timeline uses a 24 px indicator with a caption; compact callers can
  /// retain the existing Material checkbox and 44 px target.
  final bool showLabel;
  final String? semanticLabel;
  const TaskCompletionCheckbox({
    super.key,
    required this.completed,
    required this.enabled,
    required this.onToggle,
    this.showLabel = false,
    this.semanticLabel,
  });

  static TextStyle captionStyle(bool completed) => TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 11,
    height: 1.2,
    fontWeight: completed ? FontWeight.w600 : FontWeight.w400,
    color: completed ? TaskVisuals.ink : TaskVisuals.muted,
  );

  /// Reserve both labels so checking a task never shifts its neighboring title.
  static Size labeledSize(BuildContext context) {
    final strings = AppStrings.of(context);
    var width = 48.0;
    var height = 56.0;
    for (final completed in [false, true]) {
      final painter = TextPainter(
        text: TextSpan(
          text: strings.t(completed ? '완료됨' : '완료'),
          style: DefaultTextStyle.of(context).style
              .merge(captionStyle(completed)),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      width = (painter.width.ceilToDouble() + 8).clamp(width, double.infinity);
      // Label begins 1 px below the centered indicator's lower edge.
      height = ((2 * (13 + painter.height) / 4).ceil() * 4).toDouble().clamp(
        height,
        double.infinity,
      );
      painter.dispose();
    }
    return Size(width, height);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final label = strings.t(completed ? '완료 해제' : '완료 처리');
    if (showLabel) {
      final size = labeledSize(context);
      return Tooltip(
        message: label,
        child: Semantics(
          checked: completed,
          enabled: enabled,
          label: semanticLabel ?? label,
          onTap: enabled ? onToggle : null,
          excludeSemantics: true,
          child: InkWell(
            onTap: enabled ? onToggle : null,
            excludeFromSemantics: true,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              key: const Key('task-completion-target'),
              width: size.width,
              height: size.height,
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      key: const Key('task-completion-indicator'),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: completed ? TaskVisuals.ink : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: completed
                              ? TaskVisuals.ink
                              : TaskVisuals.muted,
                          width: 1.8,
                        ),
                      ),
                      child: completed
                          ? const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: size.height / 2 + 13,
                    child: Text(
                      strings.t(completed ? '완료됨' : '완료'),
                      key: const Key('task-completion-caption'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      softWrap: false,
                      style: captionStyle(completed),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: label,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Checkbox(
          value: completed,
          semanticLabel: semanticLabel ?? label,
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
