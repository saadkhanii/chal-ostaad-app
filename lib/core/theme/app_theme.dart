import 'package:flutter/material.dart';

import '../constants/colors.dart';
import '../constants/sizes.dart';
import '../theme/text_theme.dart';

class CAppTheme {
  CAppTheme._(); // private constructor

  /// Light Theme
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: CColors.primary,
    scaffoldBackgroundColor: CColors.light,
    colorScheme: const ColorScheme.light(
      primary: CColors.primary,
      secondary: CColors.secondary,
      background: CColors.light,
      surface: CColors.light,
    ),
    textTheme: CTextTheme.lightTheme,
    elevatedButtonTheme: _elevatedButtonTheme(
      background: CColors.secondary,
      foreground: CColors.light,
    ),
    inputDecorationTheme: _inputDecorationTheme(
      focusedColor: CColors.secondary,
    ),
  );

  /// Dark Theme
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: CColors.primary,
    scaffoldBackgroundColor: CColors.secondary,
    colorScheme: const ColorScheme.dark(
      primary: CColors.primary,
      secondary: CColors.light,
      background: CColors.secondary,
      surface: CColors.secondary,
    ),
    textTheme: CTextTheme.darkTheme,
    elevatedButtonTheme: _elevatedButtonTheme(
      background: CColors.primary,
      foreground: CColors.secondary,
    ),
    inputDecorationTheme: _inputDecorationTheme(
      focusedColor: CColors.primary,
    ),
  );

  /// Common ElevatedButtonTheme
  static ElevatedButtonThemeData _elevatedButtonTheme({
    required Color background,
    required Color foreground,
  }) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.buttonRadius),
        ),
      ),
    );
  }

  /// Common InputDecorationTheme
  static InputDecorationTheme _inputDecorationTheme({
    required Color focusedColor,
  }) {
    return InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CSizes.inputFieldRadius),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CSizes.inputFieldRadius),
        borderSide: BorderSide(color: focusedColor, width: 2),
      ),
    );
  }
}
