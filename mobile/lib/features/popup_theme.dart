import 'package:flutter/material.dart';

/// Captured by menu routes so legacy dropdowns and popup menus use the same
/// quiet selection state without changing focus colors elsewhere in the app.
class TodoniqMenuTheme extends StatelessWidget {
  const TodoniqMenuTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      canvasColor: TodoniqPopupTheme.surface,
      focusColor: TodoniqPopupTheme.mutedSurface,
      highlightColor: TodoniqPopupTheme.mutedSurface,
      hoverColor: TodoniqPopupTheme.quietSurface,
    ),
    child: child,
  );
}

/// Shared neutral surfaces for temporary choices, confirmations and menus.
/// These reuse Todoniq's existing palette instead of Material's seed tint.
abstract final class TodoniqPopupTheme {
  static const surface = Color(0xffffffff);
  static const ink = Color(0xff292c29);
  static const mutedSurface = Color(0xfff1f2f4);
  static const quietSurface = Color(0xfff4f5f5);
  static const border = Color(0xffe4e6ea);
  static const muted = Color(0xff676b73);
  static const barrier = Color(0x66000000);
  static const dialogRadius = 24.0;
  static const sheetRadius = 28.0;
  static const menuRadius = 14.0;

  static const titleStyle = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 20,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: -.4,
    color: ink,
  );
  static const bodyStyle = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 15,
    height: 1.5,
    letterSpacing: -.1,
    color: ink,
  );
  static const menuTextStyle = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w500,
    color: ink,
  );

  static const dialog = DialogThemeData(
    backgroundColor: surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    barrierColor: barrier,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(dialogRadius)),
    ),
    insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    actionsPadding: EdgeInsets.fromLTRB(16, 8, 16, 16),
    titleTextStyle: titleStyle,
    contentTextStyle: bodyStyle,
  );

  static const bottomSheet = BottomSheetThemeData(
    backgroundColor: surface,
    modalBackgroundColor: surface,
    surfaceTintColor: Colors.transparent,
    modalBarrierColor: barrier,
    elevation: 0,
    modalElevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(sheetRadius)),
    ),
    clipBehavior: Clip.antiAlias,
    showDragHandle: true,
    dragHandleColor: Color(0xffc9cdd3),
    dragHandleSize: Size(32, 4),
  );

  static const popupMenu = PopupMenuThemeData(
    color: surface,
    surfaceTintColor: Colors.transparent,
    elevation: 3,
    shadowColor: Color(0x1f000000),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(menuRadius)),
      side: BorderSide(color: border),
    ),
    menuPadding: EdgeInsets.symmetric(vertical: 6),
    textStyle: menuTextStyle,
    iconColor: ink,
  );

  static const menuStyle = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(surface),
    surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
    elevation: WidgetStatePropertyAll(3),
    shadowColor: WidgetStatePropertyAll(Color(0x1f000000)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(menuRadius)),
        side: BorderSide(color: border),
      ),
    ),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
  );

  static Color? _dateForeground(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return ink.withValues(alpha: .3);
    }
    return states.contains(WidgetState.selected) ? surface : ink;
  }

  static Color? _dateBackground(Set<WidgetState> states) =>
      states.contains(WidgetState.selected) ? ink : Colors.transparent;

  static Color? _dateOverlay(Set<WidgetState> states) {
    final selected = states.contains(WidgetState.selected);
    if (states.contains(WidgetState.pressed) ||
        states.contains(WidgetState.focused)) {
      return (selected ? surface : ink).withValues(alpha: .12);
    }
    if (states.contains(WidgetState.hovered)) {
      return (selected ? surface : ink).withValues(alpha: .06);
    }
    return Colors.transparent;
  }

  static final datePicker = DatePickerThemeData(
    backgroundColor: surface,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    shape: dialog.shape,
    headerBackgroundColor: surface,
    headerForegroundColor: ink,
    headerHeadlineStyle: titleStyle.copyWith(fontSize: 24),
    headerHelpStyle: menuTextStyle,
    weekdayStyle: menuTextStyle.copyWith(fontSize: 12, color: muted),
    dayStyle: menuTextStyle,
    dayForegroundColor: WidgetStateProperty.resolveWith(_dateForeground),
    dayBackgroundColor: WidgetStateProperty.resolveWith(_dateBackground),
    dayOverlayColor: WidgetStateProperty.resolveWith(_dateOverlay),
    todayForegroundColor: WidgetStateProperty.resolveWith(_dateForeground),
    todayBackgroundColor: WidgetStateProperty.resolveWith(_dateBackground),
    todayBorder: const BorderSide(color: ink),
    yearStyle: menuTextStyle,
    yearForegroundColor: WidgetStateProperty.resolveWith(_dateForeground),
    yearBackgroundColor: WidgetStateProperty.resolveWith(_dateBackground),
    yearOverlayColor: WidgetStateProperty.resolveWith(_dateOverlay),
    rangePickerBackgroundColor: surface,
    rangePickerElevation: 0,
    rangePickerSurfaceTintColor: Colors.transparent,
    rangePickerHeaderBackgroundColor: surface,
    rangePickerHeaderForegroundColor: ink,
    rangePickerHeaderHeadlineStyle: titleStyle.copyWith(fontSize: 22),
    rangePickerHeaderHelpStyle: menuTextStyle,
    rangeSelectionBackgroundColor: mutedSurface,
    rangeSelectionOverlayColor: WidgetStateProperty.resolveWith(_dateOverlay),
    subHeaderForegroundColor: ink,
    dividerColor: border,
    cancelButtonStyle: TextButton.styleFrom(
      foregroundColor: muted,
      minimumSize: const Size(64, 48),
      textStyle: menuTextStyle,
    ),
    confirmButtonStyle: TextButton.styleFrom(
      foregroundColor: surface,
      backgroundColor: ink,
      disabledForegroundColor: muted,
      disabledBackgroundColor: mutedSurface,
      minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      textStyle: menuTextStyle,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
