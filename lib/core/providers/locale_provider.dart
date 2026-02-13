import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en')) {
    initialize();
  }

  Future<void> initialize() async {
    final savedLocale = await LocalizationService.loadLanguage();
    state = savedLocale;
  }

  Future<void> changeLocale(BuildContext context, Locale locale) async {
    if (state != locale) {
      state = locale;
      await LocalizationService.saveLanguage(locale.languageCode);
      await context.setLocale(locale);
    }
  }

  bool get isUrdu => state.languageCode == 'ur';
}