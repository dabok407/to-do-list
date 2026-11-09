import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'picker_sheet.dart';
import 'popup_theme.dart';

// Kept as a legacy preference key. Existing installations may contain it, but
// the wheel picker intentionally supersedes both old dial and numeric modes.
const timePickerEntryModePreference = 'time_picker_entry_mode';

Future<TimeOfDay?> showPersistentTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) async {
  var selected = initialTime;
  var finished = false;
  final canConfirm = ValueNotifier(true);
  final scrolling = <BuildContext>{};
  final korean = Localizations.localeOf(context).languageCode == 'ko';
  try {
    return await showTodoniqPickerSheet<TimeOfDay>(
      context: context,
      title: korean ? '시간 선택' : 'Choose time',
      description: korean
          ? '위아래로 넘겨 시간을 선택해요.'
          : 'Scroll up or down to choose a time.',
      selectedValue: () => selected,
      canConfirm: canConfirm,
      contentBuilder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          // CupertinoDatePicker intentionally ignores inherited text scaling.
          // Enlarge its own font and row together without clipping its locale-
          // dependent AM/PM columns on the smallest supported screen.
          final fontSize = math.min(
            MediaQuery.textScalerOf(context).scale(24),
            constraints.maxWidth < 320 ? 30.0 : 34.0,
          );
          final itemExtent = math.max(48.0, fontSize * 1.6);
          final theme = Theme.of(context);
          return SizedBox(
            height: itemExtent * 5,
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: Brightness.light,
                primaryColor: TodoniqPopupTheme.ink,
                textTheme: CupertinoTextThemeData(
                  dateTimePickerTextStyle:
                      (theme.textTheme.titleLarge ?? const TextStyle())
                          .copyWith(
                            fontFamily: 'Pretendard',
                            fontSize: fontSize,
                            fontWeight: FontWeight.w400,
                            color: TodoniqPopupTheme.ink,
                            height: 1.2,
                          ),
                ),
              ),
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (finished) return false;
                  final source = notification.context;
                  if (source == null) return false;
                  if (notification is ScrollStartNotification) {
                    scrolling.add(source);
                  } else if (notification is ScrollEndNotification) {
                    scrolling.remove(source);
                  }
                  canConfirm.value = scrolling.isEmpty;
                  return false;
                },
                child: CupertinoDatePicker(
                  key: const Key('time-wheel-picker'),
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: DateTime(
                    2000,
                    1,
                    1,
                    initialTime.hour,
                    initialTime.minute,
                  ),
                  use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
                  itemExtent: itemExtent,
                  backgroundColor: TodoniqPopupTheme.surface,
                  selectionOverlayBuilder:
                      (
                        context, {
                        required selectedIndex,
                        required columnCount,
                      }) => CupertinoPickerDefaultSelectionOverlay(
                        // Cupertino paints this above the wheel text. Keep it
                        // translucent so the selected digits remain visible.
                        background: TodoniqPopupTheme.ink.withValues(
                          alpha: .06,
                        ),
                        capStartEdge: selectedIndex == 0,
                        capEndEdge: selectedIndex == columnCount - 1,
                      ),
                  onDateTimeChanged: (value) {
                    selected = TimeOfDay.fromDateTime(value);
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  } finally {
    finished = true;
    canConfirm.dispose();
  }
}
