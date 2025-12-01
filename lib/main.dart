// lib/main.dart

import 'package:chal_ostaad/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chal_ostaad/firebase/firebase_options.dart';
import 'core/routes/app_router.dart';
import 'core/routes/app_routes.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('🚀 ===== APP STARTING =====');
  print('🕐 Time: ${DateTime.now()}');

  // ===== PHASE 1: SHARED PREFERENCES DEBUG =====
  try {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList()..sort();

    print('📊 === SHARED PREFS AT STARTUP ===');
    print('📦 Total keys: ${keys.length}');
    print('🔑 Keys list: $keys');

    // Log all values for debugging
    for (var key in keys) {
      final value = prefs.get(key);
      print('   $key: $value');
    }

    // Track if we're losing data
    final email = prefs.getString('saved_email');
    final passwordExists = prefs.getString('saved_password') != null;
    final rememberMe = prefs.getBool('remember_me');

    print('📊 === CRITICAL VALUES ===');
    print('📧 saved_email: $email');
    print('🔐 saved_password exists: $passwordExists');
    print('💾 remember_me: $rememberMe');
    print('👤 user_role: ${prefs.getString('user_role')}');
    print('🆔 user_uid: ${prefs.getString('user_uid')}');

    // Save startup timestamp
    await prefs.setString('app_start_time', DateTime.now().toIso8601String());

  } catch (e) {
    print('❌ SharedPreferences error: $e');
  }

  // ===== PHASE 2: FIREBASE INITIALIZATION =====
  try {
    print('🔥 === FIREBASE INITIALIZATION ===');

    // 1. Initialize default Firebase app
    print('🔄 Initializing default Firebase app...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Default Firebase app initialized');

    // 2. Initialize 'client' Firebase app (if not already exists)
    print('🔄 Checking/initializing "client" Firebase app...');
    try {
      // Try to get the existing app
      final clientApp = Firebase.app('client');
      print('✅ "client" Firebase app already exists');
      print('   App name: ${clientApp.name}');
    } catch (e) {
      // App doesn't exist, create it
      if (e.toString().contains('no-app')) {
        print('🆕 Creating "client" Firebase app...');
        await Firebase.initializeApp(
          name: 'client',
          options: DefaultFirebaseOptions.currentPlatform,
        );
        print('✅ "client" Firebase app created successfully');
      } else {
        print('⚠️ Unexpected error with "client" app: $e');
      }
    }

    // 3. Initialize 'worker' Firebase app (if not already exists)
    print('🔄 Checking/initializing "worker" Firebase app...');
    try {
      // Try to get the existing app
      final workerApp = Firebase.app('worker');
      print('✅ "worker" Firebase app already exists');
      print('   App name: ${workerApp.name}');
    } catch (e) {
      // App doesn't exist, create it
      if (e.toString().contains('no-app')) {
        print('🆕 Creating "worker" Firebase app...');
        await Firebase.initializeApp(
          name: 'worker',
          options: DefaultFirebaseOptions.currentPlatform,
        );
        print('✅ "worker" Firebase app created successfully');
      } else {
        print('⚠️ Unexpected error with "worker" app: $e');
      }
    }

    print('✅ All Firebase apps initialized successfully');

  } catch (e) {
    print('❌ CRITICAL: Firebase initialization failed: $e');
    print('💡 Check your firebase_options.dart file and Google Services configuration');
  }

  // ===== PHASE 3: VERIFY ALL APPS =====
  try {
    print('🔍 === VERIFYING ALL FIREBASE APPS ===');
    final allApps = Firebase.apps;
    print('📱 Total Firebase apps: ${allApps.length}');

    for (var app in allApps) {
      print('   • App: ${app.name}');
    }

    if (allApps.length < 3) {
      print('⚠️ Warning: Expected 3 apps (default, client, worker) but found ${allApps.length}');
    }

  } catch (e) {
    print('❌ Error verifying Firebase apps: $e');
  }

  // ===== PHASE 4: FINAL CHECK =====
  print('🎯 === APP STARTUP COMPLETE ===');
  print('✅ Flutter binding initialized');
  print('✅ SharedPreferences checked');
  print('✅ Firebase initialized');
  print('🚀 Launching ChalOstaad app...');

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