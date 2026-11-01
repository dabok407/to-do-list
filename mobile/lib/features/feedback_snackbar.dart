import 'dart:async';

import 'package:flutter/material.dart';

const feedbackDuration = Duration(seconds: 3);

/// Brief feedback must time out even when it offers an Undo action.
SnackBar feedbackSnackBar({required Widget content, SnackBarAction? action}) =>
    SnackBar(
      content: content,
      action: action,
      duration: feedbackDuration,
      persist: false,
    );

/// A modal route sits above the home Scaffold's snackbar. Keep the same brief
/// feedback on the sheet itself without expanding its approved content height.
class SheetFeedbackController extends ValueNotifier<SnackBar?> {
  SheetFeedbackController() : super(null);
  Timer? _timer;
  bool closed = false;

  void show(SnackBar message) {
    if (closed) return;
    _timer?.cancel();
    value = message;
    _timer = Timer(feedbackDuration, clear);
  }

  void clear() {
    _timer?.cancel();
    if (!closed) value = null;
  }

  @override
  void dispose() {
    if (closed) return;
    closed = true;
    _timer?.cancel();
    super.dispose();
  }
}

class SheetFeedbackHost extends StatelessWidget {
  final SheetFeedbackController controller;
  final Widget child;
  const SheetFeedbackHost({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SnackBar?>(
    valueListenable: controller,
    builder: (context, message, _) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final snackTheme = theme.snackBarTheme;
      return Stack(
        children: [
          child,
          if (message != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
              child: Semantics(
                liveRegion: true,
                container: true,
                child: Material(
                  key: const Key('sheet-feedback'),
                  color: snackTheme.backgroundColor ?? colors.inverseSurface,
                  elevation: snackTheme.elevation ?? 6,
                  shape:
                      snackTheme.shape ??
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: DefaultTextStyle(
                      style:
                          snackTheme.contentTextStyle ??
                          theme.textTheme.bodyMedium!.copyWith(
                            color: colors.onInverseSurface,
                          ),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        children: [
                          message.content,
                          if (message.action case final action?)
                            TextButton(
                              onPressed: () {
                                controller.clear();
                                action.onPressed();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    snackTheme.actionTextColor ??
                                    colors.inversePrimary,
                              ),
                              child: Text(action.label),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
