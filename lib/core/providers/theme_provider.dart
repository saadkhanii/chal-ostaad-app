import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Theme modes enum
enum ThemeModeType { system, light, dark }

// Theme state
class ThemeState {
  final ThemeModeType themeMode;
  final bool isDark;

  const ThemeState({
    required this.themeMode,
    required this.isDark,
  });

  ThemeState copyWith({
    ThemeModeType? themeMode,
    bool? isDark,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      isDark: isDark ?? this.isDark,
    );
  }
}

// Theme provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier()
      : super(const ThemeState(
    themeMode: ThemeModeType.system,
    isDark: false,
  )) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString('theme_mode') ?? 'system';

      ThemeModeType themeMode;
      bool isDark = false;

      switch (savedTheme) {
        case 'light':
          themeMode = ThemeModeType.light;
          isDark = false;
          break;
        case 'dark':
          themeMode = ThemeModeType.dark;
          isDark = true;
          break;
        default:
          themeMode = ThemeModeType.system;
          // Check system preference
          isDark = WidgetsBinding.instance.window.platformBrightness == Brightness.dark;
          break;
      }

      state = ThemeState(themeMode: themeMode, isDark: isDark);
    } catch (e) {
      // Use default theme
    }
  }

  Future<void> setTheme(ThemeModeType themeMode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool isDark;

      switch (themeMode) {
        case ThemeModeType.light:
          await prefs.setString('theme_mode', 'light');
          isDark = false;
          break;
        case ThemeModeType.dark:
          await prefs.setString('theme_mode', 'dark');
          isDark = true;
          break;
        default:
          await prefs.setString('theme_mode', 'system');
          isDark = WidgetsBinding.instance.window.platformBrightness == Brightness.dark;
          break;
      }

      state = state.copyWith(themeMode: themeMode, isDark: isDark);
    } catch (e) {
      // Handle error
    }
  }

  void toggleTheme() {
    final newIsDark = !state.isDark;
    final newThemeMode = newIsDark ? ThemeModeType.dark : ThemeModeType.light;
    setTheme(newThemeMode);
  }
}