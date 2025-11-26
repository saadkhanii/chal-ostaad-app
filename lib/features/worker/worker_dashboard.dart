// lib/features/worker/worker_dashboard.dart
import 'package:chal_ostaad/features/worker/worker_dashboard_header.dart';
import 'package:chal_ostaad/features/worker/worker_job_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/job_model.dart';
import '../../core/models/bid_model.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/category_service.dart';
import '../../core/services/worker_service.dart';
import '../../shared/widgets/dashboard_drawer.dart';

class WorkerDashboard extends StatefulWidget {
  const WorkerDashboard({super.key});

  @override
  State<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends State<WorkerDashboard> {
  String _userName = 'Worker';
  String _workerId = '';
  String _workerCategory = '';
  bool _isLoading = true;
  int _selectedFilter = 0; // 0: All, 1: My Category

  final WorkerService _workerService = WorkerService();
  final BidService _bidService = BidService();
  final List<String> _filterOptions = ['All Jobs', 'My Category'];
  final CategoryService _categoryService = CategoryService();
  String _workerCategoryName = '';
  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userUid = prefs.getString('user_uid');
      final userName = prefs.getString('user_name');

      if (userName != null && userName.isNotEmpty) {
        setState(() {
          _userName = userName;
        });
      }

      if (userUid != null) {
        setState(() {
          _workerId = userUid;
        });
        await _loadWorkerProfile();
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading worker data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadWorkerProfile() async {
    try {
      final worker = await _workerService.getCurrentWorker();
      if (worker != null && worker.categoryId != null && worker.categoryId!.isNotEmpty) {
        // Convert category ID to category name for filtering
        final categoryName = await _categoryService.getCategoryName(worker.categoryId!);
        setState(() {
          _workerCategory = worker.categoryId!;
          _workerCategoryName = categoryName;
        });
        debugPrint('WORKER: Category ID: ${worker.categoryId}, Category Name: $categoryName');
      } else {
        debugPrint('WORKER: No category assigned or category ID is empty');
      }
    } catch (e) {
      debugPrint('Error loading worker profile: $e');
    }
  }


  void _showJobDetails(JobModel job) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WorkerJobDetailsScreen(
          job: job,
          workerId: _workerId,
          workerCategory: _workerCategory,
          onBidPlaced: () => setState(() {}),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: const DashboardDrawer(),
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? CColors.dark : CColors.light,
      body: _isLoading
          ? _buildLoadingScreen()
          : CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                WorkerDashboardHeader(userName: _userName),
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
                  'Performance Overview',
                  showAction: false,
                ),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildStatsRow(context),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(
                  context,
                  'Available Jobs',
                  actionText: 'View All',
                  onAction: () => _showAllJobs(),
                ),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildFilterChips(),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildJobFeed(),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(
                  context,
                  'My Bids',
                  showAction: false,
                ),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildMyBidsList(),
                const SizedBox(height: CSizes.spaceBtwSections * 2),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Column(
      children: [
        Container(
          height: 200,
          color: CColors.primary,
          child: const Center(
            child: CircularProgressIndicator(color: CColors.white),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: CColors.primary),
                const SizedBox(height: CSizes.md),
                Text(
                  'Loading your dashboard...',
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: CColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOpportunityCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CColors.secondary,
            CColors.primary.withOpacity(0.8),
          ],
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: CColors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.rocket_launch_rounded, size: 14, color: CColors.white),
                      const SizedBox(width: 6),
                      Text(
                        'BIDDING PLATFORM',
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: CColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Find Your Next Project',
                  style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                    color: CColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Place competitive bids and win projects in your category. Start earning today!',
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: CColors.white.withOpacity(0.9),
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CColors.white.withOpacity(0.2),
            ),
            child: IconButton(
              onPressed: () {
                Scrollable.ensureVisible(
                  context,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                );
              },
              icon: Icon(Icons.arrow_downward_rounded, color: CColors.white, size: 24),
              tooltip: 'Browse Jobs',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, {
    String? actionText,
    VoidCallback? onAction,
    bool showAction = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall!.copyWith(
            fontWeight: FontWeight.w800,
            color: isDark ? CColors.textWhite : CColors.textPrimary,
            fontSize: 20,
          ),
        ),
        if (showAction && actionText != null && onAction != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [CColors.primary, CColors.secondary],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: CColors.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionText,
                    style: Theme.of(context).textTheme.labelMedium!.copyWith(
                      color: CColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 16, color: CColors.white),
                ],
              ),
            ),
          ),
      ],
    );
  }
  Future<String> _getClientName(String clientId) async {
    try {
      final clientDoc = await FirebaseFirestore.instance
          .collection('clients')
          .doc(clientId)
          .get();

      if (clientDoc.exists) {
        final clientData = clientDoc.data();
        return clientData?['name'] ?? clientData?['userName'] ?? 'Client';
      }
      return 'Client';
    } catch (e) {
      debugPrint('Error fetching client name: $e');
      return 'Client';
    }
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Always show "My Category" as selected
          Container(
            margin: const EdgeInsets.only(right: 12),
            child: ChoiceChip(
              label: const Text('My Category'),
              selected: true,
              onSelected: null,
              backgroundColor: CColors.primary.withOpacity(0.1),
              selectedColor: CColors.primary,
              labelStyle: const TextStyle(
                color: CColors.white,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: CColors.primary, width: 1.5),
              ),
            ),
          ),
          // Show worker's category name as a label
          if (_workerCategoryName.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: CColors.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CColors.secondary),
              ),
              child: Text(
                _workerCategoryName,
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color: CColors.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // Show warning if no category assigned
          if (_workerCategory.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: CColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CColors.warning),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: CColors.warning),
                  const SizedBox(width: 6),
                  Text(
                    'No Category Assigned',
                    style: Theme.of(context).textTheme.labelMedium!.copyWith(
                      color: CColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bids')
          .where('workerId', isEqualTo: _workerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _buildStatsLoading(context);
        }

        final bids = snapshot.data!.docs;
        final pendingBids = bids.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'pending').length;
        final acceptedBids = bids.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'accepted').length;
        final totalEarnings = bids
            .where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'accepted')
            .fold(0.0, (sum, doc) => sum + (doc.data() as Map<String, dynamic>)['amount']);

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.3,
          mainAxisSpacing: CSizes.spaceBtwItems,
          crossAxisSpacing: CSizes.spaceBtwItems,
          children: [
            _buildStatCard(
              context,
              icon: Icons.pending_actions_rounded,
              value: pendingBids.toString(),
              label: 'Pending Bids',
              color: CColors.warning,
            ),
            _buildStatCard(
              context,
              icon: Icons.emoji_events_rounded,
              value: acceptedBids.toString(),
              label: 'Projects Won',
              color: CColors.success,
            ),
            _buildStatCard(
              context,
              icon: Icons.assignment_rounded,
              value: bids.length.toString(),
              label: 'Total Bids',
              color: CColors.info,
            ),
            _buildStatCard(
              context,
              icon: Icons.account_balance_wallet_rounded,
              value: 'Rs. ${totalEarnings.toStringAsFixed(0)}',
              label: 'Total Earnings',
              color: CColors.primary,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: isDark ? CColors.darkContainer : CColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: isDark ? CColors.darkerGrey : Colors.transparent),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
              fontWeight: FontWeight.w800,
              color: isDark ? CColors.textWhite : CColors.textPrimary,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: CColors.darkGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsLoading(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.3,
      mainAxisSpacing: CSizes.spaceBtwItems,
      crossAxisSpacing: CSizes.spaceBtwItems,
      children: [
        _buildStatCard(
          context,
          icon: Icons.pending_actions_rounded,
          value: '0',
          label: 'Loading...',
          color: CColors.grey,
        ),
        _buildStatCard(
          context,
          icon: Icons.emoji_events_rounded,
          value: '0',
          label: 'Loading...',
          color: CColors.grey,
        ),
        _buildStatCard(
          context,
          icon: Icons.assignment_rounded,
          value: '0',
          label: 'Loading...',
          color: CColors.grey,
        ),
        _buildStatCard(
          context,
          icon: Icons.account_balance_wallet_rounded,
          value: 'Rs. 0',
          label: 'Loading...',
          color: CColors.grey,
        ),
      ],
    );
  }

  Widget _buildJobFeed() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getJobsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildJobLoadingState();
        }

        if (snapshot.hasError) {
          debugPrint('JOBS FIRESTORE ERROR: ${snapshot.error}');
          return _buildJobErrorState(
            context,
            'Failed to load jobs: ${snapshot.error}',
            onRetry: () => setState(() {}),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildJobEmptyState(context);
        }

        final jobDocs = snapshot.data!.docs;
        debugPrint('WORKER: Loaded ${jobDocs.length} jobs');

        return FutureBuilder<List<JobModel>>(
          future: _filterJobsWithBids(jobDocs),
          builder: (context, filteredSnapshot) {
            if (filteredSnapshot.connectionState == ConnectionState.waiting) {
              return _buildJobLoadingState();
            }

            final filteredJobs = filteredSnapshot.data ?? [];

            if (filteredJobs.isEmpty) {
              return _buildJobEmptyState(context);
            }

            return Column(
              children: [
                ...filteredJobs.take(5).map((job) => _buildJobCard(job)),
                if (filteredJobs.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: CSizes.md),
                    child: ElevatedButton(
                      onPressed: () => _showAllJobs(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: CColors.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text('View More Jobs'),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Stream<QuerySnapshot> _getJobsStream() {
    if (_workerCategoryName.isNotEmpty) {
      debugPrint('WORKER: Filtering jobs for category: $_workerCategoryName');
      return FirebaseFirestore.instance
          .collection('jobs')
          .where('status', isEqualTo: 'open')
          .where('category', isEqualTo: _workerCategoryName) // Use category name here
          .orderBy('createdAt', descending: true)
          .snapshots();
    } else {
      debugPrint('WORKER: No category name available, showing empty stream');
      return const Stream<QuerySnapshot>.empty();
    }
  }

  Future<List<JobModel>> _filterJobsWithBids(List<QueryDocumentSnapshot> jobDocs) async {
    final filteredJobs = <JobModel>[];

    for (final doc in jobDocs) {
      try {
        final job = JobModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);

        final hasBid = await _bidService.hasWorkerBidOnJob(_workerId, job.id!);
        if (!hasBid) {
          filteredJobs.add(job);
        }
      } catch (e) {
        debugPrint('Error filtering job: $e');
      }
    }

    return filteredJobs;
  }

// In worker_dashboard.dart, update the _buildJobCard method:

  Widget _buildJobCard(JobModel job) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: CSizes.spaceBtwItems),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: isDark ? CColors.darkContainer : CColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: isDark ? CColors.darkerGrey : Colors.transparent),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showJobDetails(job),
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          child: Padding(
            padding: const EdgeInsets.all(CSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with category and time - FIXED LAYOUT
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: CColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          job.category,
                          style: Theme.of(context).textTheme.labelSmall!.copyWith(
                            color: CColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: Text(
                        timeago.format(job.createdAt.toDate()),
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: CColors.darkGrey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Job Title - MAKE SURE THIS IS VISIBLE
                Text(
                  job.title,
                  style: Theme.of(context).textTheme.titleLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? CColors.textWhite : CColors.textPrimary,
                    fontSize: 18,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // Job Description - MAKE SURE THIS IS VISIBLE
                Text(
                  job.description,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: isDark ? CColors.textWhite.withOpacity(0.7) : CColors.darkerGrey,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),

                // Footer row with client info and bid button - FIXED LAYOUT
                Row(
                  children: [
                    // Client info - FIXED: Use proper constraints
                    Expanded(
                      child: FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('clients').doc(job.clientId).get(),
                        builder: (context, snapshot) {
                          String clientName = 'Loading...';

                          if (snapshot.hasData && snapshot.data!.exists) {
                            final clientData = snapshot.data!.data() as Map<String, dynamic>;
                            final personalInfo = clientData['personalInfo'];
                            if (personalInfo is Map<String, dynamic>) {
                              clientName = personalInfo['fullName'] ?? 'Client';
                            }
                          } else if (snapshot.hasError) {
                            clientName = 'Client';
                          }

                          return Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: CColors.primary.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.person_rounded, size: 16, color: CColors.primary),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'By: $clientName',
                                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                    color: CColors.darkGrey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Bid button - Fixed width to prevent overflow
                    SizedBox(
                      width: 100, // Fixed width to prevent layout issues
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [CColors.primary, CColors.secondary],
                          ),
                          borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
                          boxShadow: [
                            BoxShadow(
                              color: CColors.primary.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () => _showJobDetails(job),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: CColors.white,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          child: const Text(
                            'Place Bid',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildMyBidsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bids')
          .where('workerId', isEqualTo: _workerId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildBidsLoadingState();
        }

        if (snapshot.hasError) {
          return _buildBidsErrorState(
            context,
            'Failed to load your bids',
            onRetry: () => setState(() {}),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildBidsEmptyState(context);
        }

        final bidDocs = snapshot.data!.docs;
        final recentBids = bidDocs.take(3).toList();

        return Column(
          children: [
            ...recentBids.map((doc) {
              try {
                final bid = BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
                return _buildBidCard(bid, context);
              } catch (e) {
                return _buildBidErrorCard(context, 'Failed to load bid');
              }
            }),
            if (bidDocs.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: CSizes.md),
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('View All Bids - Coming Soon!')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: CColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text('View All Bids'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBidCard(BidModel bid, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: CSizes.spaceBtwItems),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: isDark ? CColors.darkContainer : CColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: isDark ? CColors.darkerGrey : Colors.transparent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CSizes.lg),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _getBidStatusColor(bid.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.gavel_rounded, size: 24, color: _getBidStatusColor(bid.status)),
            ),
            const SizedBox(width: CSizes.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rs. ${bid.amount.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark ? CColors.textWhite : CColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Job: ${bid.jobId.substring(0, 8)}...',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: CColors.darkGrey,
                    ),
                  ),
                  if (bid.message != null && bid.message!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '"${bid.message!}"',
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: CColors.darkGrey,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getBidStatusColor(bid.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                bid.status.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: _getBidStatusColor(bid.status),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBidStatusColor(String status) {
    switch (status) {
      case 'pending':
        return CColors.warning;
      case 'accepted':
        return CColors.success;
      case 'rejected':
        return CColors.error;
      default:
        return CColors.grey;
    }
  }

  // Loading, Error, and Empty States for Jobs
  Widget _buildJobLoadingState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60.0),
      child: Column(
        children: [
          CircularProgressIndicator(color: CColors.primary),
          const SizedBox(height: CSizes.lg),
          Text(
            'Loading available jobs...',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: CColors.darkGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobErrorState(BuildContext context, String error, {VoidCallback? onRetry}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(CSizes.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: isDark ? CColors.darkContainer : CColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: CColors.error),
          const SizedBox(height: CSizes.lg),
          Text(
            'Unable to Load Jobs',
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? CColors.textWhite : CColors.textPrimary,
            ),
          ),
          const SizedBox(height: CSizes.sm),
          Text(
            error,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: CColors.darkGrey),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: CSizes.lg),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: CColors.primary,
                foregroundColor: CColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildJobEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60.0, horizontal: 20.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: isDark ? CColors.darkContainer : CColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.work_outline_rounded, size: 64, color: CColors.primary.withOpacity(0.5)),
          const SizedBox(height: CSizes.lg),
          Text(
            'No Jobs Available',
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
              color: isDark ? CColors.textWhite : CColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CSizes.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Text(
              _selectedFilter == 1 && _workerCategory.isNotEmpty
                  ? 'No jobs found in your category. Try browsing all jobs.'
                  : 'Check back later for new job opportunities',
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: CColors.darkGrey,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // Loading, Error, and Empty States for Bids
  Widget _buildBidsLoadingState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60.0),
      child: Column(
        children: [
          CircularProgressIndicator(color: CColors.primary),
          const SizedBox(height: CSizes.lg),
          Text(
            'Loading your bids...',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: CColors.darkGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBidsErrorState(BuildContext context, String error, {VoidCallback? onRetry}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(CSizes.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: isDark ? CColors.darkContainer : CColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: CColors.error),
          const SizedBox(height: CSizes.lg),
          Text(
            'Unable to Load Bids',
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? CColors.textWhite : CColors.textPrimary,
            ),
          ),
          const SizedBox(height: CSizes.sm),
          Text(
            error,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: CColors.darkGrey),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: CSizes.lg),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: CColors.primary,
                foregroundColor: CColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBidErrorCard(BuildContext context, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: CSizes.spaceBtwItems),
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: isDark ? CColors.darkContainer : CColors.lightContainer,
        border: Border.all(color: CColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 20, color: CColors.error),
          const SizedBox(width: CSizes.md),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: CColors.darkGrey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBidsEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60.0, horizontal: 20.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: isDark ? CColors.darkContainer : CColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.gavel_rounded, size: 64, color: CColors.primary.withOpacity(0.5)),
          const SizedBox(height: CSizes.lg),
          Text(
            'No Bids Yet',
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
              color: isDark ? CColors.textWhite : CColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CSizes.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Text(
              'Start bidding on available jobs to see them here',
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: CColors.darkGrey,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  void _showAllJobs() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All Jobs Screen - Coming Soon!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}