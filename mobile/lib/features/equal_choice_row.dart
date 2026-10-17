import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Equal shares of the available width, without wrapping the buttons themselves.
///
/// Labels can use more than one line at large accessibility sizes. Every button
/// in that row grows to the tallest label, so the full label remains available.
/// Additional legacy/custom choices follow below the first [maxColumns] choices.
class EqualChoiceRow<T> extends StatelessWidget {
  final Map<T, String> choices;
  final T value;
  final ValueChanged<T>? onChanged;
  final String? optionKeyPrefix;
  final int maxColumns;

  const EqualChoiceRow({
    super.key,
    required this.choices,
    required this.value,
    this.onChanged,
    this.optionKeyPrefix,
    this.maxColumns = 5,
  }) : assert(maxColumns > 0);

  @override
  Widget build(BuildContext context) {
    if (choices.isEmpty) return const SizedBox.shrink();

    final options = choices.entries.toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        assert(
          constraints.hasBoundedWidth,
          'EqualChoiceRow needs the available width of its form or card.',
        );
        final gap = constraints.maxWidth < 300 ? 4.0 : 6.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (
              var start = 0;
              start < options.length;
              start += maxColumns
            ) ...[
              if (start > 0) SizedBox(height: gap),
              _row(
                context,
                options.sublist(
                  start,
                  math.min(start + maxColumns, options.length),
                ),
                constraints.maxWidth,
                gap,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    List<MapEntry<T, String>> options,
    double availableWidth,
    double gap,
  ) {
    final cellWidth =
        (availableWidth - gap * (options.length - 1)) / options.length;
    // Explicit label width also makes ChoiceChip's painted Material fill its
    // equal share; constraining the outer chip alone leaves that Material loose.
    final labelWidth = math.max(0.0, cellWidth - 8);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < options.length; index++) ...[
            if (index > 0) SizedBox(width: gap),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: ChoiceChip(
                  key: optionKeyPrefix == null
                      ? null
                      : ValueKey('$optionKeyPrefix-${options[index].key}'),
                  label: SizedBox(
                    width: labelWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Builder(
                        builder: (context) {
                          final inherited = DefaultTextStyle.of(context);
                          // ChoiceChip supplies the selected/disabled style, but
                          // also a one-line limit. Preserve its style and lift
                          // only that limit so accessibility sizes stay intact.
                          return DefaultTextStyle(
                            style: inherited.style,
                            textAlign: TextAlign.center,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                            textWidthBasis: inherited.textWidthBasis,
                            textHeightBehavior: inherited.textHeightBehavior,
                            child: Center(
                              child: Text(
                                options[index].value,
                                textAlign: TextAlign.center,
                                softWrap: true,
                                overflow: TextOverflow.visible,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  selected: value == options[index].key,
                  showCheckmark: false,
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.standard,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: onChanged == null
                      ? null
                      : (_) => onChanged!(options[index].key),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
