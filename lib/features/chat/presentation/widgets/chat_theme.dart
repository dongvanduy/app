import 'package:flutter/material.dart';

/// Colors shared with the web chat, scoped to messaging screens.
class ChatColors {
  const ChatColors(this.dark);
  factory ChatColors.of(BuildContext context) => ChatColors(Theme.of(context).brightness == Brightness.dark);
  final bool dark;

  static const purple = Color(0xFF5145DF);
  static const headerGradient = LinearGradient(
    colors: [Color(0xFF5145DF), Color(0xFF302682)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const sentGradient = LinearGradient(
    colors: [Color(0xFF594BEA), Color(0xFF4034D3)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );

  Color get accent => dark ? const Color(0xFFB4ACFF) : purple;
  Color get background => dark ? const Color(0xFF151727) : const Color(0xFFFAFAFF);
  Color get surface => dark ? const Color(0xFF1F2235) : Colors.white;
  Color get field => dark ? const Color(0xFF272B41) : const Color(0xFFF4F5FB);
  Color get incoming => dark ? const Color(0xFF2B3048) : const Color(0xFFECEEF7);
  Color get tint => dark ? const Color(0xFF383358) : const Color(0xFFEAE7FF);
  Color get readPill => dark ? const Color(0xFF3B3A66) : const Color(0xFFDFE1FF);
  Color get border => dark ? const Color(0xFF363B55) : const Color(0xFFE6E8F2);
  Color get text => dark ? const Color(0xFFF1F2FC) : const Color(0xFF1C213C);
  Color get muted => dark ? const Color(0xFFAFB5D0) : const Color(0xFF717A98);
  Color get danger => dark ? const Color(0xFFFF9CB5) : const Color(0xFFB0344E);
}

class ChatTheme extends StatelessWidget {
  const ChatTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final parent = Theme.of(context);
    final c = ChatColors.of(context);
    final scheme = ColorScheme.fromSeed(seedColor: ChatColors.purple, brightness: parent.brightness)
      .copyWith(primary: c.accent, surface: c.surface, onSurface: c.text,
        onSurfaceVariant: c.muted, outlineVariant: c.border, error: c.danger);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(13));
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide(color: c.border));
    return Theme(data: parent.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      dividerColor: c.border,
      textTheme: parent.textTheme.apply(bodyColor: c.text, displayColor: c.text),
      iconTheme: IconThemeData(color: c.muted),
      appBarTheme: AppBarTheme(backgroundColor: c.surface, foregroundColor: c.text,
        surfaceTintColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0,
        centerTitle: false, titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: c.field, isDense: true,
        border: border, enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: BorderSide(color: c.accent, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        hintStyle: TextStyle(color: c.muted, fontSize: 13)),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: ChatColors.purple, foregroundColor: Colors.white,
        minimumSize: const Size(44, 44), shape: shape)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: c.accent, side: BorderSide(color: c.accent.withValues(alpha: .3)),
        minimumSize: const Size(44, 44), shape: shape)),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.accent)),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: c.muted)),
      chipTheme: parent.chipTheme.copyWith(backgroundColor: c.surface, selectedColor: c.tint,
        side: BorderSide(color: c.border), labelStyle: TextStyle(color: c.text, fontSize: 12), shape: shape),
      tabBarTheme: parent.tabBarTheme.copyWith(labelColor: c.accent, unselectedLabelColor: c.muted,
        indicatorColor: c.accent, dividerColor: c.border,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      dialogTheme: DialogThemeData(backgroundColor: c.surface, surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.surface, surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22)))),
      popupMenuTheme: PopupMenuThemeData(color: c.surface, surfaceTintColor: Colors.transparent, shape: shape),
    ), child: child);
  }
}
