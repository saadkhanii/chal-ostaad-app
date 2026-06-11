// lib/features/client/client_dashboard.dart

import 'package:chal_ostaad/features/client/client_job_details_screen.dart';
import 'package:chal_ostaad/features/client/post_job_screen.dart';
import 'package:chal_ostaad/features/notifications/notifications_screen.dart';
import 'package:chal_ostaad/features/chat/client_chat_inbox_screen.dart';
import 'package:chal_ostaad/features/client/my_posted_jobs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/job_model.dart';
import '../../core/models/payment_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/job_service.dart';
import '../../core/services/payment_service.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/dashboard_drawer.dart';
import '../../shared/widgets/curved_nav_bar.dart';
import '../profile/client_profile_screen.dart';
import 'client_dashboard_header.dart';
import '../dispute/dispute_status_banner.dart';
import '../../core/models/dispute_model.dart';
import '../../core/services/dispute_service.dart';

final clientLoadingProvider = StateProvider<bool>((ref) => true);
final clientPageIndexProvider = StateProvider<int>((ref) => 2);

class ClientDashboard extends ConsumerStatefulWidget {
  const ClientDashboard({super.key});

  @override
  ConsumerState<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends ConsumerState<ClientDashboard>
    with TickerProviderStateMixin {
  String _userName = '';
  String _clientId = '';
  String _clientEmail = '';
  String _photoBase64 = '';

  Future<Map<String, dynamic>>? _clientStatsFuture;

  List<String> _morningQuotes = [];
  List<String> _afternoonQuotes = [];
  List<String> _eveningQuotes = [];

  final ScrollController _myPostedJobsScrollController = ScrollController();
  final ScrollController _postJobScrollController = ScrollController();
  final ScrollController _homeScrollController = ScrollController();
  final ScrollController _chatScrollController = ScrollController();
  final ScrollController _profileScrollController = ScrollController();

  final JobService _jobService = JobService();
  final BidService _bidService = BidService();
  final PaymentService _paymentService = PaymentService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // ── Lifecycle ─────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeIn));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _userName = 'dashboard.client'.tr();
        _morningQuotes = [
          'quote.morning_1'.tr(),
          'quote.morning_2'.tr(),
          'quote.morning_3'.tr()
        ];
        _afternoonQuotes = [
          'quote.afternoon_1'.tr(),
          'quote.afternoon_2'.tr(),
          'quote.afternoon_3'.tr()
        ];
        _eveningQuotes = [
          'quote.evening_1'.tr(),
          'quote.evening_2'.tr(),
          'quote.evening_3'.tr()
        ];
      });
      _loadUserData();
      _animationController.forward();
    });
  }

  @override
  void dispose() {
    _myPostedJobsScrollController.dispose();
    _postJobScrollController.dispose();
    _homeScrollController.dispose();
    _chatScrollController.dispose();
    _profileScrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userUid = prefs.getString('user_uid');
      String? userName = prefs.getString('user_name');
      String? userEmail = prefs.getString('user_email');

      if (userUid != null) {
        try {
          final userDoc =
              await _firestore.collection('users').doc(userUid).get();
          if (userDoc.exists && userDoc.data() != null) {
            final data = userDoc.data()!;
            final fetchedName = data['fullName'] ??
                data['name'] ??
                data['userName'] ??
                userName ??
                'dashboard.client'.tr();
            final fetchedEmail = data['email'] ?? userEmail ?? '';
            userName = fetchedName;
            userEmail = fetchedEmail;
            await prefs.setString('user_name', fetchedName);
            await prefs.setString('user_email', fetchedEmail);
          }
        } catch (e) {
          debugPrint('Error fetching user data: $e');
        }

        String photoBase64 = '';
        try {
          final clientDoc =
              await _firestore.collection('clients').doc(userUid).get();
          if (clientDoc.exists) {
            final info =
                clientDoc.data()?['personalInfo'] as Map<String, dynamic>? ??
                    {};
            photoBase64 = info['photoBase64'] ?? '';
          }
        } catch (e) {
          debugPrint('Error fetching photoBase64: $e');
        }

        if (mounted) {
          setState(() {
            _clientId = userUid;
            _userName = userName ?? 'dashboard.client'.tr();
            _clientEmail = userEmail ?? '';
            _photoBase64 = photoBase64;
            _clientStatsFuture = _fetchClientStats();
          });
          ref.read(clientLoadingProvider.notifier).state = false;
        }
      } else {
        if (mounted) ref.read(clientLoadingProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error loading client data: $e');
      if (mounted) ref.read(clientLoadingProvider.notifier).state = false;
    }
  }

  // ── Stats — now reads real payments ──────────────────────────────

  Future<Map<String, dynamic>> _fetchClientStats() async {
    if (_clientId.isEmpty) {
      return {
        'postedJobs': 0,
        'activeJobs': 0,
        'completedJobs': 0,
        'cancelledJobs': 0,
        'totalSpent': 0.0,
        'stripeSpent': 0.0,
        'cashSpent': 0.0,
        'platformFees': 0.0,
        'pendingPayments': 0.0,
        'thisMonthSpent': 0.0,
        'openBids': 0,
      };
    }
    try {
      // Jobs
      final jobsSnap = await _firestore
          .collection('jobs')
          .where('clientId', isEqualTo: _clientId)
          .get();
      final jobs = jobsSnap.docs;
      final total = jobs.length;
      final active = jobs.where((d) => d['status'] == 'in-progress').length;
      final completed = jobs.where((d) => d['status'] == 'completed').length;
      final cancelled = jobs.where((d) => d['status'] == 'cancelled').length;

      // Open bids across all jobs
      final jobIds = jobs.map((d) => d.id).toList();
      int openBids = 0;
      if (jobIds.isNotEmpty) {
        for (int i = 0; i < jobIds.length; i += 10) {
          final chunk = jobIds.sublist(
              i, i + 10 > jobIds.length ? jobIds.length : i + 10);
          final bidSnap = await _firestore
              .collection('bids')
              .where('jobId', whereIn: chunk)
              .where('status', isEqualTo: 'pending')
              .get();
          openBids += bidSnap.docs.length;
        }
      }

      // Real payment data
      final paymentsSnap = await _firestore
          .collection('payments')
          .where('clientId', isEqualTo: _clientId)
          .get();
      final payments = paymentsSnap.docs
          .map((d) => PaymentModel.fromSnapshot(
              d as DocumentSnapshot<Map<String, dynamic>>))
          .toList();

      final paid = payments.where((p) => p.status == 'completed').toList();
      final pending =
          payments.where((p) => p.status == 'pending' && p.isCash).toList();

      double totalSpent = paid.fold(0.0, (s, p) => s + p.amount) +
          pending.fold(0.0, (s, p) => s + p.amount);
      double stripeSpent =
          paid.where((p) => p.isStripe).fold(0.0, (s, p) => s + p.amount);
      double cashSpent =
          paid.where((p) => p.isCash).fold(0.0, (s, p) => s + p.amount);
      double pendingAmt = pending.fold(0.0, (s, p) => s + p.amount);

      // Platform fees paid
      double platformFees = 0;
      for (final p in paid) {
        final snap = await _firestore.collection('payments').doc(p.id).get();
        final fee = (snap.data()?['platformFee'] as num?)?.toDouble() ??
            PaymentService.calcPlatformFee(p.amount);
        platformFees += fee;
      }

      // This month
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      double thisMonth = paid
          .where((p) =>
              p.completedAt != null &&
              p.completedAt!.toDate().isAfter(monthStart))
          .fold(0, (s, p) => s + p.amount);

      return {
        'postedJobs': total,
        'activeJobs': active,
        'completedJobs': completed,
        'cancelledJobs': cancelled,
        'totalSpent': totalSpent,
        'stripeSpent': stripeSpent,
        'cashSpent': cashSpent,
        'platformFees': platformFees,
        'pendingPayments': pendingAmt,
        'thisMonthSpent': thisMonth,
        'openBids': openBids,
      };
    } catch (e) {
      debugPrint('Error fetching client stats: $e');
      return {
        'postedJobs': 0,
        'activeJobs': 0,
        'completedJobs': 0,
        'cancelledJobs': 0,
        'totalSpent': 0.0,
        'stripeSpent': 0.0,
        'cashSpent': 0.0,
        'platformFees': 0.0,
        'pendingPayments': 0.0,
        'thisMonthSpent': 0.0,
        'openBids': 0,
      };
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  void _showJobDetails(JobModel job) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => ClientJobDetailsScreen(job: job)));
  }

  String _getGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _getMotivationalQuote() {
    final h = DateTime.now().hour;
    final r = DateTime.now().millisecond % 3;
    if (h < 12) return _morningQuotes.isNotEmpty ? _morningQuotes[r] : '';
    if (h < 17) return _afternoonQuotes.isNotEmpty ? _afternoonQuotes[r] : '';
    return _eveningQuotes.isNotEmpty ? _eveningQuotes[r] : '';
  }

  String _formatCurrency(double amount) {
    if (amount == 0) return 'Rs 0';
    if (amount >= 10000000)
      return 'Rs ${(amount / 10000000).toStringAsFixed(1)}Cr';
    if (amount >= 100000) return 'Rs ${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return 'Rs ${(amount / 1000).toStringAsFixed(1)}k';
    return 'Rs ${amount.toStringAsFixed(0)}';
  }

  // ── Pages list ────────────────────────────────────────────────────

  List<Widget> _getPages() {
    return [
      MyPostedJobsScreen(scrollController: _myPostedJobsScrollController),
      PostJobScreen(
        showAppBar: false,
        onJobPosted: () {
          // Go to My Posted Jobs tab (index 0)
          ref.read(clientPageIndexProvider.notifier).state = 0;
        },
      ),
      _buildHomePage(),
      ChatInboxScreen(
          scrollController: _chatScrollController, showAppBar: false),
      ClientProfileScreen(showAppBar: false),
    ];
  }

  // ── Home page ─────────────────────────────────────────────────────

  Widget _buildHomePage() {
    final isLoading = ref.watch(clientLoadingProvider);
    if (isLoading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _loadUserData,
      child: CustomScrollView(
        controller: _homeScrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ClientDashboardHeader(
                userName: _userName,
                photoUrl: _photoBase64,
                onNotificationTap: () =>
                    Navigator.pushNamed(context, AppRoutes.notifications),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                CSizes.defaultSpace, 16, CSizes.defaultSpace, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Hero spending banner ───────────────────────
                _buildSpendingBanner(context),
                const SizedBox(height: 16),

                // ── 4-stat row ─────────────────────────────────
                _buildStatsRow(context),
                const SizedBox(height: 20),

                // ── Spending breakdown ─────────────────────────
                _buildSectionLabel(context, 'Payment & Spending'),
                const SizedBox(height: 10),
                _buildSpendingCard(context),
                const SizedBox(height: 20),

                // ── Job distribution chart ─────────────────────
                _buildSectionLabel(context, 'Job Distribution'),
                const SizedBox(height: 10),
                _buildJobDistributionChart(context),
                const SizedBox(height: 20),

                // ── Recent payments ────────────────────────────
                _buildSectionLabel(context, 'Recent Payments'),
                const SizedBox(height: 10),
                _buildRecentPayments(context),
                const SizedBox(height: 20),

                // ── My jobs feed ───────────────────────────────
                _buildSectionLabelWithAction(
                    context,
                    'bid.recent_jobs'.tr(),
                    'common.view_all'.tr(),
                    () => ref.read(clientPageIndexProvider.notifier).state = 0),
                const SizedBox(height: 10),
                _buildJobFeed(limit: 3),
                const SizedBox(height: 20),

                // ── Disputes ───────────────────────────────────
                _buildDisputesSection(context),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero spending banner (torn-card design) ──────────────────────

  Widget _buildSpendingBanner(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _clientStatsFuture ??= _fetchClientStats(),
      builder: (context, snap) {
        final s = snap.data ?? {};
        final total = (s['totalSpent'] as double?) ?? 0;
        final monthly = (s['thisMonthSpent'] as double?) ?? 0;
        final active = s['activeJobs'] as int? ?? 0;
        final loading = snap.connectionState == ConnectionState.waiting;

        return _TornCard(
          height: 168,
          leftChild: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${_getGreeting()}, ${_userName.split(' ').first}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w400),
                ),
                const SizedBox(height: 4),
                Text(
                  loading ? '—' : _formatCurrency(total),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  'Total Spent this month: ${_formatCurrency(monthly)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () =>
                      ref.read(clientPageIndexProvider.notifier).state = 1,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('Post Job',
                        style: TextStyle(
                            color: CColors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          rightChild: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                bottom: 0,
                right: -140,
                left: 100,
                child: Image.asset(
                  'assets/images/Business-merger-amico-W.png',
                  height: 145,
                  fit: BoxFit.contain,
                ),
              ),
              Positioned(
                top: 12,
                right: 70,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                      color: CColors.secondary.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.autorenew_rounded,
                        color: Colors.amber, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      loading ? '…' : '$active active',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 4-stat compact row ────────────────────────────────────────────

  Widget _buildStatsRow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<Map<String, dynamic>>(
      future: _clientStatsFuture ??= _fetchClientStats(),
      builder: (context, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final s = snap.data ?? {};
        final items = [
          {
            'label': 'Posted',
            'value': loading ? '…' : '${s['postedJobs'] ?? 0}',
            'icon': Icons.work_outline,
            'color': CColors.primary
          },
          {
            'label': 'Active',
            'value': loading ? '…' : '${s['activeJobs'] ?? 0}',
            'icon': Icons.autorenew_rounded,
            'color': CColors.warning
          },
          {
            'label': 'Done',
            'value': loading ? '…' : '${s['completedJobs'] ?? 0}',
            'icon': Icons.check_circle_rounded,
            'color': CColors.success
          },
          {
            'label': 'Bids',
            'value': loading ? '…' : '${s['openBids'] ?? 0}',
            'icon': Icons.gavel_rounded,
            'color': CColors.info
          },
        ];
        return Row(
          children: items
              .map((item) => Expanded(
                      child: _miniStatCard(
                    context,
                    isDark,
                    label: item['label'] as String,
                    value: item['value'] as String,
                    icon: item['icon'] as IconData,
                    color: item['color'] as Color,
                  )))
              .toList(),
        );
      },
    );
  }

  Widget _miniStatCard(
    BuildContext context,
    bool isDark, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      bodyPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      elevation: isDark ? 0 : 2,
      body: Column(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: isDark ? Colors.white : CColors.textPrimary)),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.grey[400] : Colors.grey[600])),
      ]),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(title,
        style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? CColors.textWhite : CColors.textPrimary,
            letterSpacing: -0.2));
  }

  Widget _buildSectionLabelWithAction(
      BuildContext context, String title, String action, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(title,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? CColors.textWhite : CColors.textPrimary,
              letterSpacing: -0.2)),
      GestureDetector(
        onTap: onTap,
        child: Text(action,
            style: const TextStyle(
                fontSize: 13,
                color: CColors.primary,
                fontWeight: FontWeight.w600)),
      ),
    ]);
  }

  // ── Spending card ─────────────────────────────────────────────────

  Widget _buildSpendingCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<Map<String, dynamic>>(
      future: _clientStatsFuture ??= _fetchClientStats(),
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;
        final s = snap.data ?? {};

        final stripe = (s['stripeSpent'] as double?) ?? 0;
        final cash = (s['cashSpent'] as double?) ?? 0;
        final fees = (s['platformFees'] as double?) ?? 0;
        final pending = (s['pendingPayments'] as double?) ?? 0;

        if (isLoading) {
          return const SizedBox(
              height: 80, child: Center(child: CircularProgressIndicator()));
        }

        return AppCard(
          elevation: isDark ? 0 : 2,
          margin: EdgeInsets.zero,
          bodyPadding: const EdgeInsets.all(16),
          body: Column(children: [
            _spendRow(context, isDark,
                icon: Icons.credit_card_rounded,
                color: CColors.primary,
                label: 'Online (Stripe)',
                value: _formatCurrency(stripe)),
            _divider(isDark),
            _spendRow(context, isDark,
                icon: Icons.payments_outlined,
                color: CColors.success,
                label: 'Cash Payments',
                value: _formatCurrency(cash)),
            _divider(isDark),
            _spendRow(context, isDark,
                icon: Icons.storefront_rounded,
                color: CColors.darkGrey,
                label: 'Platform Fees',
                value: _formatCurrency(fees)),
            if (pending > 0) ...[
              _divider(isDark),
              _spendRow(context, isDark,
                  icon: Icons.hourglass_top_rounded,
                  color: CColors.warning,
                  label: 'Pending Cash',
                  value: _formatCurrency(pending),
                  highlight: true),
            ],
          ]),
        );
      },
    );
  }

  Widget _spendRow(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? CColors.textWhite.withValues(alpha: 0.8)
                        : CColors.textPrimary))),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: highlight
                    ? CColors.warning
                    : (isDark ? CColors.textWhite : CColors.textPrimary))),
      ]),
    );
  }

  Widget _divider(bool isDark) => Divider(
      height: 1, color: isDark ? CColors.darkerGrey : CColors.borderPrimary);

  // ── Recent payments ───────────────────────────────────────────────

  Widget _buildRecentPayments(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_clientId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<List<PaymentModel>>(
      stream: _paymentService.streamPaymentsByClient(_clientId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ));
        }

        final payments = snap.data ?? [];
        if (payments.isEmpty) {
          return AppCard(
            margin: EdgeInsets.zero,
            elevation: 0,
            bodyPadding: const EdgeInsets.all(CSizes.lg),
            body: Center(
                child: Column(children: [
              Icon(Icons.receipt_long_outlined, size: 40, color: CColors.grey),
              const SizedBox(height: 8),
              const Text('No payments yet',
                  style: TextStyle(color: CColors.darkGrey)),
            ])),
          );
        }

        return Column(
          children: payments
              .take(5)
              .map((p) => _buildPaymentTile(p, isDark))
              .toList(),
        );
      },
    );
  }

  Widget _buildPaymentTile(PaymentModel p, bool isDark) {
    final isCompleted = p.status == 'completed';
    final color = isCompleted
        ? (p.isCash ? CColors.success : CColors.primary)
        : CColors.warning;
    final icon = p.isCash ? Icons.payments_outlined : Icons.credit_card_rounded;

    return AppCard(
      margin: const EdgeInsets.only(bottom: CSizes.sm),
      elevation: isDark ? 0 : 1,
      bodyPadding: const EdgeInsets.all(CSizes.md),
      cardBackgroundColor: isDark ? CColors.darkContainer : Colors.white,
      borderRadius: BorderRadius.all(Radius.circular(CSizes.cardRadiusMd)),
      body: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.jobTitle,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Row(children: [
              _pill(p.methodDisplayName, color),
              const SizedBox(width: 6),
              _pill(p.statusDisplayName,
                  isCompleted ? CColors.success : CColors.warning),
            ]),
          ],
        )),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_formatCurrency(p.amount),
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isCompleted ? color : CColors.warning)),
          if (p.createdAt != null)
            Text(timeago.format(p.createdAt!.toDate()),
                style: const TextStyle(fontSize: 10, color: CColors.darkGrey)),
        ]),
      ]),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  // ── Stats grid (removed, replaced by _buildStatsRow inline) ─────

  // ── Job distribution chart (existing, kept) ────────────────────

  Widget _buildJobDistributionChart(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _clientStatsFuture ??= _fetchClientStats(),
      builder: (context, snapshot) {
        final open = (snapshot.data?['postedJobs'] as int? ?? 0) -
            (snapshot.data?['activeJobs'] as int? ?? 0) -
            (snapshot.data?['completedJobs'] as int? ?? 0);
        final inProgress = snapshot.data?['activeJobs'] as int? ?? 0;
        final completed = snapshot.data?['completedJobs'] as int? ?? 0;
        final total = open + inProgress + completed;

        if (total == 0) return _buildEmptyChart(context);

        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AppCard(
            elevation: isDark ? 0 : 2,
            margin: EdgeInsets.zero,
            bodyPadding: const EdgeInsets.all(CSizes.md),
            body: SizedBox(
              height: 140,
              child: Row(children: [
                Expanded(
                  flex: 2,
                  child: PieChart(PieChartData(
                    sections: [
                      PieChartSectionData(
                        value: open.toDouble(),
                        color: CColors.primary,
                        title: '${((open / total) * 100).toStringAsFixed(0)}%',
                        radius: 40,
                        titleStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                      PieChartSectionData(
                        value: inProgress.toDouble(),
                        color: CColors.warning,
                        title:
                            '${((inProgress / total) * 100).toStringAsFixed(0)}%',
                        radius: 40,
                        titleStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                      PieChartSectionData(
                        value: completed.toDouble(),
                        color: CColors.success,
                        title:
                            '${((completed / total) * 100).toStringAsFixed(0)}%',
                        radius: 40,
                        titleStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                    sectionsSpace: 2,
                    centerSpaceRadius: 30,
                  )),
                ),
                Expanded(
                  flex: 1,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _legendItem(context, 'Open', open, CColors.primary),
                      const SizedBox(height: 8),
                      _legendItem(
                          context, 'In Progress', inProgress, CColors.warning),
                      const SizedBox(height: 8),
                      _legendItem(
                          context, 'Completed', completed, CColors.success),
                    ],
                  ),
                ),
              ]),
            )
        );
      },
    );
  }

  Widget _legendItem(
      BuildContext context, String label, int count, Color color) {
    return Row(children: [
      Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text('$label ($count)', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _buildEmptyChart(BuildContext context) {
    return AppCard(
      elevation: 0,
      margin: EdgeInsets.zero,
      bodyPadding: const EdgeInsets.all(CSizes.md),
      body: SizedBox(
        height: 130,
        child: Center(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pie_chart_outline, size: 40, color: CColors.grey),
            const SizedBox(height: 8),
            Text('No job data yet',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: CColors.grey)),
          ],
        )),
      ),
    );
  }

  Widget _buildJobFeed({int? limit}) {
    if (_clientId.isEmpty) return _buildEmptyState('job.login_to_view'.tr());

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('jobs')
          .where('clientId', isEqualTo: _clientId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return _buildLoadingJobs();
        if (snapshot.hasError)
          return _buildEmptyState(
              '${'errors.load_jobs_failed'.tr()}: ${snapshot.error}');
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return _buildEmptyState('job.no_jobs_found'.tr());

        int count = snapshot.data!.docs.length;
        if (limit != null && limit < count) count = limit;

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            return _buildJobCard(
                JobModel.fromMap(doc.data() as Map<String, dynamic>, doc.id));
          },
        );
      },
    );
  }

  Widget _buildJobCard(JobModel job) {
    final isUrdu = context.locale.languageCode == 'ur';
    Color statusColor;
    String statusText;
    switch (job.status) {
      case 'open':
        statusColor = CColors.success;
        statusText = 'job.status_open'.tr();
        break;
      case 'in-progress':
        statusColor = CColors.warning;
        statusText = 'job.status_in_progress'.tr();
        break;
      case 'completed':
        statusColor = CColors.info;
        statusText = 'job.status_completed'.tr();
        break;
      case 'cancelled':
        statusColor = CColors.error;
        statusText = 'job.status_cancelled'.tr();
        break;
      default:
        statusColor = CColors.grey;
        statusText = job.status;
    }
    return AppCard(
      margin: const EdgeInsets.only(bottom: CSizes.md),
      elevation: 2,
      onTap: () => _showJobDetails(job),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(job.title,
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      fontWeight: FontWeight.bold, fontSize: isUrdu ? 18 : 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor)),
            child: Text(statusText,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: isUrdu ? 12 : 10)),
          ),
        ]),
        const SizedBox(height: CSizes.sm),
        Text(job.description,
            style: Theme.of(context)
                .textTheme
                .bodyMedium!
                .copyWith(fontSize: isUrdu ? 16 : 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: CSizes.md),
        Row(children: [
          Icon(Icons.access_time, size: 16, color: CColors.darkGrey),
          const SizedBox(width: 4),
          Text(timeago.format(job.createdAt.toDate()),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall!
                  .copyWith(fontSize: isUrdu ? 14 : 12)),
          const Spacer(),
          StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('bids')
                .where('jobId', isEqualTo: job.id)
                .snapshots(),
            builder: (context, bidSnap) {
              final count = bidSnap.data?.docs.length ?? 0;
              return Row(children: [
                Icon(Icons.gavel, size: 16, color: CColors.primary),
                const SizedBox(width: 4),
                Text('${'bid.total_bids'.tr()}: $count',
                    style: Theme.of(context).textTheme.labelMedium!.copyWith(
                        color: CColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: isUrdu ? 14 : 12)),
              ]);
            },
          ),
        ]),
      ]),
    );
  }

  // ── Disputes section ──────────────────────────────────────────────

  Widget _buildDisputesSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return StreamBuilder<List<DisputeModel>>(
      stream: DisputeService()
          .userDisputesStream(userId: _clientId, role: 'client'),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
        final disputes = snap.data!.where((d) => d.status != 'closed').toList();
        if (disputes.isEmpty) return const SizedBox.shrink();
        final openCount = disputes.where((d) => d.isActive).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _buildSectionLabel(context, 'My Disputes'),
            if (openCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: CColors.error,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('$openCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
          const SizedBox(height: CSizes.spaceBtwItems),
          ...disputes
              .take(3)
              .map((d) => _buildDisputeCard(context, d, isDark, isUrdu)),
        ]);
      },
    );
  }

  Widget _buildDisputeCard(
      BuildContext context, DisputeModel dispute, bool isDark, bool isUrdu) {
    Color statusColor;
    IconData statusIcon;
    switch (dispute.status) {
      case 'reviewing':
        statusColor = CColors.warning;
        statusIcon = Icons.manage_search_rounded;
        break;
      case 'resolved':
        statusColor = CColors.success;
        statusIcon = Icons.gavel_rounded;
        break;
      default:
        statusColor = CColors.error;
        statusIcon = Icons.flag_rounded;
    }
    return AppCard(
      margin: const EdgeInsets.only(bottom: CSizes.sm),
      elevation: isDark ? 0 : 1,
      onTap: () => Navigator.pushNamed(context, AppRoutes.disputes,
          arguments: dispute.jobId),
      body: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(statusIcon, color: statusColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dispute.jobTitle,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isUrdu ? 14 : 13,
                    color: isDark ? CColors.textWhite : CColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(dispute.reason,
                style: TextStyle(
                    fontSize: isUrdu ? 12 : 11, color: CColors.darkGrey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        )),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20)),
          child: Text(dispute.status.toUpperCase(),
              style: TextStyle(
                  color: statusColor,
                  fontSize: isUrdu ? 10 : 9,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, color: CColors.darkGrey, size: 16),
      ]),
    );
  }

  // ── Loading / empty states ────────────────────────────────────────

  Widget _buildLoadingJobs() => SizedBox(
      height: 150,
      child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: CColors.primary),
        const SizedBox(height: CSizes.md),
        Text('common.loading_jobs'.tr()),
      ])));

  Widget _buildEmptyState(String message) => Container(
      height: 150,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? CColors.darkContainer
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.work_outline, size: 48, color: CColors.grey),
        const SizedBox(height: CSizes.md),
        Text(message,
            style: Theme.of(context)
                .textTheme
                .bodyMedium!
                .copyWith(color: CColors.textSecondary),
            textAlign: TextAlign.center),
      ])));

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    final currentPageIndex = ref.watch(clientPageIndexProvider);

    ScrollController activeController;
    switch (currentPageIndex) {
      case 0:
        activeController = _myPostedJobsScrollController;
        break;
      case 1:
        activeController = _postJobScrollController;
        break;
      case 2:
        activeController = _homeScrollController;
        break;
      case 3:
        activeController = _chatScrollController;
        break;
      case 4:
        activeController = _profileScrollController;
        break;
      default:
        activeController = _homeScrollController;
    }

    return Scaffold(
      endDrawer: !isUrdu ? const DashboardDrawer() : null,
      drawer: isUrdu ? const DashboardDrawer() : null,
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: IndexedStack(index: currentPageIndex, children: _getPages()),
      bottomNavigationBar: CurvedNavBar(
        currentIndex: currentPageIndex,
        onTap: (index) {
          ref.read(clientPageIndexProvider.notifier).state = index;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            switch (index) {
              case 0:
                if (_myPostedJobsScrollController.hasClients)
                  _myPostedJobsScrollController.jumpTo(0);
                break;
              case 1:
                if (_postJobScrollController.hasClients)
                  _postJobScrollController.jumpTo(0);
                break;
              case 2:
                if (_homeScrollController.hasClients)
                  _homeScrollController.jumpTo(0);
                break;
              case 3:
                if (_chatScrollController.hasClients)
                  _chatScrollController.jumpTo(0);
                break;
              case 4:
                if (_profileScrollController.hasClients)
                  _profileScrollController.jumpTo(0);
                break;
            }
          });
        },
        userRole: 'client',
        scrollController: activeController,
      ),
    );
  }
}

// ── Torn-card widget ──────────────────────────────────────────────────────────
// Shared between client & worker dashboards.
// Left half: dark (#1C1C1C) · Right half: CColors.primary (orange)
// A sharp zigzag CustomClipper creates the torn-paper edge at ~54 % width.

class _TornCard extends StatelessWidget {
  final Widget leftChild;
  final Widget rightChild;
  final double height;

  const _TornCard({
    required this.leftChild,
    required this.rightChild,
    this.height = 168,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            // Orange right panel (full width)
            Positioned.fill(
              child: Container(color: CColors.primary, child: rightChild),
            ),
            // Dark left panel – clipped with the zigzag edge
            Positioned.fill(
              child: ClipPath(
                clipper: _LeftTearClipper(),
                child: Container(
                  color: const Color(0xFF1C1C1C),
                  child: leftChild,
                ),
              ),
            ),
            // ✨ Thin white jagged stroke overlay ✨
            Positioned.fill(
              child: CustomPaint(
                painter: _TearStrokePainter(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a thin white stroke exactly along the zigzag tear edge.
class _TearStrokePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final path = Path();
    final tx = size.width * 0.54;
    const amp = 13.0;

    path.moveTo(tx - amp, 0);
    path.lineTo(tx + amp, size.height * 0.10);
    path.lineTo(tx - amp, size.height * 0.22);
    path.lineTo(tx + amp, size.height * 0.34);
    path.lineTo(tx - amp, size.height * 0.46);
    path.lineTo(tx + amp, size.height * 0.58);
    path.lineTo(tx - amp, size.height * 0.70);
    path.lineTo(tx + amp, size.height * 0.82);
    path.lineTo(tx - amp, size.height * 0.93);
    path.lineTo(tx, size.height);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Clips the dark left panel. The right boundary is a sharp zigzag that
/// mimics a torn-paper edge, matching the reference screenshot.
class _LeftTearClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final tx = size.width * 0.54; // tear centre ~54 % from left
    const amp = 13.0; // zigzag amplitude in logical pixels

    return Path()
      ..moveTo(0, 0)
      ..lineTo(tx - amp, 0)
      ..lineTo(tx + amp, size.height * 0.10)
      ..lineTo(tx - amp, size.height * 0.22)
      ..lineTo(tx + amp, size.height * 0.34)
      ..lineTo(tx - amp, size.height * 0.46)
      ..lineTo(tx + amp, size.height * 0.58)
      ..lineTo(tx - amp, size.height * 0.70)
      ..lineTo(tx + amp, size.height * 0.82)
      ..lineTo(tx - amp, size.height * 0.93)
      ..lineTo(tx, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_LeftTearClipper old) => false;
}
