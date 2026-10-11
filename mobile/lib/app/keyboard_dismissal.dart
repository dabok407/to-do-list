import 'package:flutter/material.dart';

/// Shares keyboard dismissal with every route, sheet and dialog in the app.
class KeyboardDismissal extends StatelessWidget {
  final Widget child;

  const KeyboardDismissal({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      // Flutter's default action leaves native mobile touch focused. Using the
      // field's own tap region also preserves focus transfers and button taps.
      EditableTextTapOutsideIntent:
          CallbackAction<EditableTextTapOutsideIntent>(
            onInvoke: (intent) {
              intent.focusNode.unfocus();
              return null;
            },
          ),
    },
    child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      ),
      child: child,
    ),
  );
}
