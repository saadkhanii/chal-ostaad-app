import 'package:chal_ostaad/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chal_ostaad/firebase/firebase_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chal_ostaad/core/providers/theme_provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:chal_ostaad/core/services/localization_service.dart';
import 'package:chal_ostaad/core/services/notification_service.dart';
import 'dart:ui' as ui;

import 'core/providers/shared_prefs_provider.dart';
import 'core/routes/app_router.dart';
import 'core/routes/app_routes.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance();
  await EasyLocalization.ensureInitialized();

  try {
    // 🔥 ALWAYS use the default app
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final notificationService = NotificationService();
    await notificationService.initialize();
  } catch (e) {
    print('Firebase initialization error: $e');
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: EasyLocalization(
        supportedLocales: LocalizationService.supportedLocales,
        path: LocalizationService.path,
        fallbackLocale: LocalizationService.defaultLocale,
        child: const ChalOstaadApp(),
      ),
    ),
  );
}

class ChalOstaadApp extends ConsumerWidget {
  const ChalOstaadApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: CAppTheme.lightTheme,
      darkTheme: CAppTheme.darkTheme,
      themeMode: themeState.themeMode == ThemeModeType.system
          ? ThemeMode.system
          : (themeState.themeMode == ThemeModeType.dark
          ? ThemeMode.dark
          : ThemeMode.light),
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      builder: (context, child) {
        return Directionality(
          textDirection: context.locale.languageCode == 'ur'
              ? ui.TextDirection.rtl
              : ui.TextDirection.ltr,
          child: child!,
        );
      },
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
