import 'package:flutter/material.dart';

import 'popup_theme.dart';

/// A single choice within a modal; RadioGroup supplies selection semantics.
class PopupChoiceTile<T> extends StatelessWidget {
  const PopupChoiceTile({
    super.key,
    required this.value,
    required this.selected,
    required this.title,
    this.subtitle,
  });

  final T value;
  final bool selected;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => RadioListTile<T>(
    value: value,
    selected: selected,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    activeColor: TodoniqPopupTheme.ink,
    selectedTileColor: TodoniqPopupTheme.mutedSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected ? TodoniqPopupTheme.ink : TodoniqPopupTheme.border,
        width: selected ? 1.2 : 1,
      ),
    ),
    title: Text(
      title,
      style: TodoniqPopupTheme.bodyStyle.copyWith(fontWeight: FontWeight.w600),
    ),
    subtitle: subtitle == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle!,
              style: TodoniqPopupTheme.bodyStyle.copyWith(
                fontSize: 13,
                color: TodoniqPopupTheme.muted,
              ),
            ),
          ),
  );
}
