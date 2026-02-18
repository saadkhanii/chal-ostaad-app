import 'package:chal_ostaad/features/auth/screens/login.dart';
import 'package:chal_ostaad/features/splash/role_selection.dart';
import 'package:chal_ostaad/features/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import '../../features/auth/screens/client_signup.dart';
import '../../features/auth/screens/forgot_password.dart';
import '../../features/auth/screens/otp_verification.dart';
import '../../features/auth/screens/worker_signup.dart';
import '../../features/client/client_dashboard.dart';
import '../../features/client/my_posted_jobs_screen.dart';
import '../../features/client/post_job_screen.dart';
import '../../features/worker/find_jobs_screen.dart';
import '../../features/worker/my_bids_screen.dart';
import '../../features/worker/worker_dashboard.dart';
import '../../features/notifications/notification_settings_screen.dart';
import '../../features/notifications/notifications_screen.dart';
// TODO: Import your actual job details, chat, wallet, reviews screens
// import '../../features/job/job_details_screen.dart';
// import '../../features/chat/chat_screen.dart';
// import '../../features/wallet/wallet_screen.dart';
// import '../../features/reviews/reviews_screen.dart';

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

      case AppRoutes.postJob:
        return MaterialPageRoute(builder: (_) => const PostJobScreen());

      case AppRoutes.forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());

      case AppRoutes.myPostedJobs:
        return MaterialPageRoute(builder: (_) => const MyPostedJobsScreen());

      case AppRoutes.findJobs:
        return MaterialPageRoute(builder: (_) => const FindJobsScreen());

      case AppRoutes.myBids:
        return MaterialPageRoute(builder: (_) => const MyBidsScreen());

      case AppRoutes.notifications:
        return MaterialPageRoute(builder: (_) => const NotificationsScreen());

      case AppRoutes.notificationSettings:
        return MaterialPageRoute(builder: (_) => const NotificationSettingsScreen());

    // New routes – replace with actual screens
      case AppRoutes.jobDetails:
        final jobId = settings.arguments as String?;
        // TODO: Replace with your actual JobDetailsScreen
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text('Job Details')),
            body: Center(child: Text('Job ID: $jobId')),
          ),
        ); // removed const

      case AppRoutes.chat:
        final chatId = settings.arguments as String?;
        // TODO: Replace with your actual ChatScreen
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text('Chat')),
            body: Center(child: Text('Chat ID: $chatId')),
          ),
        ); // removed const

      // case AppRoutes.wallet:
      // // TODO: Replace with your actual WalletScreen
      //   return MaterialPageRoute(
      //     builder: (_) => const Scaffold(
      //       appBar: AppBar(title: Text('Wallet')),
      //       body: Center(child: Text('Wallet Screen')),
      //     ),
      //   ); // const is fine because the Scaffold is const
      //
      // case AppRoutes.reviews:
      // // TODO: Replace with your actual ReviewsScreen
      //   return MaterialPageRoute(
      //     builder: (_) => const Scaffold(
      //       appBar: AppBar(title: Text('Reviews')),
      //       body: Center(child: Text('Reviews Screen')),
      //     ),
      //   ); // const is fine

      case AppRoutes.otpVerification:
        if (settings.arguments is Map<String, dynamic>) {
          final args = settings.arguments as Map<String, dynamic>;
          final email = args['email'];
          if (email != null) {
            return MaterialPageRoute(
              builder: (_) => OTPVerificationScreen(email: email),
            );
          }
        }
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Error: Email address is required for OTP screen.')),
          ),
        ); // const Scaffold is okay

      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text("No route found")),
          ),
        ); // const Scaffold is okay
    }
  }
}