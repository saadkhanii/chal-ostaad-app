// lib/core/routes/app_routes.dart

class AppRoutes {
  static const String splash = '/';
  static const String role = '/role';
  static const String login = '/login';
  static const String workerLogin = '/worker-signup';
  static const String clientSignUp = '/client-signup';
  static const String clientDashboard = '/client-dashboard';
  static const String workerDashboard = '/worker-dashboard';
  static const String forgotPassword = '/forgot-password';
  static const String otpVerification = '/otp-verification';
  static const String postJob = '/post-job';
  static const String myPostedJobs = '/my-posted-jobs'; // Changed from myJobs
  static const String myBids = '/my-bids';
  static const String notifications = '/notifications';
  static const String notificationSettings = '/notification-settings';

  // You can keep old route for backward compatibility if needed
  @Deprecated('Use myPostedJobs instead')
  static const String myJobs = '/my-jobs';
}