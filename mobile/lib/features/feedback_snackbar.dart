import 'package:flutter/material.dart';

/// Brief feedback must time out even when it offers an Undo action.
SnackBar feedbackSnackBar({required Widget content, SnackBarAction? action}) =>
    SnackBar(
      content: content,
      action: action,
      duration: const Duration(seconds: 3),
      persist: false,
    );
