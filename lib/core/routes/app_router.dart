import 'package:chal_ostaad/features/auth/screens/login.dart';
import 'package:chal_ostaad/features/splash/role_selection.dart';
import 'package:chal_ostaad/features/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import '../../features/auth/screens/client_signup.dart';
import '../../features/auth/screens/forgot_password.dart';
import '../../features/auth/screens/otp_verification.dart';
import '../../features/auth/screens/set_password.dart';
import '../../features/auth/screens/worker_signup.dart';
import '../../features/client/client_dashboard.dart';
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
        return MaterialPageRoute(builder: (_) => const Login());
      case AppRoutes.workerLogin:
        return MaterialPageRoute(builder: (_) => const WorkerSignUpScreen());
      case AppRoutes.clientSignUp:
        return MaterialPageRoute(builder: (_) => const ClientSignUpScreen());
      case AppRoutes.clientDashboard:
        return MaterialPageRoute(builder: (_) => const ClientDashboard());
      case AppRoutes.workerDashboard:
        return MaterialPageRoute(builder: (_) => const WorkerDashboard());
      case AppRoutes.forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());
      case AppRoutes.setPassword:
        return MaterialPageRoute(builder: (_) => const SetPasswordScreen());

    // --- Start of Change ---
      case AppRoutes.otpVerification:
      // 1. Check if arguments are provided and are of the correct type (String)
        if (settings.arguments is String) {
          final phoneNumber = settings.arguments as String;
          // 2. Pass the extracted phone number to the screen
          return MaterialPageRoute(
            builder: (_) => OTPVerificationScreen(phoneNumber: phoneNumber),
          );
        }
        // 3. Return an error route if arguments are missing or wrong
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(
              child: Text('Error: Phone number is required for OTP screen.'),
            ),
          ),
        );
    // --- End of Change ---

      case AppRoutes.setPassword:
        return MaterialPageRoute(builder: (_) => const SetPasswordScreen());

      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text("No route found")),
          ),
        );
    }
  }
}
