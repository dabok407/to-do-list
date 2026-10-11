import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const timePickerEntryModePreference = 'time_picker_entry_mode';

/// Remember the input UI separately from task data, including when cancelled.
Future<TimeOfDay?> showPersistentTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) async {
  SharedPreferences? preferences;
  var mode = TimePickerEntryMode.dial;
  try {
    preferences = await SharedPreferences.getInstance();
    if (preferences.getString(timePickerEntryModePreference) == 'input') {
      mode = TimePickerEntryMode.input;
    }
  } catch (_) {
    // A preference failure must not block scheduling a task.
  }
  if (!context.mounted) return null;
  final value = await showTimePicker(
    context: context,
    initialTime: initialTime,
    initialEntryMode: mode,
    onEntryModeChanged: (selected) => mode = selected,
  );
  try {
    await preferences?.setString(
      timePickerEntryModePreference,
      mode == TimePickerEntryMode.input ? 'input' : 'dial',
    );
  } catch (_) {
    // The selected time is still usable when preference storage is unavailable.
  }
  return value;
}
