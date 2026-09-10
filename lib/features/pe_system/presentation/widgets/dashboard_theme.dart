import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DashboardColors {
  const DashboardColors(this.dark);

  factory DashboardColors.of(BuildContext context) =>
      DashboardColors(Theme.of(context).brightness == Brightness.dark);

  final bool dark;

  static const blue = Color(0xFF1565C0);
  static const pressed = Color(0xFF0D47A1);

  Color get accent => dark ? const Color(0xFF64B5F6) : blue;
  Color get background =>
      dark ? const Color(0xFF101820) : const Color(0xFFF5F8FC);
  Color get surface => dark ? const Color(0xFF192734) : Colors.white;
  Color get tint => dark ? const Color(0xFF203A52) : const Color(0xFFE3F2FD);
  Color get text => dark ? const Color(0xFFF1F7FC) : const Color(0xFF101820);
  Color get muted => dark ? const Color(0xFFA8BDCE) : const Color(0xFF607080);
  Color get divider => dark ? const Color(0xFF304658) : const Color(0xFFE8EFF5);
  Color get danger => dark ? const Color(0xFFFF8B93) : const Color(0xFFBF2639);
  Color get success => dark ? const Color(0xFF8FDEA5) : const Color(0xFF24733B);
  Color get warning => dark ? const Color(0xFFF2C078) : const Color(0xFF936017);

  SystemUiOverlayStyle get overlay => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: background,
    systemNavigationBarIconBrightness:
        dark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

/// Shared colors and component styling for the app's feature screens.
class DashboardTheme extends StatelessWidget {
  const DashboardTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final parent = Theme.of(context);
    final c = DashboardColors.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: DashboardColors.blue,
      brightness: parent.brightness,
    ).copyWith(
      primary: c.accent,
      onPrimary: c.dark ? c.background : Colors.white,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.muted,
      surfaceContainerHighest: c.tint,
      outlineVariant: c.divider,
      error: c.danger,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c.divider),
    );
    final button = FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: shape,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ).copyWith(
      overlayColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.pressed)
                ? DashboardColors.pressed.withValues(alpha: .15)
                : null,
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.overlay,
      child: Theme(
        data: parent.copyWith(
          colorScheme: scheme,
          scaffoldBackgroundColor: c.background,
          dividerColor: c.divider,
          textTheme: parent.textTheme.apply(
            bodyColor: c.text,
            displayColor: c.text,
          ),
          iconTheme: IconThemeData(color: c.muted),
          appBarTheme: AppBarTheme(
            backgroundColor: c.background,
            foregroundColor: c.text,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
            titleTextStyle: TextStyle(
              color: c.text,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
            systemOverlayStyle: c.overlay,
          ),
          cardTheme: CardThemeData(
            color: c.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: c.divider),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: c.surface,
            labelStyle: TextStyle(color: c.muted),
            hintStyle: TextStyle(color: c.muted),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: c.accent, width: 1.5),
            ),
            errorBorder: border.copyWith(
              borderSide: BorderSide(color: c.danger),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 16,
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(style: button),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: button.copyWith(
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.disabled) ? c.tint : c.accent,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.disabled)
                        ? c.muted
                        : scheme.onPrimary,
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              shape: shape,
              foregroundColor: c.accent,
              side: BorderSide(color: c.divider),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: c.accent,
              minimumSize: const Size(48, 48),
            ),
          ),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: c.accent,
            ),
          ),
          chipTheme: parent.chipTheme.copyWith(
            backgroundColor: c.surface,
            selectedColor: c.tint,
            labelStyle: TextStyle(color: c.text),
            side: BorderSide(color: c.divider),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: c.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          bottomSheetTheme: BottomSheetThemeData(
            backgroundColor: c.surface,
            surfaceTintColor: Colors.transparent,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
          ),
          popupMenuTheme: PopupMenuThemeData(
            color: c.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}
