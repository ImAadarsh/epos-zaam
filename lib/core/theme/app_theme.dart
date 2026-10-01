import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Zaam brand palette.
class ZaamColors {
  static const gold = Color(0xFFD4A017);
  static const black = Color(0xFF0A0A0A);
  static const charcoal = Color(0xFF1E1E1E);
  static const grey = Color(0xFF6B6B6B);
  static const softGrey = Color(0xFFE5E5E5);
  static const green = Color(0xFF2ECC71);
  static const amber = Color(0xFFF39C12);
  static const red = Color(0xFFE74C3C);
  static const info = Color(0xFF34495E);
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: ZaamColors.gold,
      brightness: brightness,
      primary: dark ? ZaamColors.gold : const Color(0xFF9A7300),
      onPrimary: dark ? ZaamColors.black : Colors.white,
      secondary: dark ? const Color(0xFFE5C45A) : ZaamColors.charcoal,
      error: ZaamColors.red,
      surface: dark ? const Color(0xFF141414) : Colors.white,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
    final text = GoogleFonts.poppinsTextTheme(base.textTheme);
    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: dark ? ZaamColors.black : const Color(0xFFF6F5F2),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? ZaamColors.charcoal : Colors.white,
        foregroundColor: dark ? Colors.white : ZaamColors.black,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: dark ? Colors.white : ZaamColors.black),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? ZaamColors.charcoal : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: dark ? const Color(0xFF2C2C2C) : ZaamColors.softGrey)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1A1A1A) : const Color(0xFFF9F9F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: dark ? ZaamColors.charcoal : Colors.white,
        indicatorColor: ZaamColors.gold.withValues(alpha: dark ? 0.35 : 0.25),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? ZaamColors.charcoal : Colors.white,
        indicatorColor: ZaamColors.gold.withValues(alpha: dark ? 0.35 : 0.25),
      ),
      chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      dividerTheme: DividerThemeData(color: dark ? const Color(0xFF2C2C2C) : ZaamColors.softGrey, space: 1),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
