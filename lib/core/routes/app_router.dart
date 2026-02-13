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
import '../../features/client/post_job_screen.dart';
import '../../features/worker/worker_dashboard.dart';
import 'app_routes.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());

      case AppRoutes.role:
        return MaterialPageRoute(builder: (_) => const RoleSelection());

      case AppRoutes.login:
      // Just pass the route, Login will read arguments from ModalRoute
        return MaterialPageRoute(
          builder: (_) => const Login(),  // ← No parameters needed
          settings: settings,  // ← Pass settings so arguments are available
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
        // Return an error route if arguments are missing or invalid
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