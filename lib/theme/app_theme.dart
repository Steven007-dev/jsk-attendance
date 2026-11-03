import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const navy = Color(0xFF1B2A4A);
  static const marigold = Color(0xFFE8A33D);
  static const coral = Color(0xFFE08268);
  static const green = Color(0xFF2F7D5E);
  static const greenLight = Color(0xFF6FBB93);
  static const brick = Color(0xFFB5482E);
  static const paper = Color(0xFFF6F4EF);
  static const ink = Color(0xFF21201C);
  static const night = Color(0xFF1A1A16);
  static const nightSurface = Color(0xFF232320);
  static const nightSurfaceRaised = Color(0xFF2C2C27);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? nightSurface : Colors.white;
    final background = isDark ? night : paper;
    final foreground = isDark ? const Color(0xFFF2EFE5) : ink;
    final muted = isDark ? const Color(0xFFC5C1B2) : const Color(0xFF6B6758);
    final line = isDark ? const Color(0xFF3B3B34) : const Color(0xFFC9C3B4);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: navy,
          brightness: brightness,
          primary: isDark ? marigold : navy,
          secondary: isDark ? greenLight : green,
          surface: surface,
          error: isDark ? coral : brick,
        ).copyWith(
          primary: isDark ? marigold : navy,
          onPrimary: isDark ? night : Colors.white,
          secondary: isDark ? greenLight : green,
          onSecondary: isDark ? night : Colors.white,
          tertiary: isDark ? coral : marigold,
          onTertiary: isDark ? night : ink,
          surface: surface,
          onSurface: foreground,
          onSurfaceVariant: muted,
          error: isDark ? coral : brick,
          outline: line,
          outlineVariant: line.withValues(alpha: .7),
          surfaceTint: isDark ? marigold : navy,
        );
    final textTheme = ThemeData(
      brightness: brightness,
      useMaterial3: true,
    ).textTheme.apply(bodyColor: foreground, displayColor: foreground);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'sans-serif',
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(
          fontFamily: 'serif',
          fontWeight: FontWeight.w600,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontFamily: 'serif',
          fontWeight: FontWeight.w600,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontFamily: 'serif',
          fontWeight: FontWeight.w600,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontFamily: 'serif',
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? navy : navy,
        foregroundColor: const Color(0xFFF2EFE5),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontFamily: 'serif',
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: Color(0xFFF2EFE5),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? night : const Color(0xFFEFEBE0),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        hintStyle: TextStyle(color: muted.withValues(alpha: .7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: marigold, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: marigold,
          foregroundColor: isDark ? night : Colors.white,
          disabledBackgroundColor: marigold.withValues(alpha: .45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: marigold.withValues(alpha: isDark ? .18 : .15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final active = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? nightSurfaceRaised : navy,
        contentTextStyle: const TextStyle(color: Color(0xFFF2EFE5)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
