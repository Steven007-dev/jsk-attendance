import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const navy = Color(0xFF1B2A4A);
  static const marigold = Color(0xFFE8A33D);
  static const green = Color(0xFF2F7D5E);
  static const brick = Color(0xFFB5482E);
  static const paper = Color(0xFFF6F4EF);
  static const ink = Color(0xFF21201C);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: navy,
      brightness: brightness,
      primary: isDark ? const Color(0xFF9FB1DF) : navy,
      secondary: isDark ? const Color(0xFFF0B559) : marigold,
      surface: isDark ? const Color(0xFF232320) : Colors.white,
      error: isDark ? const Color(0xFFE08268) : brick,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF1A1A16) : paper,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF1A1A16) : paper,
        foregroundColor: isDark ? const Color(0xFFF2EFE5) : ink,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF232320) : Colors.white,
        elevation: isDark ? 0 : 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF2C2C27) : const Color(0xFFEFEBE0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.secondary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF232320) : Colors.white,
        indicatorColor: scheme.secondary.withValues(alpha: .2),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }
}
