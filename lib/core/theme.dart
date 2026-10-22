import 'package:flutter/material.dart';

/// Thème Material 3, couleur de marque commune à la famille « Nexa ».
class AppTheme {
  AppTheme._();

  static const Color brand = Color(0xFF6366F1);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(seedColor: brand, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
