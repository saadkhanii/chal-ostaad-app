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
import '../../core/routes/app_routes.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/category_service.dart';
import '../../core/services/worker_service.dart';
import '../../shared/widgets/dashboard_drawer.dart';
import '../../shared/widgets/curved_nav_bar.dart';
import '../profile/worker_profile_screen.dart';

// State providers
final workerLoadingProvider = StateProvider<bool>((ref) => true);
final workerPageIndexProvider = StateProvider<int>((ref) => 2);

class WorkerDashboard extends ConsumerStatefulWidget {
  const WorkerDashboard({super.key});

  @override
  ConsumerState<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends ConsumerState<WorkerDashboard>
    with TickerProviderStateMixin {
  // Fields — NO .tr() at declaration; all initialised in initState after mount
  String _userName = '';
  String _workerId = '';
  String _workerCategory = '';
  String _photoBase64 = '';
  int _selectedFilter = 0;

  List<String> _filterOptions = [];
  List<String> _morningQuotes = [];
  List<String> _afternoonQuotes = [];
  List<String> _eveningQuotes = [];

  // Scroll controllers — one per page
  final ScrollController _findJobsScrollController = ScrollController();
  final ScrollController _myBidsScrollController = ScrollController();
  final ScrollController _homeScrollController = ScrollController();
  final ScrollController _chatScrollController = ScrollController();
  final ScrollController _profileScrollController = ScrollController();

  final WorkerService _workerService = WorkerService();
  final BidService _bidService = BidService();
  final CategoryService _categoryService = CategoryService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _workerCategoryName = '';

  // Animation — matches client dashboard
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // All .tr() calls deferred until widget is mounted & context is valid
      setState(() {
        _userName = 'dashboard.worker'.tr();
        _filterOptions = [
          'dashboard.all_jobs'.tr(),
          'dashboard.my_category'.tr(),
        ];
        _morningQuotes = [
          'quote.morning_1'.tr(),
          'quote.morning_2'.tr(),
          'quote.morning_3'.tr(),
        ];
        _afternoonQuotes = [
          'quote.afternoon_1'.tr(),
          'quote.afternoon_2'.tr(),
          'quote.afternoon_3'.tr(),
        ];
        _eveningQuotes = [
          'quote.evening_1'.tr(),
          'quote.evening_2'.tr(),
          'quote.evening_3'.tr(),
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

  // ─── Data loading ──────────────────────────────────────────────────────────

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
                workerDoc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
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

  Future<Map<String, dynamic>> _fetchWorkerStats() async {
    if (_workerId.isEmpty) {
      return {'bidsPlaced': 0, 'jobsWon': 0, 'earnings': 0.0, 'rating': 'N/A'};
    }
    try {
      final bidsSnapshot = await _firestore
          .collection('bids')
          .where('workerId', isEqualTo: _workerId)
          .get();

      final bids = bidsSnapshot.docs;
      final totalBids = bids.length;
      final acceptedBids =
          bids.where((doc) => doc['status'] == 'accepted').length;

      double earnings = 0.0;
      for (final doc in bids.where((d) => d['status'] == 'accepted')) {
        final amount = doc['amount'];
        if (amount is num) earnings += amount.toDouble();
      }

      String ratingText = 'N/A';
      try {
        final workerDoc =
        await _firestore.collection('workers').doc(_workerId).get();
        if (workerDoc.exists) {
          final data = workerDoc.data() as Map<String, dynamic>?;
          final ratings = data?['ratings'] as Map<String, dynamic>?;
          final avgRating = ratings?['average'] as num?;
          final totalReviews = ratings?['totalReviews'] as int? ?? 0;
          if (avgRating != null && avgRating > 0 && totalReviews > 0) {
            ratingText = avgRating.toDouble().toStringAsFixed(1);
          }
        }
      } catch (e) {
        debugPrint('Error fetching worker rating: $e');
      }

      return {
        'bidsPlaced': totalBids,
        'jobsWon': acceptedBids,
        'earnings': earnings,
        'rating': ratingText,
      };
    } catch (e) {
      debugPrint('Error fetching worker stats: $e');
      return {'bidsPlaced': 0, 'jobsWon': 0, 'earnings': 0.0, 'rating': 'N/A'};
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _showJobDetails(JobModel job) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => job_details.WorkerJobDetailsScreen(
          job: job,
          workerId: _workerId,
          workerCategory: _workerCategory,
          onBidPlaced: () => setState(() {}),
        ),
      ),
    );
  }

  void _showAllJobs() => ref.read(workerPageIndexProvider.notifier).state = 0;
  void _showAllBids() => ref.read(workerPageIndexProvider.notifier).state = 1;

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'dashboard.good_morning'.tr();
    if (hour < 17) return 'dashboard.good_afternoon'.tr();
    return 'dashboard.good_evening'.tr();
  }

  String _getMotivationalQuote() {
    final hour = DateTime.now().hour;
    final random = DateTime.now().millisecond % 3;
    if (hour < 12) return _morningQuotes.isNotEmpty ? _morningQuotes[random] : '';
    if (hour < 17) return _afternoonQuotes.isNotEmpty ? _afternoonQuotes[random] : '';
    return _eveningQuotes.isNotEmpty ? _eveningQuotes[random] : '';
  }

  String _formatCurrency(double amount) {
    if (amount == 0) return 'Rs 0';
    if (amount >= 10000000) return 'Rs ${(amount / 10000000).toStringAsFixed(1)}Cr';
    if (amount >= 100000) return 'Rs ${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return 'Rs ${(amount / 1000).toStringAsFixed(1)}k';
    return 'Rs ${amount.toStringAsFixed(0)}';
  }

  String _getBidStatusText(String status) {
    switch (status) {
      case 'accepted': return 'bid.status_accepted'.tr();
      case 'pending': return 'bid.status_pending'.tr();
      case 'rejected': return 'bid.status_rejected'.tr();
      default: return status;
    }
  }

  Color _getBidStatusColor(String status) {
    switch (status) {
      case 'accepted': return CColors.success;
      case 'pending': return CColors.warning;
      case 'rejected': return CColors.error;
      default: return CColors.grey;
    }
  }

  IconData _getBidStatusIcon(String status) {
    switch (status) {
      case 'accepted': return Icons.check_circle_rounded;
      case 'pending': return Icons.access_time_rounded;
      case 'rejected': return Icons.cancel_rounded;
      default: return Icons.help_rounded;
    }
  }

  // ─── Pages list ───────────────────────────────────────────────────────────

  List<Widget> _getPages() {
    return [
      FindJobsScreen(scrollController: _findJobsScrollController, showAppBar: false),
      MyBidsScreen(scrollController: _myBidsScrollController, showAppBar: false),
      _buildHomePage(),
      WorkerChatInboxScreen(scrollController: _chatScrollController, showAppBar: false, workerId: _workerId),
      WorkerProfileScreen(showAppBar: false),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  HOME PAGE
  // ═══════════════════════════════════════════════════════════════════════════

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
              child: Column(
                children: [
                  WorkerDashboardHeader(
                    userName: _userName,
                    photoUrl: _photoBase64,
                    onNotificationTap: () =>
                        Navigator.pushNamed(context, AppRoutes.notifications),
                  ),
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildWelcomeSection(context),
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildQuickActions(context),
                  const SizedBox(height: CSizes.spaceBtwSections),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
                    child: _buildOpportunityCard(context),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(context, 'dashboard.performance_overview'.tr(), showAction: false),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildStatsGrid(context),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(context, 'dashboard.recent_activity'.tr(), showAction: false),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildRecentActivity(),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSuggestedActions(),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(
                  context,
                  'dashboard.available_jobs'.tr(),
                  actionText: 'common.view_all'.tr(),
                  onAction: _showAllJobs,
                ),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildFilterChips(),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildJobFeed(limit: 3),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(
                  context,
                  'bid.recent_bids'.tr(),
                  actionText: 'common.view_all'.tr(),
                  onAction: _showAllBids,
                ),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildMyBidsList(limit: 3),
                const SizedBox(height: CSizes.spaceBtwSections * 2),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Welcome section ────────────────────────────────────────────────────────

  Widget _buildWelcomeSection(BuildContext context) {
    final isUrdu = context.locale.languageCode == 'ur';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CColors.primary, CColors.primary.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        boxShadow: [
          BoxShadow(
            color: CColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_getGreeting()},',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: CColors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  _userName.split(' ').first,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: CColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: isUrdu ? 26 : 24,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: CColors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.format_quote, size: 14, color: CColors.white.withOpacity(0.8)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _getMotivationalQuote(),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: CColors.white,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CColors.white.withOpacity(0.2),
              border: Border.all(color: CColors.white, width: 2),
            ),
            child: const Icon(Icons.handyman_rounded, color: CColors.white, size: 40),
          ),
        ],
      ),
    );
  }

  // ── Quick actions ──────────────────────────────────────────────────────────

  Widget _buildQuickActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'dashboard.quick_actions'.tr(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: CSizes.sm),
          Row(
            children: [
              Expanded(
                child: _buildActionCard(context,
                    icon: Icons.search_rounded,
                    label: 'dashboard.find_jobs'.tr(),
                    color: CColors.success,
                    onTap: _showAllJobs),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(context,
                    icon: Icons.gavel_rounded,
                    label: 'dashboard.my_bids'.tr(),
                    color: CColors.info,
                    onTap: _showAllBids),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(context,
                    icon: Icons.chat_rounded,
                    label: 'dashboard.messages'.tr(),
                    color: CColors.warning,
                    onTap: () => ref.read(workerPageIndexProvider.notifier).state = 3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
      BuildContext context, {
        required IconData icon,
        required String label,
        required Color color,
        required VoidCallback onTap,
      }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? CColors.darkContainer : CColors.white,
            borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Opportunity / hero card ────────────────────────────────────────────────

  Widget _buildOpportunityCard(BuildContext context) {
    final isUrdu = context.locale.languageCode == 'ur';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CColors.primary.withOpacity(0.95), CColors.secondary.withOpacity(0.95)],
        ),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        boxShadow: [
          BoxShadow(color: CColors.primary.withOpacity(0.4), blurRadius: 25, offset: const Offset(0, 10)),
          BoxShadow(color: CColors.secondary.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: CColors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: CColors.white.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.rocket_launch_rounded, size: 16, color: CColors.white),
                const SizedBox(width: 8),
                Text(
                  'dashboard.bidding_platform'.tr(),
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: CColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: isUrdu ? 12 : 11,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'dashboard.find_next_project'.tr(),
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              color: CColors.white,
              fontWeight: FontWeight.w900,
              fontSize: isUrdu ? 26 : 24,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'dashboard.bidding_description'.tr(),
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: CColors.white.withOpacity(0.95),
              height: 1.6,
              fontSize: isUrdu ? 16 : 15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: CSizes.lg),
          // CTA button — mirrors client's "Post Now" button
          ElevatedButton(
            onPressed: _showAllJobs,
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.white,
              foregroundColor: CColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text('dashboard.browse_jobs'.tr(),
                style: TextStyle(fontSize: isUrdu ? 16 : 14)),
          ),
        ],
      ),
    );
  }

  // ── Section header ─────────────────────────────────────────────────────────

  Widget _buildSectionHeader(BuildContext context, String title,
      {String? actionText, VoidCallback? onAction, bool showAction = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall!.copyWith(
            fontWeight: FontWeight.w900,
            color: isDark ? CColors.textWhite : CColors.textPrimary,
            fontSize: isUrdu ? 24 : 22,
            letterSpacing: -0.5,
          ),
        ),
        if (showAction && actionText != null && onAction != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                actionText,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: CColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: isUrdu ? 16 : 14,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Stats grid (with color per stat + trend badge) ─────────────────────────

  Widget _buildStatsGrid(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchWorkerStats(),
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final stats = snapshot.data ??
            {'bidsPlaced': 0, 'jobsWon': 0, 'earnings': 0.0, 'rating': 'N/A'};

        final items = [
          {
            'label': 'dashboard.bids_placed'.tr(),
            'value': isLoading ? '...' : '${stats['bidsPlaced']}',
            'trend': '+5%',
            'icon': Icons.gavel_rounded,
            'color': CColors.primary,
          },
          {
            'label': 'dashboard.jobs_won'.tr(),
            'value': isLoading ? '...' : '${stats['jobsWon']}',
            'trend': '+8%',
            'icon': Icons.emoji_events_rounded,
            'color': CColors.success,
          },
          {
            'label': 'dashboard.earnings'.tr(),
            'value': isLoading ? '...' : _formatCurrency(stats['earnings'] as double),
            'trend': '+12%',
            'icon': Icons.account_balance_wallet_rounded,
            'color': CColors.info,
          },
          {
            'label': 'dashboard.rating'.tr(),
            'value': isLoading ? '...' : '${stats['rating']}',
            'trend': '',
            'icon': Icons.star_rounded,
            'color': CColors.warning,
          },
        ];

        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: items
              .map((item) => _buildStatCard(
            context,
            label: item['label'] as String,
            value: item['value'] as String,
            trend: item['trend'] as String,
            icon: item['icon'] as IconData,
            color: item['color'] as Color,
          ))
              .toList(),
        );
      },
    );
  }

  Widget _buildStatCard(
      BuildContext context, {
        required String label,
        required String value,
        required String trend,
        required IconData icon,
        required Color color,
      }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: Theme.of(context).textTheme.titleMedium!.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: isUrdu ? 18 : 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (trend.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: CColors.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          trend,
                          style: const TextStyle(
                              color: CColors.success,
                              fontSize: 9,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    fontSize: isUrdu ? 12 : 11,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Recent activity ────────────────────────────────────────────────────────

  Widget _buildRecentActivity() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    if (_workerId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('bids')
          .where('workerId', isEqualTo: _workerId)
          .orderBy('createdAt', descending: true)
          .limit(4)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('dashboard.no_recent_activity'.tr());
        }

        return Container(
          decoration: BoxDecoration(
            color: isDark ? CColors.darkContainer : CColors.white,
            borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: snapshot.data!.docs.length,
            separatorBuilder: (_, __) => Divider(
                height: 1,
                color: isDark ? Colors.grey[800] : Colors.grey[200]),
            itemBuilder: (context, index) {
              final bid = BidModel.fromSnapshot(snapshot.data!.docs[index]
              as DocumentSnapshot<Map<String, dynamic>>);
              final statusColor = _getBidStatusColor(bid.status);
              return ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      shape: BoxShape.circle),
                  child: Icon(_getBidStatusIcon(bid.status),
                      color: statusColor, size: 20),
                ),
                title: FutureBuilder<DocumentSnapshot>(
                  future: _firestore.collection('jobs').doc(bid.jobId).get(),
                  builder: (context, jobSnap) {
                    final title = (jobSnap.data?.data()
                    as Map<String, dynamic>?)?['title'] ??
                        'job.unknown'.tr();
                    return Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
                subtitle: Text(
                  '${_getBidStatusText(bid.status)} · ${_formatCurrency(bid.amount)}',
                  style: TextStyle(
                      color: statusColor,
                      fontSize: isUrdu ? 13 : 12,
                      fontWeight: FontWeight.w500),
                ),
                trailing: Text(
                  timeago.format(bid.createdAt.toDate()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ── Suggested actions ──────────────────────────────────────────────────────

  Widget _buildSuggestedActions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    final tips = [
      {
        'icon': Icons.person_pin_rounded,
        'color': CColors.primary,
        'title': 'dashboard.tip_complete_profile'.tr(),
        'subtitle': 'dashboard.tip_complete_profile_desc'.tr(),
        'onTap': () => ref.read(workerPageIndexProvider.notifier).state = 4,
      },
      {
        'icon': Icons.notifications_active_rounded,
        'color': CColors.warning,
        'title': 'dashboard.tip_new_jobs'.tr(),
        'subtitle': 'dashboard.tip_new_jobs_desc'.tr(),
        'onTap': _showAllJobs,
      },
      {
        'icon': Icons.trending_up_rounded,
        'color': CColors.success,
        'title': 'dashboard.tip_win_bids'.tr(),
        'subtitle': 'dashboard.tip_win_bids_desc'.tr(),
        'onTap': _showAllBids,
      },
    ];

    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color: isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_rounded, color: CColors.warning, size: 20),
              const SizedBox(width: 8),
              Text(
                'dashboard.suggested_actions'.tr(),
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: isUrdu ? 18 : 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: CSizes.md),
          ...tips.map((tip) => _buildTipTile(
            context,
            icon: tip['icon'] as IconData,
            color: tip['color'] as Color,
            title: tip['title'] as String,
            subtitle: tip['subtitle'] as String,
            onTap: tip['onTap'] as VoidCallback,
          )),
        ],
      ),
    );
  }

  Widget _buildTipTile(
      BuildContext context, {
        required IconData icon,
        required Color color,
        required String title,
        required String subtitle,
        required VoidCallback onTap,
      }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CSizes.cardRadiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium!
                          .copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall!
                          .copyWith(color: CColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: CColors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  // ── Filter chips ───────────────────────────────────────────────────────────

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
              onSelected: (selected) {
                if (selected) setState(() => _selectedFilter = idx);
              },
              selectedColor: CColors.primary,
              labelStyle: TextStyle(
                color: isSelected
                    ? CColors.white
                    : (isDark ? CColors.white : CColors.textPrimary),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              backgroundColor: isDark ? CColors.darkContainer : CColors.softGrey,
              shape: StadiumBorder(
                side: BorderSide(
                  color: isSelected
                      ? CColors.primary
                      : (isDark ? CColors.darkGrey : CColors.grey),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Job feed ───────────────────────────────────────────────────────────────

  Widget _buildJobFeed({int? limit}) {
    if (_workerId.isEmpty) return _buildEmptyState('errors.login_to_view_jobs'.tr());

    Query query = _firestore
        .collection('jobs')
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt', descending: true);

    if (_selectedFilter == 1 && _workerCategoryName.isNotEmpty) {
      query = query.where('category', isEqualTo: _workerCategoryName);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return _buildLoadingJobs();
        if (snapshot.hasError) {
          return _buildEmptyState('${'errors.load_jobs_failed'.tr()}: ${snapshot.error}');
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('job.no_jobs_available'.tr());
        }

        int itemCount = snapshot.data!.docs.length;
        if (limit != null && limit < itemCount) itemCount = limit;

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final job = JobModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
            return _buildJobCard(job);
          },
        );
      },
    );
  }

  Widget _buildJobCard(JobModel job) {
    final isUrdu = context.locale.languageCode == 'ur';
    return Card(
      margin: const EdgeInsets.only(bottom: CSizes.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.cardRadiusMd)),
      elevation: 2,
      child: InkWell(
        onTap: () => _showJobDetails(job),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        child: Padding(
          padding: const EdgeInsets.all(CSizes.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      job.title,
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: isUrdu ? 18 : 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: CColors.info.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: CColors.info),
                    ),
                    child: Text(
                      job.category,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: CColors.info,
                        fontWeight: FontWeight.bold,
                        fontSize: isUrdu ? 12 : 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CSizes.sm),
              Text(
                job.description,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(fontSize: isUrdu ? 16 : 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: CSizes.md),
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: CColors.darkGrey),
                  const SizedBox(width: 4),
                  Text(
                    timeago.format(job.createdAt.toDate()),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall!
                        .copyWith(fontSize: isUrdu ? 14 : 12),
                  ),
                  const Spacer(),
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('bids')
                        .where('jobId', isEqualTo: job.id)
                        .snapshots(),
                    builder: (context, bidSnapshot) {
                      final bidCount = bidSnapshot.data?.docs.length ?? 0;
                      return Row(
                        children: [
                          Icon(Icons.gavel, size: 16, color: CColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${'bid.total_bids'.tr()}: $bidCount',
                            style: Theme.of(context).textTheme.labelMedium!.copyWith(
                              color: CColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: isUrdu ? 14 : 12,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── My bids list ───────────────────────────────────────────────────────────

  Widget _buildMyBidsList({int? limit}) {
    if (_workerId.isEmpty) return _buildEmptyState('errors.login_to_view_bids'.tr());

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('bids')
          .where('workerId', isEqualTo: _workerId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return _buildLoadingBids();
        if (snapshot.hasError) {
          return _buildEmptyState('${'errors.load_bids_failed'.tr()}: ${snapshot.error}');
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('bid.no_bids_placed'.tr());
        }

        int itemCount = snapshot.data!.docs.length;
        if (limit != null && limit < itemCount) itemCount = limit;

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final bid = BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
            return _buildBidItem(bid);
          },
        );
      },
    );
  }

  // Upgraded bid item — styled card instead of plain ListTile
  Widget _buildBidItem(BidModel bid) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    final statusColor = _getBidStatusColor(bid.status);

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('jobs').doc(bid.jobId).get(),
      builder: (context, jobSnapshot) {
        if (jobSnapshot.connectionState == ConnectionState.waiting) {
          return ListTile(title: Text('common.loading'.tr()));
        }
        if (!jobSnapshot.hasData || !jobSnapshot.data!.exists) {
          return ListTile(title: Text('job.job_not_found'.tr()));
        }

        final jobData = jobSnapshot.data!.data() as Map<String, dynamic>;
        final jobTitle = jobData['title'] ?? 'job.unknown'.tr();

        return Card(
          margin: const EdgeInsets.only(bottom: CSizes.sm),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CSizes.cardRadiusMd)),
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(CSizes.md),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_getBidStatusIcon(bid.status),
                      color: statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        jobTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall!.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: isUrdu ? 16 : 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: statusColor.withOpacity(0.4)),
                            ),
                            child: Text(
                              _getBidStatusText(bid.status),
                              style: TextStyle(
                                  color: statusColor,
                                  fontSize: isUrdu ? 12 : 11,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatCurrency(bid.amount),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall!
                                .copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? CColors.textWhite
                                    : CColors.textPrimary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  timeago.format(bid.createdAt.toDate()),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .copyWith(color: CColors.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Loading / empty states ─────────────────────────────────────────────────

  Widget _buildLoadingJobs() {
    final isUrdu = context.locale.languageCode == 'ur';
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: CColors.primary),
          const SizedBox(height: CSizes.md),
          Text('common.loading_jobs'.tr(),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium!
                  .copyWith(fontSize: isUrdu ? 16 : 14)),
        ]),
      ),
    );
  }

  Widget _buildLoadingBids() {
    final isUrdu = context.locale.languageCode == 'ur';
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: CColors.primary),
          const SizedBox(height: CSizes.md),
          Text('common.loading_bids'.tr(),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium!
                  .copyWith(fontSize: isUrdu ? 16 : 14)),
        ]),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    final isUrdu = context.locale.languageCode == 'ur';
    return Container(
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
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: CColors.textSecondary, fontSize: isUrdu ? 16 : 14),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    final currentPageIndex = ref.watch(workerPageIndexProvider);

    ScrollController activeController;
    switch (currentPageIndex) {
      case 0: activeController = _findJobsScrollController; break;
      case 1: activeController = _myBidsScrollController; break;
      case 2: activeController = _homeScrollController; break;
      case 3: activeController = _chatScrollController; break;
      case 4: activeController = _profileScrollController; break;
      default: activeController = _homeScrollController;
    }

    return Scaffold(
      endDrawer: !isUrdu ? const DashboardDrawer() : null,
      drawer: isUrdu ? const DashboardDrawer() : null,
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: IndexedStack(index: currentPageIndex, children: _getPages()),
      bottomNavigationBar: CurvedNavBar(
        currentIndex: currentPageIndex,
        onTap: (index) {
          ref.read(workerPageIndexProvider.notifier).state = index;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            switch (index) {
              case 0: if (_findJobsScrollController.hasClients) _findJobsScrollController.jumpTo(0); break;
              case 1: if (_myBidsScrollController.hasClients) _myBidsScrollController.jumpTo(0); break;
              case 2: if (_homeScrollController.hasClients) _homeScrollController.jumpTo(0); break;
              case 3: if (_chatScrollController.hasClients) _chatScrollController.jumpTo(0); break;
              case 4: if (_profileScrollController.hasClients) _profileScrollController.jumpTo(0); break;
            }
          });
        },
        userRole: 'worker',
        scrollController: activeController,
      ),
    );
  }
}