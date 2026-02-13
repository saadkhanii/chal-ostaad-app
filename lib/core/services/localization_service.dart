import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui;

class LocalizationService {
  static const String LANGUAGE_KEY = 'app_language';

  // Available locales
  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ur'), // Urdu
  ];

  // Default locale
  static const Locale defaultLocale = Locale('en');

  // Get path for translations
  static const String path = 'assets/translations';

  // Save language preference
  static Future<void> saveLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LANGUAGE_KEY, languageCode);
  }

  // Load saved language
  static Future<Locale> loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString(LANGUAGE_KEY);

    if (languageCode == 'ur') {
      return const Locale('ur');
    }
    return defaultLocale;
  }

  // Get current locale
  static Future<Locale> getCurrentLocale() async {
    return await loadLanguage();
  }

  // Check if current language is Urdu
  static bool isUrdu(BuildContext context) {
    return context.locale.languageCode == 'ur';
  }

  // Get text direction
  static ui.TextDirection getTextDirection(BuildContext context) {
    return isUrdu(context) ? ui.TextDirection.rtl : ui.TextDirection.ltr;
  }
}