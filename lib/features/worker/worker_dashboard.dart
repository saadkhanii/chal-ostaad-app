// lib/features/worker/worker_dashboard.dart

import 'package:chal_ostaad/features/worker/worker_dashboard_header.dart';
import 'package:chal_ostaad/features/worker/worker_job_details_screen.dart' as job_details;
import 'package:chal_ostaad/features/notifications/notifications_screen.dart';
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
import '../../core/services/bid_service.dart';
import '../../core/services/category_service.dart';
import '../../core/services/worker_service.dart';
import '../../shared/widgets/dashboard_drawer.dart';
import '../../shared/widgets/curved_nav_bar.dart';

// State provider for worker loading
final workerLoadingProvider = StateProvider<bool>((ref) => true);
// Page index provider - START AT HOME (INDEX 2)
final workerPageIndexProvider = StateProvider<int>((ref) => 2);

class WorkerDashboard extends ConsumerStatefulWidget {
  const WorkerDashboard({super.key});

  @override
  ConsumerState<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends ConsumerState<WorkerDashboard> {
  String _userName = 'dashboard.worker'.tr();
  String _workerId = '';
  String _workerCategory = '';
  int _selectedFilter = 0; // 0: All, 1: My Category

  // Create separate controllers for each scrollable page
  final ScrollController _findJobsScrollController = ScrollController(); // Index 0
  final ScrollController _myBidsScrollController = ScrollController();    // Index 1
  final ScrollController _homeScrollController = ScrollController();      // Index 2
  final ScrollController _notificationsScrollController = ScrollController(); // Index 3
  final ScrollController _profileScrollController = ScrollController();   // Index 4

  final WorkerService _workerService = WorkerService();
  final BidService _bidService = BidService();
  final List<String> _filterOptions = ['dashboard.all_jobs'.tr(), 'dashboard.my_category'.tr()];
  final CategoryService _categoryService = CategoryService();
  String _workerCategoryName = '';
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
    _findJobsScrollController.dispose();
    _myBidsScrollController.dispose();
    _homeScrollController.dispose();
    _notificationsScrollController.dispose();
    _profileScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userUid = prefs.getString('user_uid');
      final userName = prefs.getString('user_name');

      if (mounted) {
        setState(() {
          if (userName != null && userName.isNotEmpty) {
            _userName = userName;
          }
          if (userUid != null) {
            _workerId = userUid;
          }
        });
      }

      if (userUid != null) {
        await _loadWorkerProfile();
      }

      if (mounted) {
        ref.read(workerLoadingProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error loading worker data: $e');
      if (mounted) {
        ref.read(workerLoadingProvider.notifier).state = false;
      }
    }
  }

  Future<void> _loadWorkerProfile() async {
    try {
      final worker = await _workerService.getCurrentWorker();
      if (worker != null && worker.categoryId != null && worker.categoryId!.isNotEmpty) {
        final categoryName = await _categoryService.getCategoryName(worker.categoryId!);
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
      return {
        'bidsPlaced': 0,
        'jobsWon': 0,
        'earnings': 0.0,
        'rating': 'N/A',
      };
    }

    try {
      final bidsSnapshot = await _firestore
          .collection('bids')
          .where('workerId', isEqualTo: _workerId)
          .get();

      final bids = bidsSnapshot.docs;
      final totalBids = bids.length;
      final acceptedBids = bids.where((doc) => doc['status'] == 'accepted').length;

      double earnings = 0.0;
      final acceptedBidDocs = bids.where((doc) => doc['status'] == 'accepted');

      for (final doc in acceptedBidDocs) {
        final amount = doc['amount'];
        if (amount is num) {
          earnings += amount.toDouble();
        }
      }

      // Get rating
      double rating = 0.0;
      String ratingText = 'N/A';
      try {
        final workerDoc = await _firestore.collection('workers').doc(_workerId).get();
        if (workerDoc.exists) {
          final data = workerDoc.data() as Map<String, dynamic>?;
          final ratings = data?['ratings'] as Map<String, dynamic>?;
          final avgRating = ratings?['average'] as num?;
          final totalReviews = ratings?['totalReviews'] as int? ?? 0;

          if (avgRating != null && avgRating > 0 && totalReviews > 0) {
            rating = avgRating.toDouble();
            ratingText = rating.toStringAsFixed(1);
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
      return {
        'bidsPlaced': 0,
        'jobsWon': 0,
        'earnings': 0.0,
        'rating': 'N/A',
      };
    }
  }

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

  void _showAllJobs() {
    // Navigate to Find Jobs tab (index 0)
    ref.read(workerPageIndexProvider.notifier).state = 0;
  }

  void _showAllBids() {
    // Navigate to My Bids tab (index 1)
    ref.read(workerPageIndexProvider.notifier).state = 1;
  }

  // Pages for bottom navigation
  List<Widget> _getPages() {
    return [
      // Index 0: Find Jobs
      FindJobsScreen(
        scrollController: _findJobsScrollController,
        showAppBar: false,
      ),

      // Index 1: My Bids
      MyBidsScreen(
        scrollController: _myBidsScrollController,
        showAppBar: false,
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
    final isLoading = ref.watch(workerLoadingProvider);

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
                  'dashboard.performance_overview'.tr(),
                  showAction: false,
                ),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildStatsRow(context),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(
                  context,
                  'dashboard.available_jobs'.tr(),
                  actionText: 'common.view_all'.tr(),
                  onAction: () => _showAllJobs(),
                ),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildFilterChips(),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildJobFeed(limit: 3),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(
                  context,
                  'dashboard.recent_bids'.tr(),
                  actionText: 'common.view_all'.tr(),
                  onAction: () => _showAllBids(),
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

  Widget _buildStatsRow(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchWorkerStats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingStats(context);
        }

        if (snapshot.hasError) {
          return _buildStatItem(context, 'common.error'.tr(), '!', Icons.error);
        }

        final stats = snapshot.data ?? {
          'bidsPlaced': 0,
          'jobsWon': 0,
          'earnings': 0.0,
          'rating': 'N/A',
        };

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(context, 'dashboard.bids_placed'.tr(), '${stats['bidsPlaced']}', Icons.gavel),
            _buildStatItem(context, 'dashboard.jobs_won'.tr(), '${stats['jobsWon']}', Icons.emoji_events),
            _buildStatItem(context, 'dashboard.earnings'.tr(), _formatCurrency(stats['earnings']), Icons.attach_money),
            _buildStatItem(context, 'dashboard.rating'.tr(), '${stats['rating']}', Icons.star),
          ],
        );
      },
    );
  }

  Widget _buildLoadingStats(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(context, 'dashboard.bids_placed'.tr(), '...', Icons.gavel),
        _buildStatItem(context, 'dashboard.jobs_won'.tr(), '...', Icons.emoji_events),
        _buildStatItem(context, 'dashboard.earnings'.tr(), '...', Icons.attach_money),
        _buildStatItem(context, 'dashboard.rating'.tr(), '...', Icons.star),
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
              label: Text(
                label,
                style: TextStyle(fontSize: isUrdu ? 16 : 14),
              ),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedFilter = idx;
                  });
                }
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
                  color: isSelected ? CColors.primary : (isDark ? CColors.darkGrey : CColors.grey),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildJobFeed({int? limit}) {
    if (_workerId.isEmpty) {
      return _buildEmptyState('errors.login_to_view_jobs'.tr());
    }

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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingJobs();
        }

        if (snapshot.hasError) {
          return _buildEmptyState('${'errors.load_jobs_failed'.tr()}: ${snapshot.error}');
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('job.no_jobs_available'.tr());
        }

        int itemCount = snapshot.data!.docs.length;
        if (limit != null && limit < itemCount) {
          itemCount = limit;
        }

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
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontSize: isUrdu ? 16 : 14,
                ),
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
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      fontSize: isUrdu ? 14 : 12,
                    ),
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
            Text(
              'common.loading_jobs'.tr(),
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: isUrdu ? 16 : 14,
              ),
            ),
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
        color: Theme.of(context).brightness == Brightness.dark
            ? CColors.darkContainer
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.work_outline, size: 48, color: CColors.grey),
            const SizedBox(height: CSizes.md),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: CColors.textSecondary,
                fontSize: isUrdu ? 16 : 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyBidsList({int? limit}) {
    if (_workerId.isEmpty) {
      return _buildEmptyState('errors.login_to_view_bids'.tr());
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('bids')
          .where('workerId', isEqualTo: _workerId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingBids();
        }

        if (snapshot.hasError) {
          return _buildEmptyState('${'errors.load_bids_failed'.tr()}: ${snapshot.error}');
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('bid.no_bids_placed'.tr());
        }

        int itemCount = snapshot.data!.docs.length;
        if (limit != null && limit < itemCount) {
          itemCount = limit;
        }

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

  Widget _buildBidItem(BidModel bid) {
    final isUrdu = context.locale.languageCode == 'ur';

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('jobs').doc(bid.jobId).get(),
      builder: (context, jobSnapshot) {
        if (jobSnapshot.connectionState == ConnectionState.waiting) {
          return ListTile(
            title: Text('common.loading'.tr()),
          );
        }

        if (!jobSnapshot.hasData || !jobSnapshot.data!.exists) {
          return ListTile(
            title: Text('job.job_not_found'.tr()),
          );
        }

        final jobData = jobSnapshot.data!.data() as Map<String, dynamic>;
        final jobTitle = jobData['title'] ?? 'job.unknown'.tr();

        return Card(
          margin: const EdgeInsets.only(bottom: CSizes.sm),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getBidStatusColor(bid.status),
              child: Icon(
                _getBidStatusIcon(bid.status),
                size: 20,
                color: Colors.white,
              ),
            ),
            title: Text(
              jobTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${'bid.amount'.tr()}: ${_formatCurrency(bid.amount)}'),
                Text(
                  '${'bid.status'.tr()}: ${_getBidStatusText(bid.status)}',
                  style: TextStyle(color: _getBidStatusColor(bid.status)),
                ),
              ],
            ),
            trailing: Text(
              timeago.format(bid.createdAt.toDate()),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        );
      },
    );
  }

  String _getBidStatusText(String status) {
    switch (status) {
      case 'accepted':
        return 'bid.status_accepted'.tr();
      case 'pending':
        return 'bid.status_pending'.tr();
      case 'rejected':
        return 'bid.status_rejected'.tr();
      default:
        return status;
    }
  }

  Widget _buildLoadingBids() {
    final isUrdu = context.locale.languageCode == 'ur';

    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: CColors.primary),
            const SizedBox(height: CSizes.md),
            Text(
              'common.loading_bids'.tr(),
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: isUrdu ? 16 : 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBidStatusColor(String status) {
    switch (status) {
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

  IconData _getBidStatusIcon(String status) {
    switch (status) {
      case 'accepted':
        return Icons.check_circle;
      case 'pending':
        return Icons.access_time;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.help;
    }
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
    final currentPageIndex = ref.watch(workerPageIndexProvider);

    // Select the right controller based on active page
    ScrollController activeController;
    switch (currentPageIndex) {
      case 0: // Find Jobs
        activeController = _findJobsScrollController;
        break;
      case 1: // My Bids
        activeController = _myBidsScrollController;
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
          ref.read(workerPageIndexProvider.notifier).state = index;

          // Reset scroll position of the new page
          WidgetsBinding.instance.addPostFrameCallback((_) {
            switch (index) {
              case 0:
                if (_findJobsScrollController.hasClients) {
                  _findJobsScrollController.jumpTo(0);
                }
                break;
              case 1:
                if (_myBidsScrollController.hasClients) {
                  _myBidsScrollController.jumpTo(0);
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
        userRole: 'worker',
        scrollController: activeController,
      ),
    );
  }
}