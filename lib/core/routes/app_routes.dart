class AppRoutes {
  static const String splash               = '/';
  static const String role                 = '/role';
  static const String login                = '/login';
  static const String workerLogin          = '/worker-signup';
  static const String clientSignUp         = '/client-signup';
  static const String clientDashboard      = '/client-dashboard';
  static const String workerDashboard      = '/worker-dashboard';
  static const String forgotPassword       = '/forgot-password';
  static const String otpVerification      = '/otp-verification';
  static const String postJob              = '/post-job';
  static const String myPostedJobs         = '/my-posted-jobs';
  static const String myBids               = '/my-bids';
  static const String notifications        = '/notifications';
  static const String notificationSettings = '/notification-settings';
  static const String findJobs             = '/find-jobs';
  static const String jobsMap              = '/jobs-map'; // ← NEW
  static const String clientProfile        = '/client-profile';
  static const String workerProfile        = '/worker-profile';

  // Notification navigation routes
  static const String jobDetails      = '/job-details';
  static const String chat            = '/chat';
  static const String chatInbox       = '/chat-inbox';
  static const String workerChatInbox = '/worker-chat-inbox';

  // ── Payment routes ───────────────────────────────────────────────
  static const String payment        = '/payment';
  static const String paymentSuccess = '/payment-success';
  static const String wallet         = '/wallet';
  // ─────────────────────────────────────────────────────────────────
  static const String reviews             = '/reviews';
  static const String workerBidProfile    = '/worker-bid-profile';
  static const String workerReviews       = '/worker-reviews';
  static const String disputes            = '/disputes';

  // ── Settings & Support routes ────────────────────────────────────
  static const String settings            = '/settings';
  static const String helpSupport         = '/help-support';
  static const String about               = '/about';
  static const String transactionHistory  = '/transaction-history';
  // ─────────────────────────────────────────────────────────────────

  @Deprecated('Use myPostedJobs instead')
  static const String myJobs = '/my-jobs';
}