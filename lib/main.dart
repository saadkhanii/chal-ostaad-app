// lib/main.dart

import 'package:chal_ostaad/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
// It seems your options are in 'firebase/firebase_options.dart'
// If this path is wrong, please correct it.
import 'package:chal_ostaad/firebase/firebase_options.dart';

import 'core/routes/app_router.dart';
import 'core/routes/app_routes.dart';

void main() async {
  // 1. Ensure Flutter bindings are ready.
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Get the platform-specific Firebase configuration.
  final firebaseOptions = DefaultFirebaseOptions.currentPlatform;

  // --- THIS IS THE CRITICAL FIX ---
  // 3. Initialize all three required Firebase app instances.

  // The default instance for your admin panel.
  await Firebase.initializeApp(
    options: firebaseOptions,
  );

  // The secondary, named instance for 'client' users.
  await Firebase.initializeApp(
    name: 'client',
    options: firebaseOptions,
  );

  // The secondary, named instance for 'worker' users.
  await Firebase.initializeApp(
    name: 'worker',
    options: firebaseOptions,
  );
  // --- END OF CRITICAL FIX ---

  // 4. Run your app.
  runApp(const ChalOstaadApp());
}

class ChalOstaadApp extends StatelessWidget {
  const ChalOstaadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: CAppTheme.lightTheme,
      darkTheme: CAppTheme.darkTheme,
      themeMode: ThemeMode.system,
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
