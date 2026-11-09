import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'popup_theme.dart';

/// A single confirmation surface for date and time selection. Dismissing it
/// never commits the draft value kept by the caller.
Future<T?> showTodoniqPickerSheet<T>({
  required BuildContext context,
  required String title,
  String? description,
  required WidgetBuilder contentBuilder,
  required T Function() selectedValue,
  String? confirmLabel,
  bool Function()? validate,
  ValueListenable<bool>? canConfirm,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: TodoniqPopupTheme.surface,
    barrierColor: TodoniqPopupTheme.barrier,
    constraints: const BoxConstraints(maxWidth: 480),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TodoniqPopupTheme.sheetRadius),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (sheetContext) => TodoniqPickerSheet(
      title: title,
      description: description,
      confirmLabel: confirmLabel,
      canConfirm: canConfirm,
      onConfirm: () {
        if (validate?.call() ?? true) {
          Navigator.of(sheetContext).pop(selectedValue());
        }
      },
      child: contentBuilder(sheetContext),
    ),
  );
}

class TodoniqPickerSheet extends StatelessWidget {
  const TodoniqPickerSheet({
    super.key,
    required this.title,
    this.description,
    this.confirmLabel,
    this.canConfirm,
    required this.onConfirm,
    required this.child,
  });

  final String title;
  final String? description, confirmLabel;
  final ValueListenable<bool>? canConfirm;
  final VoidCallback onConfirm;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    Widget confirm(bool enabled) => SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const Key('picker-confirm'),
        onPressed: enabled ? onConfirm : null,
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
        child: Text(confirmLabel ?? localizations.okButtonLabel),
      ),
    );
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              namesRoute: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: TodoniqPopupTheme.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: localizations.cancelButtonLabel,
            onPressed: () => Navigator.of(context).pop(),
            color: TodoniqPopupTheme.muted,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 12),
              child: Text(
                description!,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: TodoniqPopupTheme.muted),
              ),
            ),
          child,
        ],
      ),
    );
    final footer = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: canConfirm != null
          ? ValueListenableBuilder<bool>(
              valueListenable: canConfirm!,
              builder: (context, enabled, _) => confirm(enabled),
            )
          : confirm(true),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep cancel and confirm visible while the selection body scrolls.
            // When a landscape keyboard leaves less than one toolbar's worth
            // of content, allow the entire sheet to scroll instead of overflow.
            final minimumPinnedHeight =
                MediaQuery.textScalerOf(context).scale(18) * 3 + 128;
            if (constraints.maxHeight < minimumPinnedHeight) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, body, footer],
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Flexible(child: SingleChildScrollView(child: body)),
                footer,
              ],
            );
          },
        ),
      ),
    );
  }
}
