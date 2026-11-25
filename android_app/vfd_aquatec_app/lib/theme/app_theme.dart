import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary      = Color(0xFF00B4D8);
  static const Color primaryDark  = Color(0xFF0077B6);
  static const Color accent       = Color(0xFF48CAE4);
  static const Color background   = Color(0xFF0A0E1A);
  static const Color surface      = Color(0xFF111827);
  static const Color surfaceLight = Color(0xFF1F2937);
  static const Color border       = Color(0xFF2D3748);
  static const Color running      = Color(0xFF10B981);
  static const Color stopped      = Color(0xFFEF4444);
  static const Color warning      = Color(0xFFF59E0B);
  static const Color textPrimary  = Color(0xFFF9FAFB);
  static const Color textSecondary= Color(0xFF9CA3AF);
  static const Color textMuted    = Color(0xFF4B5563);

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: accent,
      surface: surface,
      error: stopped,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: textPrimary, fontSize: 18,
        fontWeight: FontWeight.w700, letterSpacing: 1,
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceLight, elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary, foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      labelStyle: const TextStyle(color: textSecondary),
      hintStyle: const TextStyle(color: textMuted),
    ),
    dividerColor: border,
  );
}
