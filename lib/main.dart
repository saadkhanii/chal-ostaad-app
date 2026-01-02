import 'package:chal_ostaad/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chal_ostaad/firebase/firebase_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chal_ostaad/core/providers/theme_provider.dart';

// Import providers
import 'core/providers/shared_prefs_provider.dart';
import 'core/routes/app_router.dart';
import 'core/routes/app_routes.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SharedPreferences early
  final sharedPreferences = await SharedPreferences.getInstance();

  // Firebase initialization
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize client app if needed
    try {
      Firebase.app('client');
    } catch (_) {
      await Firebase.initializeApp(
        name: 'client',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // Initialize worker app if needed
    try {
      Firebase.app('worker');
    } catch (_) {
      await Firebase.initializeApp(
        name: 'worker',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    print('Firebase initialization error: $e');
  }

  runApp(
    ProviderScope(
      overrides: [
        // Override the sharedPreferencesProvider with actual instance
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const ChalOstaadApp(),
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
      theme: CAppTheme.lightTheme,
      darkTheme: CAppTheme.darkTheme,
      themeMode: themeState.themeMode == ThemeModeType.system
          ? ThemeMode.system
          : (themeState.themeMode == ThemeModeType.dark ? ThemeMode.dark : ThemeMode.light),
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}