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
import '../../shared/widgets/dashboard_drawer.dart';
import '../../shared/widgets/curved_nav_bar.dart';
import '../profile/client_profile_screen.dart';
import 'client_dashboard_header.dart';
import '../dispute/dispute_status_banner.dart';
import '../../core/models/dispute_model.dart';
import '../../core/services/dispute_service.dart';

final clientLoadingProvider   = StateProvider<bool>((ref) => true);
final clientPageIndexProvider = StateProvider<int>((ref) => 2);

class ClientDashboard extends ConsumerStatefulWidget {
  const ClientDashboard({super.key});

  @override
  ConsumerState<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends ConsumerState<ClientDashboard>
    with TickerProviderStateMixin {

  String _userName     = '';
  String _clientId     = '';
  String _clientEmail  = '';
  String _photoBase64  = '';

  Future<Map<String, dynamic>>? _clientStatsFuture;

  List<String> _morningQuotes   = [];
  List<String> _afternoonQuotes = [];
  List<String> _eveningQuotes   = [];

  final ScrollController _myPostedJobsScrollController = ScrollController();
  final ScrollController _postJobScrollController      = ScrollController();
  final ScrollController _homeScrollController         = ScrollController();
  final ScrollController _chatScrollController         = ScrollController();
  final ScrollController _profileScrollController      = ScrollController();

  final JobService     _jobService     = JobService();
  final BidService     _bidService     = BidService();
  final PaymentService _paymentService = PaymentService();
  final FirebaseFirestore _firestore   = FirebaseFirestore.instance;

  late AnimationController _animationController;
  late Animation<double>   _fadeAnimation;

  // ── Lifecycle ─────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _animationController, curve: Curves.easeIn));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _userName        = 'dashboard.client'.tr();
        _morningQuotes   = ['quote.morning_1'.tr(), 'quote.morning_2'.tr(), 'quote.morning_3'.tr()];
        _afternoonQuotes = ['quote.afternoon_1'.tr(), 'quote.afternoon_2'.tr(), 'quote.afternoon_3'.tr()];
        _eveningQuotes   = ['quote.evening_1'.tr(), 'quote.evening_2'.tr(), 'quote.evening_3'.tr()];
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
      final prefs   = await SharedPreferences.getInstance();
      final userUid = prefs.getString('user_uid');
      String? userName  = prefs.getString('user_name');
      String? userEmail = prefs.getString('user_email');

      if (userUid != null) {
        try {
          final userDoc = await _firestore.collection('users').doc(userUid).get();
          if (userDoc.exists && userDoc.data() != null) {
            final data        = userDoc.data()!;
            final fetchedName = data['fullName'] ?? data['name'] ?? data['userName'] ?? userName ?? 'dashboard.client'.tr();
            final fetchedEmail = data['email'] ?? userEmail ?? '';
            userName  = fetchedName;
            userEmail = fetchedEmail;
            await prefs.setString('user_name',  fetchedName);
            await prefs.setString('user_email', fetchedEmail);
          }
        } catch (e) {
          debugPrint('Error fetching user data: $e');
        }

        String photoBase64 = '';
        try {
          final clientDoc = await _firestore.collection('clients').doc(userUid).get();
          if (clientDoc.exists) {
            final info  = clientDoc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
            photoBase64 = info['photoBase64'] ?? '';
          }
        } catch (e) {
          debugPrint('Error fetching photoBase64: $e');
        }

        if (mounted) {
          setState(() {
            _clientId    = userUid;
            _userName    = userName  ?? 'dashboard.client'.tr();
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
        'postedJobs': 0, 'activeJobs': 0, 'completedJobs': 0,
        'cancelledJobs': 0, 'totalSpent': 0.0, 'stripeSpent': 0.0,
        'cashSpent': 0.0, 'platformFees': 0.0, 'pendingPayments': 0.0,
        'thisMonthSpent': 0.0, 'openBids': 0,
      };
    }
    try {
      // Jobs
      final jobsSnap = await _firestore
          .collection('jobs').where('clientId', isEqualTo: _clientId).get();
      final jobs      = jobsSnap.docs;
      final total     = jobs.length;
      final active    = jobs.where((d) => d['status'] == 'in-progress').length;
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
          .collection('payments').where('clientId', isEqualTo: _clientId).get();
      final payments = paymentsSnap.docs
          .map((d) => PaymentModel.fromSnapshot(
          d as DocumentSnapshot<Map<String, dynamic>>))
          .toList();

      final paid    = payments.where((p) => p.status == 'completed').toList();
      final pending = payments.where((p) => p.status == 'pending' && p.isCash).toList();

      double totalSpent    = paid.fold(0.0, (s, p) => s + p.amount)
          + pending.fold(0.0, (s, p) => s + p.amount);
      double stripeSpent   = paid.where((p) => p.isStripe).fold(0.0, (s, p) => s + p.amount);
      double cashSpent     = paid.where((p) => p.isCash).fold(0.0, (s, p) => s + p.amount);
      double pendingAmt    = pending.fold(0.0, (s, p) => s + p.amount);

      // Platform fees paid
      double platformFees = 0;
      for (final p in paid) {
        final snap  = await _firestore.collection('payments').doc(p.id).get();
        final fee   = (snap.data()?['platformFee'] as num?)?.toDouble()
            ?? PaymentService.calcPlatformFee(p.amount);
        platformFees += fee;
      }

      // This month
      final now        = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      double thisMonth = paid
          .where((p) =>
      p.completedAt != null &&
          p.completedAt!.toDate().isAfter(monthStart))
          .fold(0, (s, p) => s + p.amount);

      return {
        'postedJobs':    total,
        'activeJobs':    active,
        'completedJobs': completed,
        'cancelledJobs': cancelled,
        'totalSpent':    totalSpent,
        'stripeSpent':   stripeSpent,
        'cashSpent':     cashSpent,
        'platformFees':  platformFees,
        'pendingPayments': pendingAmt,
        'thisMonthSpent': thisMonth,
        'openBids':      openBids,
      };
    } catch (e) {
      debugPrint('Error fetching client stats: $e');
      return {
        'postedJobs': 0, 'activeJobs': 0, 'completedJobs': 0,
        'cancelledJobs': 0, 'totalSpent': 0.0, 'stripeSpent': 0.0,
        'cashSpent': 0.0, 'platformFees': 0.0, 'pendingPayments': 0.0,
        'thisMonthSpent': 0.0, 'openBids': 0,
      };
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  void _showJobDetails(JobModel job) {
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => ClientJobDetailsScreen(job: job)));
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
    if (h < 12) return _morningQuotes.isNotEmpty   ? _morningQuotes[r]   : '';
    if (h < 17) return _afternoonQuotes.isNotEmpty ? _afternoonQuotes[r] : '';
    return _eveningQuotes.isNotEmpty ? _eveningQuotes[r] : '';
  }

  String _formatCurrency(double amount) {
    if (amount == 0)        return 'Rs 0';
    if (amount >= 10000000) return 'Rs ${(amount / 10000000).toStringAsFixed(1)}Cr';
    if (amount >= 100000)   return 'Rs ${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000)     return 'Rs ${(amount / 1000).toStringAsFixed(1)}k';
    return 'Rs ${amount.toStringAsFixed(0)}';
  }

  // ── Pages list ────────────────────────────────────────────────────

  List<Widget> _getPages() {
    return [
      MyPostedJobsScreen(scrollController: _myPostedJobsScrollController),
      PostJobScreen(
        showAppBar: false,
        onJobPosted: () {
          ref.read(clientPageIndexProvider.notifier).state = 2;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:         Text('job.job_posted'.tr()),
            backgroundColor: CColors.success,
            duration:        const Duration(seconds: 2),
            behavior:        SnackBarBehavior.floating,
          ));
        },
      ),
      _buildHomePage(),
      ChatInboxScreen(scrollController: _chatScrollController, showAppBar: false),
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
        physics:    const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(children: [
                ClientDashboardHeader(
                  userName:          _userName,
                  photoUrl:          _photoBase64,
                  onNotificationTap: () =>
                      Navigator.pushNamed(context, AppRoutes.notifications),
                ),
                const SizedBox(height: CSizes.spaceBtwSections),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: CSizes.defaultSpace),
                  child: _buildOpportunityCard(context),
                ),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildQuickActions(context),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
                horizontal: CSizes.defaultSpace),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(context,
                    'dashboard.project_overview'.tr(), showAction: false),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildStatsGrid(context),
                const SizedBox(height: CSizes.spaceBtwSections),

                // ── Spending breakdown ──────────────────────────
                _buildSectionHeader(context, 'Payment & Spending',
                    showAction: false),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildSpendingCard(context),
                const SizedBox(height: CSizes.spaceBtwSections),

                // ── Recent payments ─────────────────────────────
                _buildSectionHeader(context, 'Recent Payments',
                    showAction: false),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildRecentPayments(context),
                const SizedBox(height: CSizes.spaceBtwSections),

                _buildSectionHeader(context, 'Job Distribution',
                    showAction: false),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildJobDistributionChart(context),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildRecentActivity(),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSuggestedActions(),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(context, 'bid.recent_jobs'.tr(),
                    actionText: 'common.view_all'.tr(),
                    onAction:   () =>
                    ref.read(clientPageIndexProvider.notifier).state = 0),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildJobFeed(limit: 3),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildDisputesSection(context),
                const SizedBox(height: CSizes.spaceBtwSections * 2),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Spending card ─────────────────────────────────────────────────

  Widget _buildSpendingCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<Map<String, dynamic>>(
      future: _clientStatsFuture ??= _fetchClientStats(),
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;
        final s = snap.data ?? {};

        final total    = (s['totalSpent']      as double?) ?? 0;
        final stripe   = (s['stripeSpent']     as double?) ?? 0;
        final cash     = (s['cashSpent']       as double?) ?? 0;
        final fees     = (s['platformFees']    as double?) ?? 0;
        final pending  = (s['pendingPayments'] as double?) ?? 0;
        final monthly  = (s['thisMonthSpent']  as double?) ?? 0;

        return Container(
          padding:    const EdgeInsets.all(CSizes.lg),
          decoration: BoxDecoration(
            color:        isDark ? CColors.darkContainer : CColors.white,
            borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
            boxShadow: isDark ? [] : [
              BoxShadow(color: Colors.black.withOpacity(0.06),
                  blurRadius: 12, offset: const Offset(0, 4))
            ],
          ),
          child: isLoading
              ? const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child:   CircularProgressIndicator()))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Hero total
            Container(
              width:   double.infinity,
              padding: const EdgeInsets.all(CSizes.md),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [CColors.primary, CColors.primary.withOpacity(0.75)],
                ),
                borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
              ),
              child: Column(children: [
                const Text('Total Amount Spent',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text(_formatCurrency(total),
                    style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   28,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('This month: ${_formatCurrency(monthly)}',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11)),
              ]),
            ),
            const SizedBox(height: CSizes.md),
            _spendRow(context, isDark,
                icon:  Icons.credit_card_rounded,
                color: CColors.primary,
                label: 'Online Payments (Stripe)',
                value: _formatCurrency(stripe)),
            _divider(isDark),
            _spendRow(context, isDark,
                icon:  Icons.payments_outlined,
                color: CColors.success,
                label: 'Cash Payments',
                value: _formatCurrency(cash)),
            _divider(isDark),
            _spendRow(context, isDark,
                icon:  Icons.storefront_rounded,
                color: CColors.darkGrey,
                label: 'Platform Fees Contributed',
                value: _formatCurrency(fees)),
            if (pending > 0) ...[
              _divider(isDark),
              _spendRow(context, isDark,
                  icon:      Icons.hourglass_top_rounded,
                  color:     CColors.warning,
                  label:     'Pending Cash Payments',
                  value:     _formatCurrency(pending),
                  highlight: true),
            ],
          ]),
        );
      },
    );
  }

  Widget _spendRow(BuildContext context, bool isDark, {
    required IconData icon,
    required Color    color,
    required String   label,
    required String   value,
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(
          padding:    const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color:        color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label,
            style: TextStyle(
                fontSize: 13,
                color:    isDark
                    ? CColors.textWhite.withOpacity(0.8)
                    : CColors.textPrimary))),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize:   14,
                color:      highlight ? CColors.warning
                    : (isDark ? CColors.textWhite : CColors.textPrimary))),
      ]),
    );
  }

  Widget _divider(bool isDark) => Divider(height: 1,
      color: isDark ? CColors.darkerGrey : CColors.borderPrimary);

  // ── Recent payments ───────────────────────────────────────────────

  Widget _buildRecentPayments(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_clientId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<List<PaymentModel>>(
      stream: _paymentService.streamPaymentsByClient(_clientId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(16),
            child:   CircularProgressIndicator(),
          ));
        }

        final payments = snap.data ?? [];
        if (payments.isEmpty) {
          return Container(
            padding:    const EdgeInsets.all(CSizes.lg),
            decoration: BoxDecoration(
              color:        isDark ? CColors.darkContainer : CColors.white,
              borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
            ),
            child: Center(child: Column(children: [
              Icon(Icons.receipt_long_outlined,
                  size: 40, color: CColors.grey),
              const SizedBox(height: 8),
              const Text('No payments yet',
                  style: TextStyle(color: CColors.darkGrey)),
            ])),
          );
        }

        return Column(
          children: payments.take(5).map((p) =>
              _buildPaymentTile(p, isDark)).toList(),
        );
      },
    );
  }

  Widget _buildPaymentTile(PaymentModel p, bool isDark) {
    final isCompleted = p.status == 'completed';
    final color = isCompleted
        ? (p.isCash ? CColors.success : CColors.primary)
        : CColors.warning;
    final icon = p.isCash
        ? Icons.payments_outlined
        : Icons.credit_card_rounded;

    return Container(
      margin:     const EdgeInsets.only(bottom: CSizes.sm),
      padding:    const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border:       Border.all(color: color.withOpacity(0.25)),
        boxShadow: isDark ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        Container(
          padding:    const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color:        color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.jobTitle,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  fontSize:   15,
                  color:      isCompleted ? color : CColors.warning)),
          if (p.createdAt != null)
            Text(timeago.format(p.createdAt!.toDate()),
                style: const TextStyle(
                    fontSize: 10, color: CColors.darkGrey)),
        ]),
      ]),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding:    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color:        color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border:       Border.all(color: color.withOpacity(0.3))),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  // ── Stats grid ────────────────────────────────────────────────────

  Widget _buildStatsGrid(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _clientStatsFuture ??= _fetchClientStats(),
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final s = snapshot.data ?? {
          'postedJobs': 0, 'activeJobs': 0, 'completedJobs': 0,
          'thisMonthSpent': 0.0, 'openBids': 0, 'cancelledJobs': 0,
        };

        final items = [
          {'label': 'dashboard.posted_jobs'.tr(),
            'value': isLoading ? '...' : '${s['postedJobs']}',
            'icon':  Icons.work_outline, 'color': CColors.primary},
          {'label': 'dashboard.active_jobs'.tr(),
            'value': isLoading ? '...' : '${s['activeJobs']}',
            'icon':  Icons.autorenew_rounded, 'color': CColors.warning},
          {'label': 'dashboard.completed_jobs'.tr(),
            'value': isLoading ? '...' : '${s['completedJobs']}',
            'icon':  Icons.check_circle, 'color': CColors.success},
          {'label': 'Open Bids',
            'value': isLoading ? '...' : '${s['openBids']}',
            'icon':  Icons.gavel_rounded, 'color': CColors.info},
          {'label': 'This Month',
            'value': isLoading ? '...' : _formatCurrency((s['thisMonthSpent'] as double?) ?? 0),
            'icon':  Icons.calendar_month_rounded, 'color': CColors.primary},
          {'label': 'Cancelled',
            'value': isLoading ? '...' : '${s['cancelledJobs']}',
            'icon':  Icons.cancel_outlined, 'color': CColors.error},
        ];

        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:   2,
            crossAxisSpacing: 12,
            mainAxisSpacing:  12,
            childAspectRatio: 1.4,
          ),
          shrinkWrap: true,
          physics:    const NeverScrollableScrollPhysics(),
          itemCount:  items.length,
          itemBuilder: (context, index) => _buildStatCard(context,
              label: items[index]['label'] as String,
              value: items[index]['value'] as String,
              icon:  items[index]['icon']  as IconData,
              color: items[index]['color'] as Color),
        );
      },
    );
  }

  Widget _buildStatCard(BuildContext context, {
    required String   label,
    required String   value,
    required IconData icon,
    required Color    color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    return Container(
      padding:    const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.08),
              blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            padding:    const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color:        color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 20),
          ),
        ]),
        const Spacer(),
        Text(value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize:   isUrdu ? 24 : 22)),
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey[600])),
      ]),
    );
  }

  // ── Job distribution chart (existing) ────────────────────────────

  Widget _buildJobDistributionChart(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _clientStatsFuture ??= _fetchClientStats(),
      builder: (context, snapshot) {
        final open       = (snapshot.data?['postedJobs']    as int? ?? 0) -
            (snapshot.data?['activeJobs']    as int? ?? 0) -
            (snapshot.data?['completedJobs'] as int? ?? 0);
        final inProgress = snapshot.data?['activeJobs']    as int? ?? 0;
        final completed  = snapshot.data?['completedJobs'] as int? ?? 0;
        final total = open + inProgress + completed;

        if (total == 0) return _buildEmptyChart(context);

        return Container(
          height:     160,
          padding:    const EdgeInsets.all(CSizes.md),
          decoration: BoxDecoration(
            color:        Theme.of(context).brightness == Brightness.dark
                ? CColors.darkContainer : CColors.white,
            borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05),
                  blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(children: [
            Expanded(flex: 2,
              child: PieChart(PieChartData(
                sections: [
                  PieChartSectionData(
                    value: open.toDouble(), color: CColors.primary,
                    title: '${((open / total) * 100).toStringAsFixed(0)}%',
                    radius: 40,
                    titleStyle: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  PieChartSectionData(
                    value: inProgress.toDouble(), color: CColors.warning,
                    title: '${((inProgress / total) * 100).toStringAsFixed(0)}%',
                    radius: 40,
                    titleStyle: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  PieChartSectionData(
                    value: completed.toDouble(), color: CColors.success,
                    title: '${((completed / total) * 100).toStringAsFixed(0)}%',
                    radius: 40,
                    titleStyle: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
                sectionsSpace:     2,
                centerSpaceRadius: 30,
              )),
            ),
            Expanded(flex: 1,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _legendItem(context, 'Open',        open,       CColors.primary),
                  const SizedBox(height: 8),
                  _legendItem(context, 'In Progress', inProgress, CColors.warning),
                  const SizedBox(height: 8),
                  _legendItem(context, 'Completed',   completed,  CColors.success),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _legendItem(BuildContext context, String label, int count, Color color) {
    return Row(children: [
      Container(width: 12, height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text('$label ($count)',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _buildEmptyChart(BuildContext context) {
    return Container(
      height:     160,
      padding:    const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color:        Theme.of(context).brightness == Brightness.dark
            ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
      ),
      child: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pie_chart_outline, size: 40, color: CColors.grey),
          const SizedBox(height: 8),
          Text('No job data yet',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: CColors.grey)),
        ],
      )),
    );
  }

  // ── Recent activity & welcome / quick actions / suggestions ───────

  Widget _buildRecentActivity() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Recent Activity',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          TextButton(onPressed: () {}, child: const Text('View All')),
        ]),
        const SizedBox(height: CSizes.sm),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('jobs')
              .where('clientId', isEqualTo: _clientId)
              .orderBy('createdAt', descending: true)
              .limit(5)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
              return _buildEmptyActivity();
            return ListView.builder(
              shrinkWrap: true,
              physics:    const NeverScrollableScrollPhysics(),
              itemCount:  snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                return _buildActivityItem(
                    JobModel.fromMap(doc.data() as Map<String, dynamic>, doc.id));
              },
            );
          },
        ),
      ]),
    );
  }

  Widget _buildActivityItem(JobModel job) {
    IconData icon;
    Color    color;
    String   action;
    switch (job.status) {
      case 'open':
        icon = Icons.post_add; color = CColors.primary; action = 'posted a new job'; break;
      case 'in-progress':
        icon = Icons.autorenew; color = CColors.warning; action = 'job in progress'; break;
      case 'completed':
        icon = Icons.check_circle; color = CColors.success; action = 'completed a job'; break;
      case 'cancelled':
        icon = Icons.cancel; color = CColors.error; action = 'cancelled a job'; break;
      default:
        icon = Icons.fiber_manual_record; color = CColors.grey; action = 'updated job';
    }
    return Container(
      margin:     const EdgeInsets.only(bottom: 12),
      padding:    const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        Theme.of(context).brightness == Brightness.dark
            ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02),
              blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        Container(
          padding:    const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color:  color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(job.title,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('$action • ${timeago.format(job.createdAt.toDate())}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: CColors.grey)),
          ],
        )),
      ]),
    );
  }

  Widget _buildEmptyActivity() {
    return Container(
      padding:    const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        color:        Theme.of(context).brightness == Brightness.dark
            ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
      ),
      child: Center(child: Column(children: [
        Icon(Icons.history, size: 40, color: CColors.grey),
        const SizedBox(height: 8),
        Text('No recent activity',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: CColors.grey)),
      ])),
    );
  }

  Widget _buildWelcomeSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    return Container(
      margin:  const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [CColors.primary, CColors.primary.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        boxShadow: [
          BoxShadow(color: CColors.primary.withOpacity(0.3),
              blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_getGreeting()},',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: CColors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w400)),
            Text(_userName.split(' ').first,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color:      CColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize:   isUrdu ? 26 : 24)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color:        CColors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.format_quote,
                    size: 14, color: CColors.white.withOpacity(0.8)),
                const SizedBox(width: 4),
                Expanded(child: Text(_getMotivationalQuote(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:     CColors.white,
                        fontStyle: FontStyle.italic),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ],
        )),
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
              shape:  BoxShape.circle,
              color:  CColors.white.withOpacity(0.2),
              border: Border.all(color: CColors.white, width: 2)),
          child: const Icon(Icons.emoji_events,
              color: CColors.white, size: 40),
        ),
      ]),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Quick Actions',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: CSizes.sm),
        Row(children: [
          Expanded(child: _buildActionCard(context,
              icon: Icons.add_circle, label: 'Post Job',
              color: CColors.success,
              onTap: () => ref.read(clientPageIndexProvider.notifier).state = 1)),
          const SizedBox(width: 12),
          Expanded(child: _buildActionCard(context,
              icon: Icons.work, label: 'My Jobs',
              color: CColors.info,
              onTap: () => ref.read(clientPageIndexProvider.notifier).state = 0)),
          const SizedBox(width: 12),
          Expanded(child: _buildActionCard(context,
              icon: Icons.chat, label: 'Messages',
              color: CColors.warning,
              onTap: () => ref.read(clientPageIndexProvider.notifier).state = 3)),
        ]),
      ]),
    );
  }

  Widget _buildActionCard(BuildContext context, {
    required IconData icon, required String label,
    required Color color, required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:        onTap,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color:        isDark ? CColors.darkContainer : CColors.white,
            borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05),
                  blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(children: [
            Container(
              padding:    const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color:  color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _buildOpportunityCard(BuildContext context) {
    final isUrdu = context.locale.languageCode == 'ur';
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(CSizes.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [CColors.primary.withOpacity(0.95),
            CColors.secondary.withOpacity(0.95)],
        ),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        boxShadow: [
          BoxShadow(color: CColors.primary.withOpacity(0.4),
              blurRadius: 25, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color:        CColors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(24),
              border:       Border.all(color: CColors.white.withOpacity(0.3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.business_center_rounded,
                size: 16, color: CColors.white),
            const SizedBox(width: 8),
            Text('dashboard.job_platform'.tr(),
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color:         CColors.white,
                    fontWeight:    FontWeight.w800,
                    fontSize:      isUrdu ? 12 : 11,
                    letterSpacing: 1.2)),
          ]),
        ),
        const SizedBox(height: 20),
        Text('dashboard.post_job'.tr(),
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                color:      CColors.white,
                fontWeight: FontWeight.w900,
                fontSize:   isUrdu ? 26 : 24, height: 1.2)),
        const SizedBox(height: 12),
        Text('dashboard.find_workers'.tr(),
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color:    CColors.white.withOpacity(0.95),
                height:   1.6,
                fontSize: isUrdu ? 16 : 15),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: CSizes.lg),
        ElevatedButton(
          onPressed: () =>
          ref.read(clientPageIndexProvider.notifier).state = 1,
          style: ElevatedButton.styleFrom(
              backgroundColor: CColors.white,
              foregroundColor: CColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20))),
          child: Text('dashboard.post_now'.tr(),
              style: TextStyle(fontSize: isUrdu ? 16 : 14)),
        ),
      ]),
    );
  }

  Widget _buildSuggestedActions() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Suggested for you',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: CSizes.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _suggestionCard(context, icon: Icons.rate_review,
                title: 'Review Workers',
                subtitle: 'Help others by reviewing workers',
                color: CColors.primary),
            const SizedBox(width: 12),
            _suggestionCard(context, icon: Icons.trending_up,
                title: 'Boost Your Job',
                subtitle: 'Get more applicants',
                color: CColors.warning),
            const SizedBox(width: 12),
            _suggestionCard(context, icon: Icons.people,
                title: 'Find Top Workers',
                subtitle: 'Based on your preferences',
                color: CColors.success),
          ]),
        ),
      ]),
    );
  }

  Widget _suggestionCard(BuildContext context, {
    required IconData icon, required String title,
    required String subtitle, required Color color,
  }) {
    return Container(
      width:   200,
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border:       Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding:    const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color:  color.withOpacity(0.2), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 12),
        Text(title,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {},
          style: TextButton.styleFrom(
              padding:         EdgeInsets.zero,
              minimumSize:     Size.zero,
              tapTargetSize:   MaterialTapTargetSize.shrinkWrap),
          child: Text('Try now →',
              style: TextStyle(color: color, fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _buildJobFeed({int? limit}) {
    if (_clientId.isEmpty)
      return _buildEmptyState('job.login_to_view'.tr());

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('jobs')
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
          physics:    const NeverScrollableScrollPhysics(),
          itemCount:  count,
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
    Color  statusColor;
    String statusText;
    switch (job.status) {
      case 'open':        statusColor = CColors.success; statusText = 'job.status_open'.tr();        break;
      case 'in-progress': statusColor = CColors.warning; statusText = 'job.status_in_progress'.tr(); break;
      case 'completed':   statusColor = CColors.info;    statusText = 'job.status_completed'.tr();   break;
      case 'cancelled':   statusColor = CColors.error;   statusText = 'job.status_cancelled'.tr();   break;
      default:            statusColor = CColors.grey;    statusText = job.status;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: CSizes.md),
      shape:  RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusMd)),
      elevation: 2,
      child: InkWell(
        onTap:        () => _showJobDetails(job),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        child: Padding(
          padding: const EdgeInsets.all(CSizes.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(job.title,
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize:   isUrdu ? 18 : 16),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Container(
                padding:    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color:        statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:       Border.all(color: statusColor)),
                child: Text(statusText,
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color:      statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize:   isUrdu ? 12 : 10)),
              ),
            ]),
            const SizedBox(height: CSizes.sm),
            Text(job.description,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(fontSize: isUrdu ? 16 : 14),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: CSizes.md),
            Row(children: [
              Icon(Icons.access_time, size: 16, color: CColors.darkGrey),
              const SizedBox(width: 4),
              Text(timeago.format(job.createdAt.toDate()),
                  style: Theme.of(context).textTheme.bodySmall!
                      .copyWith(fontSize: isUrdu ? 14 : 12)),
              const Spacer(),
              StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('bids')
                    .where('jobId', isEqualTo: job.id).snapshots(),
                builder: (context, bidSnap) {
                  final count = bidSnap.data?.docs.length ?? 0;
                  return Row(children: [
                    Icon(Icons.gavel, size: 16, color: CColors.primary),
                    const SizedBox(width: 4),
                    Text('${'bid.total_bids'.tr()}: $count',
                        style: Theme.of(context).textTheme.labelMedium!.copyWith(
                            color:      CColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize:   isUrdu ? 14 : 12)),
                  ]);
                },
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── Disputes section ──────────────────────────────────────────────

  Widget _buildDisputesSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return StreamBuilder<List<DisputeModel>>(
      stream: DisputeService().userDisputesStream(userId: _clientId, role: 'client'),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
        final disputes  = snap.data!.where((d) => d.status != 'closed').toList();
        if (disputes.isEmpty) return const SizedBox.shrink();
        final openCount = disputes.where((d) => d.isActive).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _buildSectionHeader(context, 'My Disputes', showAction: false),
            if (openCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color:        CColors.error,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('$openCount',
                    style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   11,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
          const SizedBox(height: CSizes.spaceBtwItems),
          ...disputes.take(3).map((d) =>
              _buildDisputeCard(context, d, isDark, isUrdu)),
        ]);
      },
    );
  }

  Widget _buildDisputeCard(BuildContext context, DisputeModel dispute,
      bool isDark, bool isUrdu) {
    Color    statusColor;
    IconData statusIcon;
    switch (dispute.status) {
      case 'reviewing':
        statusColor = CColors.warning; statusIcon = Icons.manage_search_rounded; break;
      case 'resolved':
        statusColor = CColors.success; statusIcon = Icons.gavel_rounded; break;
      default:
        statusColor = CColors.error; statusIcon = Icons.flag_rounded;
    }
    return GestureDetector(
      onTap: () => Navigator.pushNamed(
          context, AppRoutes.disputes, arguments: dispute.jobId),
      child: Container(
        width:   double.infinity,
        margin:  const EdgeInsets.only(bottom: CSizes.sm),
        padding: const EdgeInsets.all(CSizes.md),
        decoration: BoxDecoration(
          color:        isDark ? CColors.darkContainer : CColors.white,
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          border:       Border.all(color: statusColor.withOpacity(0.3)),
        ),
        child: Row(children: [
          Container(
            padding:    const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color:        statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(statusIcon, color: statusColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dispute.jobTitle,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize:   isUrdu ? 14 : 13,
                      color:      isDark ? CColors.textWhite : CColors.textPrimary),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(dispute.reason,
                  style: TextStyle(
                      fontSize: isUrdu ? 12 : 11,
                      color:    CColors.darkGrey),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          )),
          Container(
            padding:    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color:        statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20)),
            child: Text(dispute.status.toUpperCase(),
                style: TextStyle(
                    color:      statusColor,
                    fontSize:   isUrdu ? 10 : 9,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: CColors.darkGrey, size: 16),
        ]),
      ),
    );
  }

  // ── Section header ────────────────────────────────────────────────

  Widget _buildSectionHeader(BuildContext context, String title,
      {String? actionText, VoidCallback? onAction, bool showAction = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(title,
          style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              fontWeight:   FontWeight.w900,
              color:        isDark ? CColors.textWhite : CColors.textPrimary,
              fontSize:     isUrdu ? 24 : 22,
              letterSpacing: -0.5)),
      if (showAction && actionText != null && onAction != null)
        InkWell(
          onTap:        onAction,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(actionText,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color:      CColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize:   isUrdu ? 16 : 14)),
          ),
        ),
    ]);
  }

  // ── Loading / empty states ────────────────────────────────────────

  Widget _buildLoadingJobs() => SizedBox(
      height: 150,
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: CColors.primary),
        const SizedBox(height: CSizes.md),
        Text('common.loading_jobs'.tr()),
      ])));

  Widget _buildEmptyState(String message) => Container(
      height: 150,
      decoration: BoxDecoration(
        color:        Theme.of(context).brightness == Brightness.dark
            ? CColors.darkContainer : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.work_outline, size: 48, color: CColors.grey),
        const SizedBox(height: CSizes.md),
        Text(message,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color:      CColors.textSecondary),
            textAlign: TextAlign.center),
      ])));

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark           = Theme.of(context).brightness == Brightness.dark;
    final isUrdu           = context.locale.languageCode == 'ur';
    final currentPageIndex = ref.watch(clientPageIndexProvider);

    ScrollController activeController;
    switch (currentPageIndex) {
      case 0: activeController = _myPostedJobsScrollController; break;
      case 1: activeController = _postJobScrollController;      break;
      case 2: activeController = _homeScrollController;         break;
      case 3: activeController = _chatScrollController;         break;
      case 4: activeController = _profileScrollController;      break;
      default: activeController = _homeScrollController;
    }

    return Scaffold(
      endDrawer:  !isUrdu ? const DashboardDrawer() : null,
      drawer:      isUrdu ? const DashboardDrawer() : null,
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: IndexedStack(index: currentPageIndex, children: _getPages()),
      bottomNavigationBar: CurvedNavBar(
        currentIndex: currentPageIndex,
        onTap: (index) {
          ref.read(clientPageIndexProvider.notifier).state = index;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            switch (index) {
              case 0: if (_myPostedJobsScrollController.hasClients) _myPostedJobsScrollController.jumpTo(0); break;
              case 1: if (_postJobScrollController.hasClients)      _postJobScrollController.jumpTo(0);      break;
              case 2: if (_homeScrollController.hasClients)         _homeScrollController.jumpTo(0);         break;
              case 3: if (_chatScrollController.hasClients)         _chatScrollController.jumpTo(0);         break;
              case 4: if (_profileScrollController.hasClients)      _profileScrollController.jumpTo(0);      break;
            }
          });
        },
        userRole:         'client',
        scrollController: activeController,
      ),
    );
  }
}
