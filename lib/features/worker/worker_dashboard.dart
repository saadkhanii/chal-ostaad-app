// lib/features/worker/worker_dashboard.dart

import 'package:chal_ostaad/features/worker/worker_dashboard_header.dart';
import 'package:chal_ostaad/features/worker/worker_job_details_screen.dart'
as job_details;
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
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/dashboard_drawer.dart';
import '../../shared/widgets/curved_nav_bar.dart';
import '../profile/worker_profile_screen.dart';
import '../dispute/dispute_status_banner.dart';
import '../../core/models/dispute_model.dart';
import '../../core/services/dispute_service.dart';

final workerLoadingProvider = StateProvider<bool>((ref) => true);
final workerPageIndexProvider = StateProvider<int>((ref) => 2);

class WorkerDashboard extends ConsumerStatefulWidget {
  const WorkerDashboard({super.key});

  @override
  ConsumerState<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends ConsumerState<WorkerDashboard>
    with TickerProviderStateMixin {
  String _userName = '';
  String _workerId = '';
  String _workerCategory = '';
  String _photoBase64 = '';
  int _selectedFilter = 0;

  Future<Map<String, dynamic>>? _workerStatsFuture;

  List<String> _filterOptions = [];
  List<String> _morningQuotes = [];
  List<String> _afternoonQuotes = [];
  List<String> _eveningQuotes = [];

  final ScrollController _findJobsScrollController = ScrollController();
  final ScrollController _myBidsScrollController = ScrollController();
  final ScrollController _homeScrollController = ScrollController();
  final ScrollController _chatScrollController = ScrollController();
  final ScrollController _profileScrollController = ScrollController();

  final WorkerService _workerService = WorkerService();
  final BidService _bidService = BidService();
  final CategoryService _categoryService = CategoryService();
  final PaymentService _paymentService = PaymentService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _workerCategoryName = '';

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
        _userName = 'dashboard.worker'.tr();
        _filterOptions = [
          'dashboard.all_jobs'.tr(),
          'dashboard.my_category'.tr(),
        ];
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
      final prefs = await SharedPreferences.getInstance();
      final userUid = prefs.getString('user_uid');
      final userName = prefs.getString('user_name');

      if (mounted) {
        setState(() {
          if (userName != null && userName.isNotEmpty) _userName = userName;
          if (userUid != null) _workerId = userUid;
        });
      }

      if (userUid != null) {
        await _loadWorkerProfile();
        try {
          final workerDoc = await FirebaseFirestore.instance
              .collection('workers')
              .doc(userUid)
              .get();
          if (workerDoc.exists) {
            final info =
                workerDoc.data()?['personalInfo'] as Map<String, dynamic>? ??
                    {};
            final photo = info['photoBase64'] as String? ?? '';
            if (mounted) setState(() => _photoBase64 = photo);
          }
        } catch (e) {
          debugPrint('Error fetching worker photo: $e');
        }
      }

      if (mounted) {
        setState(() => _workerStatsFuture = _fetchWorkerStats());
        ref.read(workerLoadingProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error loading worker data: $e');
      if (mounted) ref.read(workerLoadingProvider.notifier).state = false;
    }
  }

  Future<void> _loadWorkerProfile() async {
    try {
      final worker = await _workerService.getCurrentWorker();
      if (worker != null &&
          worker.categoryId != null &&
          worker.categoryId!.isNotEmpty) {
        final categoryName =
        await _categoryService.getCategoryName(worker.categoryId!);
        if (mounted) {
          setState(() {
            _workerCategory = worker.categoryId!;
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
        'bidsPlaced': 0,
        'jobsWon': 0,
        'completedJobs': 0,
        'inProgressJobs': 0,
        'totalEarnings': 0.0,
        'platformFeesPaid': 0.0,
        'netEarnings': 0.0,
        'cashEarnings': 0.0,
        'stripeEarnings': 0.0,
        'pendingCash': 0.0,
        'thisMonthEarnings': 0.0,
        'rating': 'N/A',
      };
    }
    try {
      // Bids, payments, and worker doc are independent — fetch concurrently.
      // (Removed the unused `jobs where clientId == _workerId` query —
      // its result, jobsSnap, was never read anywhere in the original code.)
      final results = await Future.wait([
        _firestore.collection('bids').where('workerId', isEqualTo: _workerId).get(),
        _firestore.collection('payments').where('workerId', isEqualTo: _workerId).get(),
        _firestore.collection('workers').doc(_workerId).get(),
      ]);
      final bidsSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final paymentsSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final workerDoc = results[2] as DocumentSnapshot<Map<String, dynamic>>;

      final totalBids = bidsSnap.docs.length;
      final acceptedBids =
          bidsSnap.docs.where((d) => d['status'] == 'accepted').length;

      final payments = paymentsSnap.docs
          .map((d) => PaymentModel.fromSnapshot(
          d as DocumentSnapshot<Map<String, dynamic>>))
          .toList();

      final completed = payments.where((p) => p.status == 'completed').toList();
      final cashCompleted = completed.where((p) => p.isCash).toList();
      final stripeDone = completed.where((p) => p.isStripe).toList();
      final pendingCash =
      payments.where((p) => p.isCash && p.status == 'pending').toList();

      double totalEarnings = completed.fold(0, (s, p) => s + p.amount);
      double cashEarnings = cashCompleted.fold(0, (s, p) => s + p.amount);
      double stripeEarnings = stripeDone.fold(0, (s, p) => s + p.amount);
      double pendingCashAmt = pendingCash.fold(0, (s, p) => s + p.amount);

      // Platform fee — reuse paymentsSnap docs instead of re-fetching each one.
      final paymentDataById = {
        for (final d in paymentsSnap.docs) d.id: d.data(),
      };
      double platformFees = 0;
      double netEarnings = 0;
      for (final p in completed) {
        final data = paymentDataById[p.id];
        final fee = (data?['platformFee'] as num?)?.toDouble() ??
            PaymentService.calcPlatformFee(p.amount);
        final net = (data?['workerNet'] as num?)?.toDouble() ?? (p.amount - fee);
        platformFees += fee;
        netEarnings += net;
      }

      // This month
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      double thisMonth = completed
          .where((p) =>
      p.completedAt != null &&
          p.completedAt!.toDate().isAfter(monthStart))
          .fold(0, (s, p) => s + p.amount);

      // Jobs count via accepted bids (unchanged logic)
      final acceptedJobIds = bidsSnap.docs
          .where((d) => d['status'] == 'accepted')
          .map((d) => d['jobId'] as String)
          .toList();

      int completedJobs = 0;
      int inProgressJobs = 0;
      if (acceptedJobIds.isNotEmpty) {
        for (int i = 0; i < acceptedJobIds.length; i += 10) {
          final chunk = acceptedJobIds.sublist(i,
              i + 10 > acceptedJobIds.length ? acceptedJobIds.length : i + 10);
          final snap = await _firestore
              .collection('jobs')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          for (final d in snap.docs) {
            final s = d['status'] as String? ?? '';
            if (s == 'completed') completedJobs++;
            if (s == 'in-progress') inProgressJobs++;
          }
        }
      }

      // Rating — reuse workerDoc fetched above instead of a separate .get().
      String ratingText = 'N/A';
      if (workerDoc.exists) {
        final ratings = workerDoc.data()?['ratings'] as Map<String, dynamic>?;
        final avgRating = ratings?['average'] as num?;
        final totalReviews = ratings?['totalReviews'] as int? ?? 0;
        if (avgRating != null && avgRating > 0 && totalReviews > 0) {
          ratingText = avgRating.toDouble().toStringAsFixed(1);
        }
      }

      return {
        'bidsPlaced': totalBids,
        'jobsWon': acceptedBids,
        'completedJobs': completedJobs,
        'inProgressJobs': inProgressJobs,
        'totalEarnings': totalEarnings,
        'platformFeesPaid': platformFees,
        'netEarnings': netEarnings,
        'cashEarnings': cashEarnings,
        'stripeEarnings': stripeEarnings,
        'pendingCash': pendingCashAmt,
        'thisMonthEarnings': thisMonth,
        'rating': ratingText,
      };
    } catch (e) {
      debugPrint('Error fetching worker stats: $e');
      return {
        'bidsPlaced': 0,
        'jobsWon': 0,
        'completedJobs': 0,
        'inProgressJobs': 0,
        'totalEarnings': 0.0,
        'platformFeesPaid': 0.0,
        'netEarnings': 0.0,
        'cashEarnings': 0.0,
        'stripeEarnings': 0.0,
        'pendingCash': 0.0,
        'thisMonthEarnings': 0.0,
        'rating': 'N/A',
      };
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  void _showJobDetails(JobModel job) {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => job_details.WorkerJobDetailsScreen(
            job: job,
            workerId: _workerId,
            workerCategory: _workerCategory,
            onBidPlaced: () => setState(() {}),
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

  String _getBidStatusText(String s) {
    switch (s) {
      case 'accepted':
        return 'bid.status_accepted'.tr();
      case 'pending':
        return 'bid.status_pending'.tr();
      case 'rejected':
        return 'bid.status_rejected'.tr();
      default:
        return s;
    }
  }

  Color _getBidStatusColor(String s) {
    switch (s) {
      case 'accepted':
        return CColors.success;
      case 'pending':
        return CColors.warning;
      case 'rejected':
        return CColors.error;
      default:
        return CColors.grey;
    }
  }

  IconData _getBidStatusIcon(String s) {
    switch (s) {
      case 'accepted':
        return Icons.check_circle_rounded;
      case 'pending':
        return Icons.access_time_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.help_rounded;
    }
  }

  // ── Pages list ────────────────────────────────────────────────────

  List<Widget> _getPages() {
    return [
      FindJobsScreen(
          scrollController: _findJobsScrollController, showAppBar: false),
      MyBidsScreen(
          scrollController: _myBidsScrollController, showAppBar: false),
      _buildHomePage(),
      WorkerChatInboxScreen(
          scrollController: _chatScrollController,
          showAppBar: false,
          workerId: _workerId),
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
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: WorkerDashboardHeader(
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
                // ── Hero earnings banner ───────────────────────
                _buildEarningsBanner(context),
                const SizedBox(height: 16),

                // ── 4-stat row ─────────────────────────────────
                _buildStatsRow(context),
                const SizedBox(height: 20),

                // ── Earnings chart + breakdown combined ────────
                _buildSectionLabel(
                    context, 'dashboard.performance_overview'.tr()),
                const SizedBox(height: 10),
                _buildEarningsCard(context),
                const SizedBox(height: 20),

                // ── Recent payments ────────────────────────────
                _buildSectionLabel(context, 'Recent Payments'),
                const SizedBox(height: 10),
                _buildRecentPayments(context),
                const SizedBox(height: 20),

                // ── Available jobs ─────────────────────────────
                _buildSectionLabelWithAction(
                    context,
                    'dashboard.available_jobs'.tr(),
                    'common.view_all'.tr(),
                    _showAllJobs),
                const SizedBox(height: 10),
                _buildJobFeed(limit: 3),
                const SizedBox(height: 20),

                // ── Recent bids ────────────────────────────────
                _buildSectionLabelWithAction(context, 'bid.recent_bids'.tr(),
                    'common.view_all'.tr(), _showAllBids),
                const SizedBox(height: 10),
                _buildMyBidsList(limit: 3),
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

  // ── Hero earnings banner (torn-card design) ──────────────────────

  Widget _buildEarningsBanner(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _workerStatsFuture ??= _fetchWorkerStats(),
      builder: (context, snap) {
        final s = snap.data ?? {};
        final net = (s['netEarnings'] as double?) ?? 0;
        final monthly = (s['thisMonthEarnings'] as double?) ?? 0;
        final rating = s['rating']?.toString() ?? 'N/A';
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
                  loading ? '—' : _formatCurrency(net),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  'Net Earnings this month: ${_formatCurrency(monthly)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _showAllJobs,
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('Find Jobs',
                        style: TextStyle(
                            color: CColors.secondary,
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
                bottom: -24,
                right: -40,
                left: 40,
                child: Image.asset(
                  'assets/images/Pipeline-maintenance-amico.png',
                  height: 250,
                  fit: BoxFit.contain,
                ),
              ),
              Positioned(
                top: 12,
                right: 85,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: CColors.secondary.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_rounded,
                        color: Colors.amber, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      loading ? '…' : rating,
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
      future: _workerStatsFuture ??= _fetchWorkerStats(),
      builder: (context, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final s = snap.data ?? {};
        final items = [
          {
            'label': 'Bids',
            'value': loading ? '…' : '${s['bidsPlaced'] ?? 0}',
            'icon': Icons.gavel_rounded,
            'color': CColors.primary
          },
          {
            'label': 'Won',
            'value': loading ? '…' : '${s['jobsWon'] ?? 0}',
            'icon': Icons.emoji_events_rounded,
            'color': CColors.success
          },
          {
            'label': 'Active',
            'value': loading ? '…' : '${s['inProgressJobs'] ?? 0}',
            'icon': Icons.autorenew_rounded,
            'color': CColors.warning
          },
          {
            'label': 'Done',
            'value': loading ? '…' : '${s['completedJobs'] ?? 0}',
            'icon': Icons.check_circle_rounded,
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
      showTopBorder: true, // ADDED
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

  // ── Earnings breakdown card ───────────────────────────────────────

  Widget _buildEarningsCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<Map<String, dynamic>>(
      future: _workerStatsFuture ??= _fetchWorkerStats(),
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;
        final s = snap.data ?? {};

        final total = (s['totalEarnings'] as double?) ?? 0;
        final fee = (s['platformFeesPaid'] as double?) ?? 0;
        final cash = (s['cashEarnings'] as double?) ?? 0;
        final stripe = (s['stripeEarnings'] as double?) ?? 0;
        final pending = (s['pendingCash'] as double?) ?? 0;

        if (isLoading) {
          return const SizedBox(
              height: 80, child: Center(child: CircularProgressIndicator()));
        }

        return AppCard(
          showTopBorder: true, // ADDED
          elevation: isDark ? 0 : 2,
          margin: EdgeInsets.zero,
          bodyPadding: const EdgeInsets.all(16),
          body: Column(children: [
            _earningRow(context, isDark,
                icon: Icons.receipt_long_rounded,
                color: CColors.info,
                label: 'Gross',
                value: _formatCurrency(total)),
            _divider(isDark),
            _earningRow(context, isDark,
                icon: Icons.storefront_rounded,
                color: CColors.error,
                label:
                'Platform Fee (${PaymentService.platformFeePercent.toStringAsFixed(0)}%)',
                value: '- ${_formatCurrency(fee)}'),
            _divider(isDark),
            _earningRow(context, isDark,
                icon: Icons.credit_card_rounded,
                color: CColors.primary,
                label: 'Online (Stripe)',
                value: _formatCurrency(stripe)),
            _divider(isDark),
            _earningRow(context, isDark,
                icon: Icons.payments_outlined,
                color: CColors.success,
                label: 'Cash Received',
                value: _formatCurrency(cash)),
            if (pending > 0) ...[
              _divider(isDark),
              _earningRow(context, isDark,
                  icon: Icons.hourglass_top_rounded,
                  color: CColors.warning,
                  label: 'Cash Pending',
                  value: _formatCurrency(pending),
                  highlight: true),
            ],
          ]),
        );
      },
    );
  }

  Widget _earningRow(
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
          return AppCard(
            showTopBorder: true, // ADDED
            margin: EdgeInsets.zero,
            elevation: 0,
            bodyPadding: const EdgeInsets.all(CSizes.lg),
            body: Center(
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
        ? CColors.success
        : (p.isCash ? CColors.warning : CColors.error);
    final icon = p.isCash ? Icons.payments_outlined : Icons.credit_card_rounded;

    return AppCard(
      showTopBorder: true, // ADDED
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
                  color: isCompleted ? CColors.success : CColors.warning)),
          if (p.completedAt != null)
            Text(timeago.format(p.completedAt!.toDate()),
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

  // ── Section header kept for disputes section ─────────────────────

  // ── Disputes section ──────────────────────────────────────────────

  Widget _buildDisputesSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return StreamBuilder<List<DisputeModel>>(
      stream: DisputeService()
          .userDisputesStream(userId: _workerId, role: 'worker'),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
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
      showTopBorder: true, // ADDED
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

  // ── Filter chips

  Widget _buildFilterChips() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _filterOptions.asMap().entries.map((entry) {
          final idx = entry.key;
          final label = entry.value;
          final isSelected = _selectedFilter == idx;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(label, style: TextStyle(fontSize: isUrdu ? 16 : 14)),
              selected: isSelected,
              onSelected: (s) {
                if (s) setState(() => _selectedFilter = idx);
              },
              selectedColor: CColors.primary,
              labelStyle: TextStyle(
                  color: isSelected
                      ? CColors.white
                      : (isDark ? CColors.white : CColors.textPrimary),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
              backgroundColor:
              isDark ? CColors.darkContainer : CColors.softGrey,
              shape: StadiumBorder(
                  side: BorderSide(
                      color: isSelected
                          ? CColors.primary
                          : (isDark ? CColors.darkGrey : CColors.grey))),
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
        .where('status', isEqualTo: 'open')
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
    return AppCard(
      showTopBorder: true, // ADDED
      margin: const EdgeInsets.only(bottom: CSizes.md),
      elevation: 2,
      onTap: () => _showJobDetails(job),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Text(job.title,
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: isUrdu ? 18 : 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: CColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CColors.info)),
            child: Text(job.category,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: CColors.info,
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
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium!
                        .copyWith(
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

  Widget _buildMyBidsList({int? limit}) {
    if (_workerId.isEmpty)
      return _buildEmptyState('errors.login_to_view_bids'.tr());

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('bids')
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
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    final statusColor = _getBidStatusColor(bid.status);

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('jobs').doc(bid.jobId).get(),
      builder: (context, jobSnap) {
        if (jobSnap.connectionState == ConnectionState.waiting)
          return ListTile(title: Text('common.loading'.tr()));
        if (!jobSnap.hasData || !jobSnap.data!.exists)
          return ListTile(title: Text('job.job_not_found'.tr()));

        final jobData = jobSnap.data!.data() as Map<String, dynamic>;
        final jobTitle = jobData['title'] ?? 'job.unknown'.tr();

        return AppCard(
          showTopBorder: true, // ADDED
          margin: const EdgeInsets.only(bottom: CSizes.sm),
          elevation: isDark ? 0 : 1.5,
          body: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle),
              child: Icon(_getBidStatusIcon(bid.status),
                  color: statusColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(jobTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall!.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: isUrdu ? 16 : 14)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: statusColor.withValues(alpha: 0.4))),
                        child: Text(_getBidStatusText(bid.status),
                            style: TextStyle(
                                color: statusColor,
                                fontSize: isUrdu ? 12 : 11,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Text(_formatCurrency(bid.amount),
                          style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? CColors.textWhite
                                  : CColors.textPrimary)),
                    ]),
                  ],
                )),
            Text(timeago.format(bid.createdAt.toDate()),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall!
                    .copyWith(color: CColors.textSecondary)),
          ]),
        );
      },
    );
  }

  Widget _buildLoadingJobs() => SizedBox(
      height: 150,
      child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CircularProgressIndicator(color: CColors.primary),
            const SizedBox(height: CSizes.md),
            Text('common.loading_jobs'.tr()),
          ])));

  Widget _buildLoadingBids() => SizedBox(
      height: 150,
      child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CircularProgressIndicator(color: CColors.primary),
            const SizedBox(height: CSizes.md),
            Text('common.loading_bids'.tr()),
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
    final currentPageIndex = ref.watch(workerPageIndexProvider);

    ScrollController activeController;
    switch (currentPageIndex) {
      case 0:
        activeController = _findJobsScrollController;
        break;
      case 1:
        activeController = _myBidsScrollController;
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
      extendBody: true,
      extendBodyBehindAppBar: false,
      body: IndexedStack(index: currentPageIndex, children: _getPages()),
      bottomNavigationBar: CurvedNavBar(
        currentIndex: currentPageIndex,
        onTap: (index) {
          ref.read(workerPageIndexProvider.notifier).state = index;
          ref.read(navBarVisibilityProvider.notifier).state = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            switch (index) {
              case 0:
                if (_findJobsScrollController.hasClients)
                  _findJobsScrollController.jumpTo(0);
                break;
              case 1:
                if (_myBidsScrollController.hasClients)
                  _myBidsScrollController.jumpTo(0);
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
        userRole: 'worker',
        scrollController: activeController,
      ),
    );
  }
}

// ── Torn-card widget ──────────────────────────────────────────────────────────
// Matches the reference UI: dark left half + orange right half with a ragged
// zigzag tear edge running vertically at ~55 % of the card width.

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
/// Clips the LEFT (dark) panel. The right boundary follows a sharp zigzag
/// that mimics a torn-paper edge, matching the reference screenshot.
class _LeftTearClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    // Centre of the tear — slightly past midpoint so the illustration has room
    final tx = size.width * 0.54;
    const amplitude = 13.0; // how far each tooth juts in/out

    final path = Path()
      ..moveTo(0, 0)
    // Top edge → tear start
      ..lineTo(tx - amplitude, 0)
    // Zigzag teeth down the tear edge
      ..lineTo(tx + amplitude, size.height * 0.10)
      ..lineTo(tx - amplitude, size.height * 0.22)
      ..lineTo(tx + amplitude, size.height * 0.34)
      ..lineTo(tx - amplitude, size.height * 0.46)
      ..lineTo(tx + amplitude, size.height * 0.58)
      ..lineTo(tx - amplitude, size.height * 0.70)
      ..lineTo(tx + amplitude, size.height * 0.82)
      ..lineTo(tx - amplitude, size.height * 0.93)
      ..lineTo(tx, size.height)
    // Bottom-left corner
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(_LeftTearClipper old) => false;
}