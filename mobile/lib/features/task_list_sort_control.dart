import 'package:flutter/material.dart';

import '../domain/task_list_sections.dart';
import '../l10n/app_strings.dart';
import 'visual_tokens.dart';

class TaskListSortControl extends StatelessWidget {
  final bool completed;
  final TaskListOrder order;
  final ValueChanged<TaskListOrder> onChanged;

  const TaskListSortControl({
    super.key,
    required this.completed,
    required this.order,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final basis = strings.t(completed ? '완료일 기준' : '예정일 기준');
    String label(TaskListOrder value) =>
        strings.t(value == TaskListOrder.latest ? '최신순' : '오래된순');
    final menu = Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: const BorderSide(color: TaskVisuals.line),
      ),
      child: PopupMenuButton<TaskListOrder>(
        key: Key('task-sort-menu-${completed ? 'completed' : 'upcoming'}'),
        tooltip: strings.t('정렬 방식 선택'),
        initialValue: order,
        position: PopupMenuPosition.under,
        onSelected: onChanged,
        itemBuilder: (context) => [
          for (final value in TaskListOrder.values)
            PopupMenuItem(
              key: Key('task-sort-option-${value.name}'),
              value: value,
              height: 48,
              child: Row(
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: order == value
                        ? TaskVisuals.ink
                        : Colors.transparent,
                  ),
                  const SizedBox(width: 9),
                  Flexible(child: Text(label(value), style: _style)),
                ],
              ),
            ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swap_vert_rounded, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label(order),
                    textAlign: TextAlign.center,
                    style: _style,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.expand_more_rounded, size: 17),
              ],
            ),
          ),
        ),
      ),
    );
    final hint = Text(
      basis,
      style: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 12,
        height: 1.5,
        color: TaskVisuals.muted,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            MediaQuery.textScalerOf(context).scale(13) > 20
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hint,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: menu),
                ],
              )
            : Row(
                children: [
                  Expanded(child: hint),
                  const SizedBox(width: 12),
                  menu,
                ],
              ),
      ),
    );
  }

  static const _style = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w500,
    color: TaskVisuals.ink,
  );
}
