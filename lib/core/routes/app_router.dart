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
      case AppRoutes.clientSignUp:
        return MaterialPageRoute(builder: (_) => const ClientSignUpScreen());
      case AppRoutes.clientDashboard:
        return MaterialPageRoute(builder: (_) => const ClientDashboard());
      case AppRoutes.workerDashboard:
        return MaterialPageRoute(builder: (_) => const WorkerDashboard());
      case AppRoutes.forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());
      case AppRoutes.otpVerification:
        return MaterialPageRoute(builder: (_) => const OTPVerificationScreen());
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
