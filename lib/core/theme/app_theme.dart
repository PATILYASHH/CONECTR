import 'package:flutter/material.dart';

/// Monochrome, matching XPENC's own default theme — true black/white, no
/// stray hue — laid out the One UI way: a soft page with brighter rounded
/// cards on it (light), or true black with lifted cards (dark).
///
/// The scheme is built explicitly: `colorSchemeSeed` assigns an arbitrary
/// hue even from an achromatic seed (a black seed rendered as wine/maroon).
class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final ink = isLight ? Colors.black : Colors.white;
    final paper = isLight ? Colors.white : Colors.black;
    final page = isLight ? const Color(0xFFF2F2F2) : Colors.black;
    final card = isLight ? Colors.white : const Color(0xFF171717);
    final raised = isLight ? const Color(0xFFEAEAEA) : const Color(0xFF222222);
    final muted = isLight ? const Color(0xFF6B6B6B) : const Color(0xFF9E9E9E);
    final line = isLight ? const Color(0xFFE2E2E2) : const Color(0xFF2A2A2A);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: ink,
      onPrimary: paper,
      primaryContainer: ink,
      onPrimaryContainer: paper,
      // The navigation bar's selected pill.
      secondary: ink,
      onSecondary: paper,
      secondaryContainer: ink,
      onSecondaryContainer: paper,
      error: isLight ? const Color(0xFFC62828) : const Color(0xFFFF6B6B),
      onError: paper,
      errorContainer: isLight
          ? const Color(0xFFFDECEC)
          : const Color(0xFF3A1515),
      onErrorContainer: isLight
          ? const Color(0xFF8C1D1D)
          : const Color(0xFFFFB4B4),
      surface: page,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerLowest: card,
      surfaceContainerLow: card,
      surfaceContainer: card,
      surfaceContainerHigh: raised,
      surfaceContainerHighest: line,
      outline: muted,
      outlineVariant: line,
      surfaceTint: Colors.transparent,
    );

    const pill = StadiumBorder();
    const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
    final rounded16 = BorderRadius.circular(16);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: page,
      appBarTheme: AppBarTheme(
        backgroundColor: page,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: paper,
          minimumSize: const Size.fromHeight(52),
          textStyle: buttonText,
          shape: pill,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: ink),
          minimumSize: const Size.fromHeight(52),
          textStyle: buttonText,
          shape: pill,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: ink,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? paper : ink,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        iconColor: ink,
        subtitleTextStyle: TextStyle(color: muted, fontSize: 13),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? paper : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? ink : line,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? ink : muted,
        ),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(ink)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: ink),
      dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: rounded16),
        focusedBorder: OutlineInputBorder(
          borderRadius: rounded16,
          borderSide: BorderSide(color: ink, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: TextStyle(color: paper),
        shape: RoundedRectangleBorder(borderRadius: rounded16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        showDragHandle: true,
      ),
    );
  }
}
