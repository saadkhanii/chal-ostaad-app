// lib/features/client/client_dashboard.dart

import 'package:chal_ostaad/features/client/client_job_details_screen.dart';
import 'package:chal_ostaad/features/client/post_job_screen.dart';
import 'package:chal_ostaad/features/notifications/notifications_screen.dart';
import 'package:chal_ostaad/features/client/my_posted_jobs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/job_model.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/job_service.dart';
import '../../shared/widgets/dashboard_drawer.dart';
import '../../shared/widgets/curved_nav_bar.dart';
import 'client_dashboard_header.dart';

final clientLoadingProvider = StateProvider<bool>((ref) => true);
final clientPageIndexProvider = StateProvider<int>((ref) => 2);

class ClientDashboard extends ConsumerStatefulWidget {
  const ClientDashboard({super.key});

  @override
  ConsumerState<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends ConsumerState<ClientDashboard> {
  String _userName = 'dashboard.client'.tr();
  String _clientId = '';
  String _clientEmail = '';

  final ScrollController _myPostedJobsScrollController = ScrollController();
  final ScrollController _postJobScrollController = ScrollController();
  final ScrollController _homeScrollController = ScrollController();
  final ScrollController _notificationsScrollController = ScrollController();
  final ScrollController _profileScrollController = ScrollController();

  final JobService _jobService = JobService();
  final BidService _bidService = BidService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUserData());
  }

  @override
  void dispose() {
    _myPostedJobsScrollController.dispose();
    _postJobScrollController.dispose();
    _homeScrollController.dispose();
    _notificationsScrollController.dispose();
    _profileScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userUid = prefs.getString('user_uid');
      String? userName = prefs.getString('user_name');
      String? userEmail = prefs.getString('user_email');

      if (userUid != null) {
        try {
          final userDoc = await _firestore.collection('users').doc(userUid).get();
          if (userDoc.exists && userDoc.data() != null) {
            final data = userDoc.data()!;
            final fetchedName = data['fullName'] ?? data['name'] ?? data['userName'] ?? userName ?? 'dashboard.client'.tr();
            final fetchedEmail = data['email'] ?? userEmail ?? '';
            userName = fetchedName;
            userEmail = fetchedEmail;
            await prefs.setString('user_name', fetchedName);
            await prefs.setString('user_email', fetchedEmail);
          }
        } catch (e) {
          debugPrint('Error fetching user data: $e');
        }

        if (mounted) {
          setState(() {
            _clientId = userUid;
            _userName = userName ?? 'dashboard.client'.tr();
            _clientEmail = userEmail ?? '';
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

  void _showJobDetails(JobModel job) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => ClientJobDetailsScreen(job: job)));
  }

  String _formatCurrency(double amount) {
    if (amount == 0) return 'Rs 0';
    if (amount >= 10000000) return 'Rs ${(amount / 10000000).toStringAsFixed(1)}Cr';
    if (amount >= 100000) return 'Rs ${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return 'Rs ${(amount / 1000).toStringAsFixed(1)}k';
    return 'Rs ${amount.toStringAsFixed(0)}';
  }

  // ============== UI COMPONENTS ==============

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
                const Icon(Icons.business_center_rounded, size: 16, color: CColors.white),
                const SizedBox(width: 8),
                Text(
                  'dashboard.job_platform'.tr(),
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: CColors.white, fontWeight: FontWeight.w800,
                    fontSize: isUrdu ? 12 : 11, letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'dashboard.post_job'.tr(),
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              color: CColors.white, fontWeight: FontWeight.w900,
              fontSize: isUrdu ? 26 : 24, height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'dashboard.find_workers'.tr(),
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: CColors.white.withOpacity(0.95), height: 1.6, fontSize: isUrdu ? 16 : 15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: CSizes.lg),
          ElevatedButton(
            onPressed: () => ref.read(clientPageIndexProvider.notifier).state = 1,
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.white,
              foregroundColor: CColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text('dashboard.post_now'.tr(), style: TextStyle(fontSize: isUrdu ? 16 : 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, {
    String? actionText, VoidCallback? onAction, bool showAction = true,
  }) {
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
                  color: CColors.primary, fontWeight: FontWeight.w700, fontSize: isUrdu ? 16 : 14,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatsGrid(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchClientStats(),
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final stats = snapshot.data ?? {'postedJobs': 0, 'activeJobs': 0, 'completedJobs': 0, 'totalSpent': 0.0};
        final items = [
          {'label': 'dashboard.posted_jobs'.tr(), 'value': isLoading ? '...' : '${stats['postedJobs']}', 'icon': Icons.work_outline},
          {'label': 'dashboard.active_jobs'.tr(), 'value': isLoading ? '...' : '${stats['activeJobs']}', 'icon': Icons.work},
          {'label': 'dashboard.completed_jobs'.tr(), 'value': isLoading ? '...' : '${stats['completedJobs']}', 'icon': Icons.check_circle},
          {'label': 'dashboard.total_spent'.tr(), 'value': isLoading ? '...' : _formatCurrency(stats['totalSpent']), 'icon': Icons.attach_money},
        ];
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: items.map((item) => _buildStatCard(
            context, label: item['label'] as String,
            value: item['value'] as String, icon: item['icon'] as IconData,
          )).toList(),
        );
      },
    );
  }

  Widget _buildStatCard(BuildContext context, {required String label, required String value, required IconData icon}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: CColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: CColors.primary, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.bold, fontSize: isUrdu ? 18 : 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(label,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    fontSize: isUrdu ? 12 : 11,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  overflow: TextOverflow.ellipsis, maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchClientStats() async {
    if (_clientId.isEmpty) return {'postedJobs': 0, 'activeJobs': 0, 'completedJobs': 0, 'totalSpent': 0.0};
    try {
      final jobsSnapshot = await _firestore.collection('jobs').where('clientId', isEqualTo: _clientId).get();
      final jobs = jobsSnapshot.docs;
      final completedJobIds = jobs.where((doc) => doc['status'] == 'completed').map((doc) => doc.id).toList();
      double totalSpent = 0.0;
      if (completedJobIds.isNotEmpty) {
        final bidsSnapshot = await _firestore.collection('bids')
            .where('jobId', whereIn: completedJobIds).where('status', isEqualTo: 'accepted').get();
        for (var bid in bidsSnapshot.docs) {
          final amount = bid['amount'];
          if (amount is num) totalSpent += amount.toDouble();
        }
      }
      return {
        'postedJobs': jobs.length,
        'activeJobs': jobs.where((doc) => doc['status'] == 'in-progress').length,
        'completedJobs': jobs.where((doc) => doc['status'] == 'completed').length,
        'totalSpent': totalSpent,
      };
    } catch (e) {
      debugPrint('Error fetching client stats: $e');
      return {'postedJobs': 0, 'activeJobs': 0, 'completedJobs': 0, 'totalSpent': 0.0};
    }
  }

  // ✅ StreamBuilder = live bid count (same as worker dashboard)
  Widget _buildJobFeed({int? limit}) {
    if (_clientId.isEmpty) return _buildEmptyState('job.login_to_view'.tr());
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('jobs').where('clientId', isEqualTo: _clientId)
          .orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return _buildLoadingJobs();
        if (snapshot.hasError) return _buildEmptyState('${'errors.load_jobs_failed'.tr()}: ${snapshot.error}');
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildEmptyState('job.no_jobs_found'.tr());
        int itemCount = snapshot.data!.docs.length;
        if (limit != null && limit < itemCount) itemCount = limit;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            return _buildJobCard(JobModel.fromMap(doc.data() as Map<String, dynamic>, doc.id));
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
      case 'open': statusColor = CColors.success; statusText = 'job.status_open'.tr(); break;
      case 'in-progress': statusColor = CColors.warning; statusText = 'job.status_in_progress'.tr(); break;
      case 'completed': statusColor = CColors.info; statusText = 'job.status_completed'.tr(); break;
      case 'cancelled': statusColor = CColors.error; statusText = 'job.status_cancelled'.tr(); break;
      default: statusColor = CColors.grey; statusText = job.status;
    }
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
                children: [
                  Expanded(
                    child: Text(job.title,
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(
                        fontWeight: FontWeight.bold, fontSize: isUrdu ? 18 : 16,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(statusText,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: statusColor, fontWeight: FontWeight.bold, fontSize: isUrdu ? 12 : 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CSizes.sm),
              Text(job.description,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: isUrdu ? 16 : 14),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: CSizes.md),
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: CColors.darkGrey),
                  const SizedBox(width: 4),
                  Text(timeago.format(job.createdAt.toDate()),
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: isUrdu ? 14 : 12),
                  ),
                  const Spacer(),
                  // ✅ Live bid count via StreamBuilder
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('bids').where('jobId', isEqualTo: job.id).snapshots(),
                    builder: (context, bidSnapshot) {
                      final bidCount = bidSnapshot.data?.docs.length ?? 0;
                      return Row(
                        children: [
                          Icon(Icons.gavel, size: 16, color: CColors.primary),
                          const SizedBox(width: 4),
                          Text('${'bid.total_bids'.tr()}: $bidCount',
                            style: Theme.of(context).textTheme.labelMedium!.copyWith(
                              color: CColors.primary, fontWeight: FontWeight.bold, fontSize: isUrdu ? 14 : 12,
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

  Widget _buildLoadingJobs() {
    final isUrdu = context.locale.languageCode == 'ur';
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: CColors.primary),
            const SizedBox(height: CSizes.md),
            Text('common.loading_jobs'.tr(),
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: isUrdu ? 16 : 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    final isUrdu = context.locale.languageCode == 'ur';
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? CColors.darkContainer : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.work_outline, size: 48, color: CColors.grey),
            const SizedBox(height: CSizes.md),
            Text(message,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: CColors.textSecondary, fontSize: isUrdu ? 16 : 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ============== PAGES ==============

  List<Widget> _getPages() {
    return [
      MyPostedJobsScreen(scrollController: _myPostedJobsScrollController),
      PostJobScreen(
        showAppBar: false,
        onJobPosted: () {
          ref.read(clientPageIndexProvider.notifier).state = 2;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('job.job_posted'.tr()),
            backgroundColor: CColors.success,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ));
        },
      ),
      _buildHomePage(),
      NotificationsScreen(scrollController: _notificationsScrollController, showAppBar: false),
      _buildProfilePlaceholder(controller: _profileScrollController),
    ];
  }

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
            child: Column(
              children: [
                ClientDashboardHeader(userName: _userName),
                Padding(
                  padding: const EdgeInsets.all(CSizes.defaultSpace),
                  child: _buildOpportunityCard(context),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildSectionHeader(context, 'dashboard.project_overview'.tr(), showAction: false),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildStatsGrid(context),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(context, 'bid.recent_jobs'.tr(),
                  actionText: 'common.view_all'.tr(),
                  onAction: () => ref.read(clientPageIndexProvider.notifier).state = 0,
                ),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildJobFeed(limit: 3),
                const SizedBox(height: CSizes.spaceBtwSections * 2),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePlaceholder({ScrollController? controller}) {
    return SingleChildScrollView(
      controller: controller,
      child: SizedBox(
        height: MediaQuery.of(context).size.height,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_outline, size: 80, color: Colors.grey),
              const SizedBox(height: 16),
              Text('common.coming_soon'.tr(), style: const TextStyle(fontSize: 18, color: Colors.grey)),
              const SizedBox(height: 8),
              const Text('Profile Page', style: TextStyle(fontSize: 16, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    final currentPageIndex = ref.watch(clientPageIndexProvider);

    ScrollController activeController;
    switch (currentPageIndex) {
      case 0: activeController = _myPostedJobsScrollController; break;
      case 1: activeController = _postJobScrollController; break;
      case 2: activeController = _homeScrollController; break;
      case 3: activeController = _notificationsScrollController; break;
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
          ref.read(clientPageIndexProvider.notifier).state = index;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            switch (index) {
              case 0: if (_myPostedJobsScrollController.hasClients) _myPostedJobsScrollController.jumpTo(0); break;
              case 1: if (_postJobScrollController.hasClients) _postJobScrollController.jumpTo(0); break;
              case 2: if (_homeScrollController.hasClients) _homeScrollController.jumpTo(0); break;
              case 3: if (_notificationsScrollController.hasClients) _notificationsScrollController.jumpTo(0); break;
              case 4: if (_profileScrollController.hasClients) _profileScrollController.jumpTo(0); break;
            }
          });
        },
        userRole: 'client',
        scrollController: activeController,
      ),
    );
  }
}