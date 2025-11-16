import 'package:chal_ostaad/features/auth/screens/login.dart';
import 'package:chal_ostaad/features/splash/role_selection.dart';
import 'package:chal_ostaad/features/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import '../../features/auth/screens/worker_login.dart';
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
        return MaterialPageRoute(builder: (_) => const WorkerLoginScreen());
      // case AppRoutes.home:
      //   return MaterialPageRoute(builder: (_) => const HomePage());
      // case AppRoutes.profile:
      //   return MaterialPageRoute(builder: (_) => const ProfilePage());
      // case AppRoutes.jobDetails:
      //   return MaterialPageRoute(builder: (_) => const JobDetailsPage());
      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text("No route found")),
          ),
        );
    }
  }
}
