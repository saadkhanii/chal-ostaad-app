// lib/features/client/client_dashboard.dart

import 'package:chal_ostaad/features/client/client_job_details_screen.dart';
import 'package:chal_ostaad/features/client/post_job_screen.dart';
import 'package:chal_ostaad/features/notifications/notifications_screen.dart';
import 'package:chal_ostaad/features/client/my_posted_jobs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/job_model.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/job_service.dart';
import '../../shared/widgets/dashboard_drawer.dart';
import '../../shared/widgets/curved_nav_bar.dart';
import 'client_dashboard_header.dart';
import 'jobs_list_widget.dart';

// Create a state provider for loading
final clientLoadingProvider = StateProvider<bool>((ref) => true);
// Add page index provider for navigation - START AT HOME (INDEX 2)
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

  // Create separate controllers for each scrollable page
  final ScrollController _myPostedJobsScrollController = ScrollController(); // Index 0
  final ScrollController _postJobScrollController = ScrollController();      // Index 1
  final ScrollController _homeScrollController = ScrollController();         // Index 2
  final ScrollController _notificationsScrollController = ScrollController(); // Index 3
  final ScrollController _profileScrollController = ScrollController();      // Index 4

  final JobService _jobService = JobService();
  final BidService _bidService = BidService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserData();
    });
  }

  @override
  void dispose() {
    // Dispose all controllers
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

      debugPrint('Loading client data - UID: $userUid, Name: $userName');

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
          debugPrint('Error fetching user data from Firestore: $e');
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
        debugPrint('No user UID found in SharedPreferences');
        if (mounted) {
          ref.read(clientLoadingProvider.notifier).state = false;
        }
      }
    } catch (e) {
      debugPrint('Error loading client data: $e');
      if (mounted) {
        ref.read(clientLoadingProvider.notifier).state = false;
      }
    }
  }

  void _showJobDetails(JobModel job) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClientJobDetailsScreen(job: job),
      ),
    );
  }

  void _showAllJobs() {
    // Navigate to My Posted Jobs tab (index 0)
    ref.read(clientPageIndexProvider.notifier).state = 0;
  }

  Widget _buildLoadingScreen() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildOpportunityCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CColors.primary.withOpacity(0.95),
            CColors.secondary.withOpacity(0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        boxShadow: [
          BoxShadow(
            color: CColors.primary.withOpacity(0.4),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: CColors.secondary.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'dashboard.post_job'.tr(),
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              color: CColors.white,
              fontWeight: FontWeight.bold,
              fontSize: isUrdu ? 24 : 22,
            ),
          ),
          const SizedBox(height: CSizes.sm),
          Text(
            'dashboard.find_workers'.tr(),
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: CColors.white.withOpacity(0.9),
              fontSize: isUrdu ? 16 : 14,
            ),
          ),
          const SizedBox(height: CSizes.lg),
          ElevatedButton(
            onPressed: () {
              // Navigate to post job tab (index 1)
              ref.read(clientPageIndexProvider.notifier).state = 1;
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.white,
              foregroundColor: CColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(
              'dashboard.post_now'.tr(),
              style: TextStyle(fontSize: isUrdu ? 16 : 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, {String? actionText, VoidCallback? onAction, bool showAction = true}) {
    final isUrdu = context.locale.languageCode == 'ur';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: isUrdu ? 22 : 20,
          ),
        ),
        if (showAction && actionText != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              actionText,
              style: TextStyle(fontSize: isUrdu ? 16 : 14),
            ),
          ),
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchClientStats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingStats(context);
        }

        if (snapshot.hasError) {
          return _buildStatItem(context, 'common.error'.tr(), '!', Icons.error);
        }

        final stats = snapshot.data ?? {
          'postedJobs': 0,
          'activeJobs': 0,
          'completedJobs': 0,
          'totalSpent': 0.0,
        };

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(context, 'dashboard.posted_jobs'.tr(), '${stats['postedJobs']}', Icons.work_outline),
            _buildStatItem(context, 'dashboard.active_jobs'.tr(), '${stats['activeJobs']}', Icons.work),
            _buildStatItem(context, 'dashboard.completed_jobs'.tr(), '${stats['completedJobs']}', Icons.check_circle),
            _buildStatItem(context, 'dashboard.total_spent'.tr(), _formatCurrency(stats['totalSpent']), Icons.attach_money),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchClientStats() async {
    if (_clientId.isEmpty) {
      return {
        'postedJobs': 0,
        'activeJobs': 0,
        'completedJobs': 0,
        'totalSpent': 0.0,
      };
    }

    try {
      final jobsSnapshot = await _firestore
          .collection('jobs')
          .where('clientId', isEqualTo: _clientId)
          .get();

      final jobs = jobsSnapshot.docs;

      final postedJobs = jobs.length;
      final activeJobs = jobs.where((doc) => doc['status'] == 'in-progress').length;
      final completedJobs = jobs.where((doc) => doc['status'] == 'completed').length;

      // Calculate total spent from accepted bids on completed jobs
      double totalSpent = 0.0;

      // Get IDs of completed jobs
      final completedJobIds = jobs
          .where((doc) => doc['status'] == 'completed')
          .map((doc) => doc.id)
          .toList();

      if (completedJobIds.isNotEmpty) {
        // Fetch accepted bids for completed jobs
        final bidsSnapshot = await _firestore
            .collection('bids')
            .where('jobId', whereIn: completedJobIds)
            .where('status', isEqualTo: 'accepted')
            .get();

        // Sum up the amounts
        for (var bidDoc in bidsSnapshot.docs) {
          final amount = bidDoc['amount'];
          if (amount is num) {
            totalSpent += amount.toDouble();
          }
        }
      }

      return {
        'postedJobs': postedJobs,
        'activeJobs': activeJobs,
        'completedJobs': completedJobs,
        'totalSpent': totalSpent,
      };
    } catch (e) {
      debugPrint('Error fetching client stats: $e');
      return {
        'postedJobs': 0,
        'activeJobs': 0,
        'completedJobs': 0,
        'totalSpent': 0.0,
      };
    }
  }

  Widget _buildLoadingStats(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(context, 'dashboard.posted_jobs'.tr(), '...', Icons.work_outline),
        _buildStatItem(context, 'dashboard.active_jobs'.tr(), '...', Icons.work),
        _buildStatItem(context, 'dashboard.completed_jobs'.tr(), '...', Icons.check_circle),
        _buildStatItem(context, 'dashboard.total_spent'.tr(), '...', Icons.attach_money),
      ],
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value, IconData icon) {
    final isUrdu = context.locale.languageCode == 'ur';

    return Column(
      children: [
        Icon(icon, color: CColors.primary, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: isUrdu ? 20 : 18,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            fontSize: isUrdu ? 14 : 12,
          ),
        ),
      ],
    );
  }

  String _formatCurrency(double amount) {
    if (amount == 0) return 'Rs 0';
    if (amount >= 10000000) {
      return 'Rs ${(amount / 10000000).toStringAsFixed(1)}Cr';
    } else if (amount >= 100000) {
      return 'Rs ${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return 'Rs ${(amount / 1000).toStringAsFixed(1)}k';
    }
    return 'Rs ${amount.toStringAsFixed(0)}';
  }

  // Pages for bottom navigation
  List<Widget> _getPages() {
    return [
      // Index 0: My Posted Jobs
      MyPostedJobsScreen(
        scrollController: _myPostedJobsScrollController,
      ),

      // Index 1: Post Job
      PostJobScreen(
        showAppBar: false,
        onJobPosted: () {
          // After posting, go back to home
          ref.read(clientPageIndexProvider.notifier).state = 2;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('job.job_posted'.tr()),
              backgroundColor: CColors.success,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),

      // Index 2: Home Dashboard
      _buildHomePage(),

      // Index 3: Notifications
      NotificationsScreen(
        scrollController: _notificationsScrollController,
        showAppBar: false,
      ),

      // Index 4: Profile
      _buildProfilePlaceholder(controller: _profileScrollController),
    ];
  }

  Widget _buildHomePage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLoading = ref.watch(clientLoadingProvider);

    if (isLoading) {
      return _buildLoadingScreen();
    }

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildOpportunityCard(context),
                      const SizedBox(height: CSizes.spaceBtwSections),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildSectionHeader(
                  context,
                  'dashboard.project_overview'.tr(),
                  showAction: false,
                ),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildStatsRow(context),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(
                  context,
                  'bid.recent_jobs'.tr(),
                  actionText: 'common.view_all'.tr(),
                  onAction: () => _showAllJobs(),
                ),
                const SizedBox(height: CSizes.spaceBtwItems),
                if (_clientId.isNotEmpty)
                  SizedBox(
                    height: 400,
                    child: JobsListWidget(
                      clientId: _clientId,
                      showFilters: false,
                      limit: 3,
                      onJobTap: (job) => _showJobDetails(job),
                    ),
                  ),
                const SizedBox(height: CSizes.spaceBtwSections),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePlaceholder({ScrollController? controller}) {
    return Scrollbar(
      controller: controller,
      child: SingleChildScrollView(
        controller: controller,
        child: Container(
          height: MediaQuery.of(context).size.height,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_outline, size: 80, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'common.coming_soon'.tr(),
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  'Profile Page',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
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

    // CORRECT controller mapping based on index
    ScrollController activeController;
    switch (currentPageIndex) {
      case 0: // My Posted Jobs
        activeController = _myPostedJobsScrollController;
        break;
      case 1: // Post Job
        activeController = _postJobScrollController;
        break;
      case 2: // Home Dashboard
        activeController = _homeScrollController;
        break;
      case 3: // Notifications
        activeController = _notificationsScrollController;
        break;
      case 4: // Profile
        activeController = _profileScrollController;
        break;
      default:
        activeController = _homeScrollController;
    }

    return Scaffold(
      endDrawer: !isUrdu ? const DashboardDrawer() : null,
      drawer: isUrdu ? const DashboardDrawer() : null,
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: IndexedStack(
        index: currentPageIndex,
        children: _getPages(),
      ),
      bottomNavigationBar: CurvedNavBar(
        currentIndex: currentPageIndex,
        onTap: (index) {
          // Update the page index
          ref.read(clientPageIndexProvider.notifier).state = index;

          // Reset scroll position of the new page
          WidgetsBinding.instance.addPostFrameCallback((_) {
            switch (index) {
              case 0:
                if (_myPostedJobsScrollController.hasClients) {
                  _myPostedJobsScrollController.jumpTo(0);
                }
                break;
              case 1:
                if (_postJobScrollController.hasClients) {
                  _postJobScrollController.jumpTo(0);
                }
                break;
              case 2:
                if (_homeScrollController.hasClients) {
                  _homeScrollController.jumpTo(0);
                }
                break;
              case 3:
                if (_notificationsScrollController.hasClients) {
                  _notificationsScrollController.jumpTo(0);
                }
                break;
              case 4:
                if (_profileScrollController.hasClients) {
                  _profileScrollController.jumpTo(0);
                }
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