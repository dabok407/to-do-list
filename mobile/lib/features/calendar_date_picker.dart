import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_strings.dart';
import 'picker_sheet.dart';

/// A compact calendar using the same modal shell as the scrolling time picker.
/// Date changes remain a draft until confirmation, including keyboard entry.
Future<DateTime?> showTodoniqDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? title,
}) {
  final strings = AppStrings.of(context);
  final first = DateUtils.dateOnly(firstDate);
  final last = DateUtils.dateOnly(lastDate);
  var selected = DateUtils.dateOnly(initialDate);
  if (selected.isBefore(first)) selected = first;
  if (selected.isAfter(last)) selected = last;
  var enteringDate = false;
  final form = GlobalKey<FormState>();
  return showTodoniqPickerSheet<DateTime>(
    context: context,
    title: title ?? strings.t('날짜 선택'),
    selectedValue: () => selected,
    validate: () {
      if (!enteringDate) return true;
      if (form.currentState?.validate() != true) return false;
      form.currentState!.save();
      return true;
    },
    contentBuilder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('date-picker-entry-toggle'),
              onPressed: () {
                if (enteringDate) {
                  if (form.currentState?.validate() != true) return;
                  form.currentState!.save();
                }
                FocusScope.of(context).unfocus();
                setState(() => enteringDate = !enteringDate);
              },
              icon: Icon(
                enteringDate
                    ? Icons.calendar_month_outlined
                    : Icons.edit_outlined,
                size: 18,
              ),
              label: Text(strings.t(enteringDate ? '달력으로 선택' : '직접 입력')),
            ),
          ),
          if (enteringDate)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              child: Form(
                key: form,
                child: InputDatePickerFormField(
                  key: const Key('date-picker-input'),
                  initialDate: selected,
                  firstDate: first,
                  lastDate: last,
                  autofocus: true,
                  onDateSaved: (value) => selected = value,
                  onDateSubmitted: (value) => selected = value,
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) =>
                  // Seven fixed columns must keep both digits readable. Only
                  // the calendar grid is bounded; title, manual input, close
                  // and confirm continue following the full system text size.
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: constraints.maxWidth < 320 ? 1.2 : 1.4,
                    child: CalendarDatePicker(
                      key: const Key('date-picker-calendar'),
                      calendarDelegate:
                          constraints.maxWidth < 320 &&
                              Localizations.localeOf(context).languageCode ==
                                  'en'
                          ? const _CompactMonthCalendarDelegate()
                          : const GregorianCalendarDelegate(),
                      initialDate: selected,
                      firstDate: first,
                      lastDate: last,
                      onDateChanged: (value) => selected = value,
                    ),
                  ),
            ),
        ],
      ),
    ),
  );
}

/// Keep the year visible alongside the month on narrow English calendars.
/// Calendar arithmetic, week start, day semantics and input formats are intact.
class _CompactMonthCalendarDelegate extends GregorianCalendarDelegate {
  const _CompactMonthCalendarDelegate();

  @override
  String formatMonthYear(DateTime date, MaterialLocalizations localizations) =>
      DateFormat.yMMM('en').format(date);
}
