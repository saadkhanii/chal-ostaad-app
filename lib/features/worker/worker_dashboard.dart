// lib/features/worker/worker_dashboard.dart

import 'package:chal_ostaad/features/worker/worker_dashboard_header.dart';
import 'package:chal_ostaad/features/worker/worker_job_details_screen.dart' as job_details;
import 'package:chal_ostaad/features/notifications/notifications_screen.dart';
import 'package:chal_ostaad/features/chat/worker_chat_inbox_screen.dart';
import 'package:chal_ostaad/features/worker/find_jobs_screen.dart';
import 'package:chal_ostaad/features/worker/my_bids_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/job_model.dart';
import '../../core/models/bid_model.dart';
import '../../core/models/payment_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/category_service.dart';
import '../../core/services/worker_service.dart';
import '../../core/services/payment_service.dart';
import '../../shared/widgets/dashboard_drawer.dart';
import '../../shared/widgets/curved_nav_bar.dart';
import '../profile/worker_profile_screen.dart';
import '../dispute/dispute_status_banner.dart';
import '../../core/models/dispute_model.dart';
import '../../core/services/dispute_service.dart';

final workerLoadingProvider   = StateProvider<bool>((ref) => true);
final workerPageIndexProvider = StateProvider<int>((ref) => 2);

class WorkerDashboard extends ConsumerStatefulWidget {
  const WorkerDashboard({super.key});

  @override
  ConsumerState<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends ConsumerState<WorkerDashboard>
    with TickerProviderStateMixin {

  String _userName        = '';
  String _workerId        = '';
  String _workerCategory  = '';
  String _photoBase64     = '';
  int    _selectedFilter  = 0;

  List<String> _filterOptions    = [];
  List<String> _morningQuotes    = [];
  List<String> _afternoonQuotes  = [];
  List<String> _eveningQuotes    = [];

  final ScrollController _findJobsScrollController = ScrollController();
  final ScrollController _myBidsScrollController   = ScrollController();
  final ScrollController _homeScrollController     = ScrollController();
  final ScrollController _chatScrollController     = ScrollController();
  final ScrollController _profileScrollController  = ScrollController();

  final WorkerService   _workerService   = WorkerService();
  final BidService      _bidService      = BidService();
  final CategoryService _categoryService = CategoryService();
  final PaymentService  _paymentService  = PaymentService();
  final FirebaseFirestore _firestore     = FirebaseFirestore.instance;

  String _workerCategoryName = '';

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
        _userName = 'dashboard.worker'.tr();
        _filterOptions = [
          'dashboard.all_jobs'.tr(),
          'dashboard.my_category'.tr(),
        ];
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
    _findJobsScrollController.dispose();
    _myBidsScrollController.dispose();
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
      final userName = prefs.getString('user_name');

      if (mounted) {
        setState(() {
          if (userName != null && userName.isNotEmpty) _userName = userName;
          if (userUid  != null) _workerId = userUid;
        });
      }

      if (userUid != null) {
        await _loadWorkerProfile();
        try {
          final workerDoc = await FirebaseFirestore.instance
              .collection('workers').doc(userUid).get();
          if (workerDoc.exists) {
            final info  = workerDoc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
            final photo = info['photoBase64'] as String? ?? '';
            if (mounted) setState(() => _photoBase64 = photo);
          }
        } catch (e) {
          debugPrint('Error fetching worker photo: $e');
        }
      }

      if (mounted) ref.read(workerLoadingProvider.notifier).state = false;
    } catch (e) {
      debugPrint('Error loading worker data: $e');
      if (mounted) ref.read(workerLoadingProvider.notifier).state = false;
    }
  }

  Future<void> _loadWorkerProfile() async {
    try {
      final worker = await _workerService.getCurrentWorker();
      if (worker != null && worker.categoryId != null && worker.categoryId!.isNotEmpty) {
        final categoryName =
        await _categoryService.getCategoryName(worker.categoryId!);
        if (mounted) {
          setState(() {
            _workerCategory     = worker.categoryId!;
            _workerCategoryName = categoryName;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading worker profile: $e');
    }
  }

  // ── Stats — now reads from real payments collection ───────────────

  Future<Map<String, dynamic>> _fetchWorkerStats() async {
    if (_workerId.isEmpty) {
      return {
        'bidsPlaced': 0, 'jobsWon': 0,
        'completedJobs': 0, 'inProgressJobs': 0,
        'totalEarnings': 0.0, 'platformFeesPaid': 0.0,
        'netEarnings': 0.0, 'cashEarnings': 0.0,
        'stripeEarnings': 0.0, 'pendingCash': 0.0,
        'thisMonthEarnings': 0.0, 'rating': 'N/A',
      };
    }
    try {
      // Bids
      final bidsSnap = await _firestore
          .collection('bids').where('workerId', isEqualTo: _workerId).get();
      final totalBids    = bidsSnap.docs.length;
      final acceptedBids = bidsSnap.docs.where((d) => d['status'] == 'accepted').length;

      // Payments from payments collection (source of truth)
      final paymentsSnap = await _firestore
          .collection('payments').where('workerId', isEqualTo: _workerId).get();
      final payments = paymentsSnap.docs
          .map((d) => PaymentModel.fromSnapshot(
          d as DocumentSnapshot<Map<String, dynamic>>))
          .toList();

      final completed     = payments.where((p) => p.status == 'completed').toList();
      final cashCompleted = completed.where((p) => p.isCash).toList();
      final stripeDone    = completed.where((p) => p.isStripe).toList();
      final pendingCash   = payments.where((p) => p.isCash && p.status == 'pending').toList();

      double totalEarnings   = completed.fold(0, (s, p) => s + p.amount);
      double cashEarnings    = cashCompleted.fold(0, (s, p) => s + p.amount);
      double stripeEarnings  = stripeDone.fold(0, (s, p) => s + p.amount);
      double pendingCashAmt  = pendingCash.fold(0, (s, p) => s + p.amount);

      // Platform fee stored per payment; fall back to calculating it
      double platformFees = 0;
      double netEarnings  = 0;
      for (final p in completed) {
        final snap = await _firestore.collection('payments').doc(p.id).get();
        final fee = (snap.data()?['platformFee'] as num?)?.toDouble()
            ?? PaymentService.calcPlatformFee(p.amount);
        final net = (snap.data()?['workerNet'] as num?)?.toDouble()
            ?? (p.amount - fee);
        platformFees += fee;
        netEarnings  += net;
      }

      // This month
      final now        = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      double thisMonth = completed
          .where((p) =>
      p.completedAt != null &&
          p.completedAt!.toDate().isAfter(monthStart))
          .fold(0, (s, p) => s + p.amount);

      // Jobs count
      final jobsSnap = await _firestore
          .collection('jobs').where('clientId', isEqualTo: _workerId).get();
      // Actually count jobs this worker was accepted for via bids
      final acceptedJobIds = bidsSnap.docs
          .where((d) => d['status'] == 'accepted')
          .map((d) => d['jobId'] as String)
          .toList();

      int completedJobs  = 0;
      int inProgressJobs = 0;
      if (acceptedJobIds.isNotEmpty) {
        // Batch in chunks of 10 (Firestore whereIn limit)
        for (int i = 0; i < acceptedJobIds.length; i += 10) {
          final chunk = acceptedJobIds.sublist(
              i, i + 10 > acceptedJobIds.length ? acceptedJobIds.length : i + 10);
          final snap = await _firestore
              .collection('jobs').where(FieldPath.documentId, whereIn: chunk).get();
          for (final d in snap.docs) {
            final s = d['status'] as String? ?? '';
            if (s == 'completed') completedJobs++;
            if (s == 'in-progress') inProgressJobs++;
          }
        }
      }

      // Rating
      String ratingText = 'N/A';
      final workerDoc = await _firestore.collection('workers').doc(_workerId).get();
      if (workerDoc.exists) {
        final ratings     = workerDoc.data()?['ratings'] as Map<String, dynamic>?;
        final avgRating   = ratings?['average']      as num?;
        final totalReviews = ratings?['totalReviews'] as int? ?? 0;
        if (avgRating != null && avgRating > 0 && totalReviews > 0) {
          ratingText = avgRating.toDouble().toStringAsFixed(1);
        }
      }

      return {
        'bidsPlaced':       totalBids,
        'jobsWon':          acceptedBids,
        'completedJobs':    completedJobs,
        'inProgressJobs':   inProgressJobs,
        'totalEarnings':    totalEarnings,
        'platformFeesPaid': platformFees,
        'netEarnings':      netEarnings,
        'cashEarnings':     cashEarnings,
        'stripeEarnings':   stripeEarnings,
        'pendingCash':      pendingCashAmt,
        'thisMonthEarnings': thisMonth,
        'rating':           ratingText,
      };
    } catch (e) {
      debugPrint('Error fetching worker stats: $e');
      return {
        'bidsPlaced': 0, 'jobsWon': 0,
        'completedJobs': 0, 'inProgressJobs': 0,
        'totalEarnings': 0.0, 'platformFeesPaid': 0.0,
        'netEarnings': 0.0, 'cashEarnings': 0.0,
        'stripeEarnings': 0.0, 'pendingCash': 0.0,
        'thisMonthEarnings': 0.0, 'rating': 'N/A',
      };
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  void _showJobDetails(JobModel job) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => job_details.WorkerJobDetailsScreen(
        job:            job,
        workerId:       _workerId,
        workerCategory: _workerCategory,
        onBidPlaced:    () => setState(() {}),
      ),
    ));
  }

  void _showAllJobs() => ref.read(workerPageIndexProvider.notifier).state = 0;
  void _showAllBids() => ref.read(workerPageIndexProvider.notifier).state = 1;

  String _getGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'dashboard.good_morning'.tr();
    if (h < 17) return 'dashboard.good_afternoon'.tr();
    return 'dashboard.good_evening'.tr();
  }

  String _getMotivationalQuote() {
    final h = DateTime.now().hour;
    final r = DateTime.now().millisecond % 3;
    if (h < 12) return _morningQuotes.isNotEmpty   ? _morningQuotes[r]   : '';
    if (h < 17) return _afternoonQuotes.isNotEmpty ? _afternoonQuotes[r] : '';
    return _eveningQuotes.isNotEmpty ? _eveningQuotes[r] : '';
  }

  String _formatCurrency(double amount) {
    if (amount == 0)           return 'Rs 0';
    if (amount >= 10000000)    return 'Rs ${(amount / 10000000).toStringAsFixed(1)}Cr';
    if (amount >= 100000)      return 'Rs ${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000)        return 'Rs ${(amount / 1000).toStringAsFixed(1)}k';
    return 'Rs ${amount.toStringAsFixed(0)}';
  }

  String _getBidStatusText(String s) {
    switch (s) {
      case 'accepted': return 'bid.status_accepted'.tr();
      case 'pending':  return 'bid.status_pending'.tr();
      case 'rejected': return 'bid.status_rejected'.tr();
      default:         return s;
    }
  }

  Color _getBidStatusColor(String s) {
    switch (s) {
      case 'accepted': return CColors.success;
      case 'pending':  return CColors.warning;
      case 'rejected': return CColors.error;
      default:         return CColors.grey;
    }
  }

  IconData _getBidStatusIcon(String s) {
    switch (s) {
      case 'accepted': return Icons.check_circle_rounded;
      case 'pending':  return Icons.access_time_rounded;
      case 'rejected': return Icons.cancel_rounded;
      default:         return Icons.help_rounded;
    }
  }

  // ── Pages list ────────────────────────────────────────────────────

  List<Widget> _getPages() {
    return [
      FindJobsScreen(scrollController: _findJobsScrollController, showAppBar: false),
      MyBidsScreen(scrollController: _myBidsScrollController, showAppBar: false),
      _buildHomePage(),
      WorkerChatInboxScreen(scrollController: _chatScrollController, showAppBar: false, workerId: _workerId),
      WorkerProfileScreen(showAppBar: false),
    ];
  }

  // ── Home page ─────────────────────────────────────────────────────

  Widget _buildHomePage() {
    final isLoading = ref.watch(workerLoadingProvider);
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
                WorkerDashboardHeader(
                  userName:          _userName,
                  photoUrl:          _photoBase64,
                  onNotificationTap: () =>
                      Navigator.pushNamed(context, AppRoutes.notifications),
                ),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildWelcomeSection(context),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildQuickActions(context),
                const SizedBox(height: CSizes.spaceBtwSections),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: CSizes.defaultSpace),
                  child: _buildOpportunityCard(context),
                ),
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
                    'dashboard.performance_overview'.tr(),
                    showAction: false),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildStatsGrid(context),
                const SizedBox(height: CSizes.spaceBtwSections),

                // ── Earnings breakdown ──────────────────────────
                _buildSectionHeader(context, 'Earnings Breakdown',
                    showAction: false),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildEarningsCard(context),
                const SizedBox(height: CSizes.spaceBtwSections),

                // ── Recent payments ─────────────────────────────
                _buildSectionHeader(context, 'Recent Payments',
                    showAction: false),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildRecentPayments(context),
                const SizedBox(height: CSizes.spaceBtwSections),

                _buildSectionHeader(context,
                    'dashboard.recent_activity'.tr(),
                    showAction: false),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildRecentActivity(),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSuggestedActions(),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(context,
                    'dashboard.available_jobs'.tr(),
                    actionText: 'common.view_all'.tr(),
                    onAction:   _showAllJobs),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildJobFeed(limit: 3),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(context, 'bid.recent_bids'.tr(),
                    actionText: 'common.view_all'.tr(),
                    onAction:   _showAllBids),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildMyBidsList(limit: 3),
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

  // ── Earnings breakdown card ───────────────────────────────────────

  Widget _buildEarningsCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchWorkerStats(),
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;
        final s = snap.data ?? {};

        final total    = (s['totalEarnings']    as double?) ?? 0;
        final net      = (s['netEarnings']      as double?) ?? 0;
        final fee      = (s['platformFeesPaid'] as double?) ?? 0;
        final cash     = (s['cashEarnings']     as double?) ?? 0;
        final stripe   = (s['stripeEarnings']   as double?) ?? 0;
        final pending  = (s['pendingCash']      as double?) ?? 0;
        final monthly  = (s['thisMonthEarnings'] as double?) ?? 0;

        return Container(
          padding:    const EdgeInsets.all(CSizes.lg),
          decoration: BoxDecoration(
            color: isDark ? CColors.darkContainer : CColors.white,
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
                child: CircularProgressIndicator(),
              ))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Total net earnings — hero number
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
                const Text('Your Net Earnings',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text(_formatCurrency(net),
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

            // Break-down rows
            _earningRow(context, isDark,
                icon:  Icons.receipt_long_rounded,
                color: CColors.info,
                label: 'Gross Earnings',
                value: _formatCurrency(total)),
            _divider(isDark),
            _earningRow(context, isDark,
                icon:  Icons.storefront_rounded,
                color: CColors.error,
                label: 'Platform Fee (${PaymentService.platformFeePercent.toStringAsFixed(0)}%)',
                value: '- ${_formatCurrency(fee)}'),
            _divider(isDark),
            _earningRow(context, isDark,
                icon:  Icons.credit_card_rounded,
                color: CColors.primary,
                label: 'Online (Stripe)',
                value: _formatCurrency(stripe)),
            _divider(isDark),
            _earningRow(context, isDark,
                icon:  Icons.payments_outlined,
                color: CColors.success,
                label: 'Cash Received',
                value: _formatCurrency(cash)),
            if (pending > 0) ...[
              _divider(isDark),
              _earningRow(context, isDark,
                  icon:  Icons.hourglass_top_rounded,
                  color: CColors.warning,
                  label: 'Cash Pending Confirmation',
                  value: _formatCurrency(pending),
                  highlight: true),
            ],
          ]),
        );
      },
    );
  }

  Widget _earningRow(BuildContext context, bool isDark, {
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
                fontSize:   13,
                color:      isDark ? CColors.textWhite.withOpacity(0.8) : CColors.textPrimary))),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize:   14,
                color:      highlight ? CColors.warning : (isDark ? CColors.textWhite : CColors.textPrimary))),
      ]),
    );
  }

  Widget _divider(bool isDark) => Divider(
      height: 1, color: isDark ? CColors.darkerGrey : CColors.borderPrimary);

  // ── Recent payments list ──────────────────────────────────────────

  Widget _buildRecentPayments(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_workerId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<List<PaymentModel>>(
      stream: _paymentService.streamPaymentsByWorker(_workerId),
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
          return Container(
            padding:    const EdgeInsets.all(CSizes.lg),
            decoration: BoxDecoration(
              color: isDark ? CColors.darkContainer : CColors.white,
              borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
            ),
            child: Center(
              child: Column(children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 40, color: CColors.grey),
                const SizedBox(height: 8),
                const Text('No payments yet',
                    style: TextStyle(color: CColors.darkGrey)),
              ]),
            ),
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
        ? CColors.success
        : (p.isCash ? CColors.warning : CColors.error);
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
                  color:      isCompleted ? CColors.success : CColors.warning)),
          if (p.completedAt != null)
            Text(timeago.format(p.completedAt!.toDate()),
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
      future: _fetchWorkerStats(),
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;
        final s = snap.data ??
            {'bidsPlaced': 0, 'jobsWon': 0, 'completedJobs': 0,
              'inProgressJobs': 0, 'thisMonthEarnings': 0.0, 'rating': 'N/A'};

        final items = [
          {'label': 'Bids Placed',   'value': isLoading ? '...' : '${s['bidsPlaced']}',
            'icon': Icons.gavel_rounded, 'color': CColors.primary},
          {'label': 'Jobs Won',      'value': isLoading ? '...' : '${s['jobsWon']}',
            'icon': Icons.emoji_events_rounded, 'color': CColors.success},
          {'label': 'In Progress',   'value': isLoading ? '...' : '${s['inProgressJobs']}',
            'icon': Icons.autorenew_rounded, 'color': CColors.warning},
          {'label': 'Completed',     'value': isLoading ? '...' : '${s['completedJobs']}',
            'icon': Icons.check_circle_rounded, 'color': CColors.info},
          {'label': 'This Month',    'value': isLoading ? '...' : _formatCurrency((s['thisMonthEarnings'] as double?) ?? 0),
            'icon': Icons.calendar_month_rounded, 'color': CColors.primary},
          {'label': 'Rating',        'value': isLoading ? '...' : '${s['rating']}',
            'icon': Icons.star_rounded, 'color': CColors.warning},
        ];

        return GridView.count(
          crossAxisCount:  2,
          shrinkWrap:      true,
          physics:         const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing:  12,
          childAspectRatio: 1.6,
          children: items.map((item) => _buildStatCard(context,
              label: item['label'] as String,
              value: item['value'] as String,
              icon:  item['icon']  as IconData,
              color: item['color'] as Color)).toList(),
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
          BoxShadow(color: Colors.black.withOpacity(0.05),
              blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        Container(
          padding:    const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color:        color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:  MainAxisAlignment.center,
          children: [
            Text(value,
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize:   isUrdu ? 18 : 16),
                overflow: TextOverflow.ellipsis),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    fontSize: isUrdu ? 12 : 11,
                    color:    isDark ? Colors.grey[400] : Colors.grey[600]),
                overflow: TextOverflow.ellipsis, maxLines: 2),
          ],
        )),
      ]),
    );
  }

  // ── Welcome / opportunity / quick actions (unchanged structure) ───

  Widget _buildWelcomeSection(BuildContext context) {
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
                Icon(Icons.format_quote, size: 14,
                    color: CColors.white.withOpacity(0.8)),
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
          width:  80, height: 80,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CColors.white.withOpacity(0.2),
              border: Border.all(color: CColors.white, width: 2)),
          child: const Icon(Icons.handyman_rounded,
              color: CColors.white, size: 40),
        ),
      ]),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('dashboard.quick_actions'.tr(),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: CSizes.sm),
        Row(children: [
          Expanded(child: _buildActionCard(context,
              icon:  Icons.search_rounded,
              label: 'dashboard.find_jobs'.tr(),
              color: CColors.success,
              onTap: _showAllJobs)),
          const SizedBox(width: 12),
          Expanded(child: _buildActionCard(context,
              icon:  Icons.gavel_rounded,
              label: 'dashboard.my_bids'.tr(),
              color: CColors.info,
              onTap: _showAllBids)),
          const SizedBox(width: 12),
          Expanded(child: _buildActionCard(context,
              icon:  Icons.chat_rounded,
              label: 'dashboard.messages'.tr(),
              color: CColors.warning,
              onTap: () =>
              ref.read(workerPageIndexProvider.notifier).state = 3)),
        ]),
      ]),
    );
  }

  Widget _buildActionCard(BuildContext context, {
    required IconData icon,
    required String   label,
    required Color    color,
    required VoidCallback onTap,
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
            Text(label,
                style: Theme.of(context).textTheme.bodyMedium
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
            const Icon(Icons.rocket_launch_rounded,
                size: 16, color: CColors.white),
            const SizedBox(width: 8),
            Text('dashboard.bidding_platform'.tr(),
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color:       CColors.white,
                    fontWeight:  FontWeight.w800,
                    fontSize:    isUrdu ? 12 : 11,
                    letterSpacing: 1.2)),
          ]),
        ),
        const SizedBox(height: 20),
        Text('dashboard.find_next_project'.tr(),
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                color:      CColors.white,
                fontWeight: FontWeight.w900,
                fontSize:   isUrdu ? 26 : 24,
                height:     1.2)),
        const SizedBox(height: 12),
        Text('dashboard.bidding_description'.tr(),
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color:    CColors.white.withOpacity(0.95),
                height:   1.6,
                fontSize: isUrdu ? 16 : 15),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: CSizes.lg),
        ElevatedButton(
          onPressed: _showAllJobs,
          style: ElevatedButton.styleFrom(
              backgroundColor: CColors.white,
              foregroundColor: CColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20))),
          child: Text('dashboard.browse_jobs'.tr(),
              style: TextStyle(fontSize: isUrdu ? 16 : 14)),
        ),
      ]),
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

  // ── Disputes section ──────────────────────────────────────────────

  Widget _buildDisputesSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return StreamBuilder<List<DisputeModel>>(
      stream: DisputeService().userDisputesStream(userId: _workerId, role: 'worker'),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final disputes = snap.data!.where((d) => d.status != 'closed').toList();
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
    Color statusColor;
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

  // ── Filter chips / job feed / bids list (unchanged logic) ─────────

  Widget _buildFilterChips() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _filterOptions.asMap().entries.map((entry) {
          final idx      = entry.key;
          final label    = entry.value;
          final isSelected = _selectedFilter == idx;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label:           Text(label, style: TextStyle(fontSize: isUrdu ? 16 : 14)),
              selected:        isSelected,
              onSelected:      (s) { if (s) setState(() => _selectedFilter = idx); },
              selectedColor:   CColors.primary,
              labelStyle:      TextStyle(
                  color:      isSelected ? CColors.white : (isDark ? CColors.white : CColors.textPrimary),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
              backgroundColor: isDark ? CColors.darkContainer : CColors.softGrey,
              shape: StadiumBorder(side: BorderSide(
                  color: isSelected ? CColors.primary : (isDark ? CColors.darkGrey : CColors.grey))),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildJobFeed({int? limit}) {
    if (_workerId.isEmpty)
      return _buildEmptyState('errors.login_to_view_jobs'.tr());

    // Always filter by the worker's category — they should never see other categories
    if (_workerCategoryName.isEmpty) return _buildLoadingJobs();

    final Query query = _firestore
        .collection('jobs')
        .where('status',   isEqualTo: 'open')
        .where('category', isEqualTo: _workerCategoryName)
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return _buildLoadingJobs();
        if (snapshot.hasError)
          return _buildEmptyState(
              '${'errors.load_jobs_failed'.tr()}: ${snapshot.error}');
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return _buildEmptyState('job.no_jobs_available'.tr());

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
    return Card(
      margin: const EdgeInsets.only(bottom: CSizes.md),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusMd)),
      elevation: 2,
      child: InkWell(
        onTap:        () => _showJobDetails(job),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        child: Padding(
          padding: const EdgeInsets.all(CSizes.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(
                child: Text(job.title,
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize:   isUrdu ? 18 : 16),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding:    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color:        CColors.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:       Border.all(color: CColors.info)),
                child: Text(job.category,
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color:      CColors.info,
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

  Widget _buildMyBidsList({int? limit}) {
    if (_workerId.isEmpty)
      return _buildEmptyState('errors.login_to_view_bids'.tr());

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('bids')
          .where('workerId', isEqualTo: _workerId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return _buildLoadingBids();
        if (snapshot.hasError)
          return _buildEmptyState(
              '${'errors.load_bids_failed'.tr()}: ${snapshot.error}');
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return _buildEmptyState('bid.no_bids_placed'.tr());

        int count = snapshot.data!.docs.length;
        if (limit != null && limit < count) count = limit;

        return ListView.builder(
          shrinkWrap: true,
          physics:    const NeverScrollableScrollPhysics(),
          itemCount:  count,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final bid = BidModel.fromSnapshot(
                doc as DocumentSnapshot<Map<String, dynamic>>);
            return _buildBidItem(bid);
          },
        );
      },
    );
  }

  Widget _buildBidItem(BidModel bid) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final isUrdu       = context.locale.languageCode == 'ur';
    final statusColor  = _getBidStatusColor(bid.status);

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('jobs').doc(bid.jobId).get(),
      builder: (context, jobSnap) {
        if (jobSnap.connectionState == ConnectionState.waiting)
          return ListTile(title: Text('common.loading'.tr()));
        if (!jobSnap.hasData || !jobSnap.data!.exists)
          return ListTile(title: Text('job.job_not_found'.tr()));

        final jobData  = jobSnap.data!.data() as Map<String, dynamic>;
        final jobTitle = jobData['title'] ?? 'job.unknown'.tr();

        return Card(
          margin: const EdgeInsets.only(bottom: CSizes.sm),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CSizes.cardRadiusMd)),
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(CSizes.md),
            child: Row(children: [
              Container(
                width:      44, height: 44,
                decoration: BoxDecoration(
                    color:  statusColor.withOpacity(0.12),
                    shape:  BoxShape.circle),
                child: Icon(_getBidStatusIcon(bid.status),
                    color: statusColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(jobTitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall!.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize:   isUrdu ? 16 : 14)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(
                      padding:    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color:        statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border:       Border.all(color: statusColor.withOpacity(0.4))),
                      child: Text(_getBidStatusText(bid.status),
                          style: TextStyle(
                              color:      statusColor,
                              fontSize:   isUrdu ? 12 : 11,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Text(_formatCurrency(bid.amount),
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark ? CColors.textWhite : CColors.textPrimary)),
                  ]),
                ],
              )),
              Text(timeago.format(bid.createdAt.toDate()),
                  style: Theme.of(context).textTheme.bodySmall!
                      .copyWith(color: CColors.textSecondary)),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildRecentActivity() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    if (_workerId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('bids')
          .where('workerId', isEqualTo: _workerId)
          .orderBy('createdAt', descending: true)
          .limit(4)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return _buildEmptyState('dashboard.no_recent_activity'.tr());

        return Container(
          decoration: BoxDecoration(
            color:        isDark ? CColors.darkContainer : CColors.white,
            borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04),
                  blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics:    const NeverScrollableScrollPhysics(),
            itemCount:  snapshot.data!.docs.length,
            separatorBuilder: (_, __) => Divider(height: 1,
                color: isDark ? Colors.grey[800] : Colors.grey[200]),
            itemBuilder: (context, index) {
              final bid = BidModel.fromSnapshot(
                  snapshot.data!.docs[index]
                  as DocumentSnapshot<Map<String, dynamic>>);
              final statusColor = _getBidStatusColor(bid.status);
              return ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                      color:  statusColor.withOpacity(0.12),
                      shape:  BoxShape.circle),
                  child: Icon(_getBidStatusIcon(bid.status),
                      color: statusColor, size: 20),
                ),
                title: FutureBuilder<DocumentSnapshot>(
                  future: _firestore.collection('jobs').doc(bid.jobId).get(),
                  builder: (context, jobSnap) {
                    final title = (jobSnap.data?.data()
                    as Map<String, dynamic>?)?['title']
                        ?? 'job.unknown'.tr();
                    return Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium!
                            .copyWith(fontWeight: FontWeight.w600));
                  },
                ),
                subtitle: Text(
                  '${_getBidStatusText(bid.status)} · ${_formatCurrency(bid.amount)}',
                  style: TextStyle(
                      color:      statusColor,
                      fontSize:   isUrdu ? 13 : 12,
                      fontWeight: FontWeight.w500),
                ),
                trailing: Text(timeago.format(bid.createdAt.toDate()),
                    style: Theme.of(context).textTheme.bodySmall),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSuggestedActions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    final tips = [
      {'icon': Icons.person_pin_rounded,         'color': CColors.primary,
        'title': 'dashboard.tip_complete_profile'.tr(),
        'subtitle': 'dashboard.tip_complete_profile_desc'.tr(),
        'onTap': () => ref.read(workerPageIndexProvider.notifier).state = 4},
      {'icon': Icons.notifications_active_rounded, 'color': CColors.warning,
        'title': 'dashboard.tip_new_jobs'.tr(),
        'subtitle': 'dashboard.tip_new_jobs_desc'.tr(),
        'onTap': _showAllJobs},
      {'icon': Icons.trending_up_rounded,          'color': CColors.success,
        'title': 'dashboard.tip_win_bids'.tr(),
        'subtitle': 'dashboard.tip_win_bids_desc'.tr(),
        'onTap': _showAllBids},
    ];
    return Container(
      padding:    const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.lightbulb_rounded, color: CColors.warning, size: 20),
          const SizedBox(width: 8),
          Text('dashboard.suggested_actions'.tr(),
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.w700, fontSize: isUrdu ? 18 : 16)),
        ]),
        const SizedBox(height: CSizes.md),
        ...tips.map((tip) => _buildTipTile(context,
            icon:     tip['icon']     as IconData,
            color:    tip['color']    as Color,
            title:    tip['title']    as String,
            subtitle: tip['subtitle'] as String,
            onTap:    tip['onTap']    as VoidCallback)),
      ]),
    );
  }

  Widget _buildTipTile(BuildContext context, {
    required IconData icon, required Color color,
    required String title, required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(CSizes.cardRadiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(children: [
          Container(
            padding:    const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color:        color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(fontWeight: FontWeight.w600)),
            Text(subtitle,
                style: Theme.of(context).textTheme.bodySmall!
                    .copyWith(color: CColors.textSecondary)),
          ])),
          const Icon(Icons.chevron_right_rounded,
              color: CColors.grey, size: 20),
        ]),
      ),
    );
  }

  // ── Loading / empty states ────────────────────────────────────────

  Widget _buildLoadingJobs() => SizedBox(
      height: 150,
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: CColors.primary),
        const SizedBox(height: CSizes.md),
        Text('common.loading_jobs'.tr()),
      ])));

  Widget _buildLoadingBids() => SizedBox(
      height: 150,
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: CColors.primary),
        const SizedBox(height: CSizes.md),
        Text('common.loading_bids'.tr()),
      ])));

  Widget _buildEmptyState(String message) => Container(
      height: 150,
      decoration: BoxDecoration(
        color:        Theme.of(context).brightness == Brightness.dark
            ? CColors.darkContainer
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.work_outline, size: 48, color: CColors.grey),
        const SizedBox(height: CSizes.md),
        Text(message,
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: CColors.textSecondary),
            textAlign: TextAlign.center),
      ])));

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark           = Theme.of(context).brightness == Brightness.dark;
    final isUrdu           = context.locale.languageCode == 'ur';
    final currentPageIndex = ref.watch(workerPageIndexProvider);

    ScrollController activeController;
    switch (currentPageIndex) {
      case 0: activeController = _findJobsScrollController; break;
      case 1: activeController = _myBidsScrollController;   break;
      case 2: activeController = _homeScrollController;     break;
      case 3: activeController = _chatScrollController;     break;
      case 4: activeController = _profileScrollController;  break;
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
          ref.read(workerPageIndexProvider.notifier).state = index;
          ref.read(navBarVisibilityProvider.notifier).state = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            switch (index) {
              case 0: if (_findJobsScrollController.hasClients) _findJobsScrollController.jumpTo(0); break;
              case 1: if (_myBidsScrollController.hasClients)   _myBidsScrollController.jumpTo(0);   break;
              case 2: if (_homeScrollController.hasClients)     _homeScrollController.jumpTo(0);     break;
              case 3: if (_chatScrollController.hasClients)     _chatScrollController.jumpTo(0);     break;
              case 4: if (_profileScrollController.hasClients)  _profileScrollController.jumpTo(0);  break;
            }
          });
        },
        userRole:         'worker',
        scrollController: activeController,
      ),
    );
  }
}