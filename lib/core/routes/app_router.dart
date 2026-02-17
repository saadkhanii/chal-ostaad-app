// D:/FlutterProjects/chal_ostaad/lib/core/routes/app_router.dart

import 'package:chal_ostaad/features/auth/screens/login.dart';
import 'package:chal_ostaad/features/splash/role_selection.dart';
import 'package:chal_ostaad/features/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import '../../features/auth/screens/client_signup.dart';
import '../../features/auth/screens/forgot_password.dart';
import '../../features/auth/screens/otp_verification.dart';
import '../../features/auth/screens/worker_signup.dart';
import '../../features/client/client_dashboard.dart';
import '../../features/client/my_posted_jobs_screen.dart'; // Add this import
import '../../features/client/post_job_screen.dart';
import '../../features/worker/my_bids_screen.dart';
import '../../features/worker/worker_dashboard.dart';

// 🔔 Import Notification Screens
import '../../features/notifications/notification_settings_screen.dart';
import '../../features/notifications/notifications_screen.dart';

import 'app_routes.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());

      case AppRoutes.role:
        return MaterialPageRoute(builder: (_) => const RoleSelection());

      case AppRoutes.login:
        return MaterialPageRoute(
          builder: (_) => const Login(),
          settings: settings,
        );

      case AppRoutes.workerLogin:
        return MaterialPageRoute(builder: (_) => const WorkerSignUpScreen());

      case AppRoutes.clientSignUp:
        return MaterialPageRoute(builder: (_) => const ClientSignUpScreen());

      case AppRoutes.clientDashboard:
        return MaterialPageRoute(builder: (_) => const ClientDashboard());

      case AppRoutes.workerDashboard:
        return MaterialPageRoute(builder: (_) => const WorkerDashboard());

      case AppRoutes.postJob:
        return MaterialPageRoute(builder: (_) => const PostJobScreen());

      case AppRoutes.forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());

      case AppRoutes.myPostedJobs: // New route
        return MaterialPageRoute(builder: (_) => const MyPostedJobsScreen());

      case AppRoutes.myBids:
        return MaterialPageRoute(builder: (_) => const MyBidsScreen());

    // 🔔 Notification Routes
      case AppRoutes.notifications:
        return MaterialPageRoute(builder: (_) => const NotificationsScreen());

      case AppRoutes.notificationSettings:
        return MaterialPageRoute(builder: (_) => const NotificationSettingsScreen());

    // --- OTP ROUTE LOGIC ---
      case AppRoutes.otpVerification:
        if (settings.arguments is Map<String, dynamic>) {
          final args = settings.arguments as Map<String, dynamic>;
          final email = args['email'];

          if (email != null) {
            return MaterialPageRoute(
              builder: (_) => OTPVerificationScreen(
                email: email,
              ),
            );
          }
        }
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(
              child: Text('Error: Email address is required for OTP screen.'),
            ),
          ),
        );

      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text("No route found")),
          ),
        );
    }
  }
}