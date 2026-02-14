// lib/features/worker/worker_dashboard.dart

import 'package:chal_ostaad/features/worker/worker_dashboard_header.dart';
import 'package:chal_ostaad/features/worker/worker_job_details_screen.dart' as job_details; // Added alias
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

// State provider for worker loading
final workerLoadingProvider = StateProvider<bool>((ref) => true);

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
        'totalBids': 0,
        'pendingBids': 0,
        'acceptedBids': 0,
        'rejectedBids': 0,
      };
    }

    try {
      final bidsSnapshot = await _firestore
          .collection('bids')
          .where('workerId', isEqualTo: _workerId)
          .get();

      final bids = bidsSnapshot.docs;
      final totalBids = bids.length;

      final pendingBids = bids.where((doc) => doc['status'] == 'pending').length;
      final acceptedBids = bids.where((doc) => doc['status'] == 'accepted').length;
      final rejectedBids = bids.where((doc) => doc['status'] == 'rejected').length;

      double earnings = 0.0;
      final acceptedBidDocs = bids.where((doc) => doc['status'] == 'accepted');

      for (final doc in acceptedBidDocs) {
        final amount = doc['amount'];
        double bidAmount = 0.0;

        if (amount is int) {
          bidAmount = amount.toDouble();
        } else if (amount is double) {
          bidAmount = amount;
        } else if (amount is String) {
          try {
            final cleanedAmount = amount.replaceAll(RegExp(r'[^0-9\.]'), '');
            bidAmount = double.parse(cleanedAmount);
          } catch (e) {
            bidAmount = 0.0;
          }
        } else if (amount is num) {
          bidAmount = amount.toDouble();
        }
        earnings += bidAmount;
      }

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
        'totalBids': totalBids,
        'pendingBids': pendingBids,
        'acceptedBids': acceptedBids,
        'rejectedBids': rejectedBids,
      };
    } catch (e) {
      debugPrint('Error fetching worker stats: $e');
      return {
        'bidsPlaced': 0,
        'jobsWon': 0,
        'earnings': 0.0,
        'rating': 'N/A',
        'totalBids': 0,
        'pendingBids': 0,
        'acceptedBids': 0,
        'rejectedBids': 0,
      };
    }
  }

  void _showJobDetails(JobModel job) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => job_details.WorkerJobDetailsScreen( // ← Using the alias
          job: job,
          workerId: _workerId,
          workerCategory: _workerCategory,
          onBidPlaced: () => setState(() {}),
        ),
      ),
    );
  }

  void _showAllJobs() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('common.coming_soon'.tr())),
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

  Widget _buildLoadingScreen() {
    return Column(
      children: [
        Container(
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [CColors.primary, CColors.secondary],
            ),
          ),
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
                  'common.loading_dashboard'.tr(),
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

  Widget _buildJobFeed() {
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

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
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
                      job.category.toUpperCase(),
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

  Widget _buildMyBidsList() {
    if (_workerId.isEmpty) {
      return _buildEmptyState('errors.login_to_view_bids'.tr());
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('bids')
          .where('workerId', isEqualTo: _workerId)
          .orderBy('createdAt', descending: true)
          .limit(5)
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

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final bid = BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
            return _buildBidItem(bid, data);
          },
        );
      },
    );
  }

  Widget _buildBidItem(BidModel bid, Map<String, dynamic> data) {
    final isUrdu = context.locale.languageCode == 'ur';

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('jobs').doc(bid.jobId).get(),
      builder: (context, jobSnapshot) {
        if (jobSnapshot.connectionState == ConnectionState.waiting) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: _getBidStatusColor(bid.status),
              child: Icon(
                _getBidStatusIcon(bid.status),
                size: 20,
                color: Colors.white,
              ),
            ),
            title: Text(
              'common.loading'.tr(),
              style: TextStyle(
                color: CColors.grey,
                fontSize: isUrdu ? 16 : 14,
              ),
            ),
            subtitle: Text(
              '${'bid.amount'.tr()}: ${_formatCurrency(bid.amount)}',
              style: TextStyle(fontSize: isUrdu ? 14 : 12),
            ),
          );
        }

        if (!jobSnapshot.hasData || !jobSnapshot.data!.exists) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: CColors.error,
              child: Icon(Icons.error, size: 20, color: Colors.white),
            ),
            title: Text(
              'job.job_not_found'.tr(),
              style: TextStyle(
                color: CColors.error,
                fontSize: isUrdu ? 16 : 14,
              ),
            ),
            subtitle: Text(
              '${'bid.amount'.tr()}: ${_formatCurrency(bid.amount)}',
              style: TextStyle(fontSize: isUrdu ? 14 : 12),
            ),
          );
        }

        final jobData = jobSnapshot.data!.data() as Map<String, dynamic>;
        final jobTitle = jobData['title'] ?? 'job.unknown'.tr();

        return ListTile(
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
            style: TextStyle(fontSize: isUrdu ? 16 : 14),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${'bid.amount'.tr()}: ${_formatCurrency(bid.amount)}',
                style: TextStyle(fontSize: isUrdu ? 14 : 12),
              ),
              Text(
                '${'bid.status'.tr()}: ${_getBidStatusText(bid.status)}',
                style: TextStyle(
                  color: _getBidStatusColor(bid.status),
                  fontWeight: FontWeight.bold,
                  fontSize: isUrdu ? 14 : 12,
                ),
              ),
            ],
          ),
          trailing: Text(
            timeago.format(bid.createdAt.toDate()),
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              fontSize: isUrdu ? 14 : 12,
            ),
          ),
        );
      },
    );
  }

  String _getBidStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'bid.status_pending'.tr();
      case 'accepted':
        return 'bid.status_accepted'.tr();
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

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(workerLoadingProvider);
    final isUrdu = context.locale.languageCode == 'ur';

    return Scaffold(
      endDrawer: !isUrdu ? const DashboardDrawer() : null,
      drawer: isUrdu ? const DashboardDrawer() : null,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? CColors.dark : CColors.lightGrey,
      body: isLoading
          ? _buildLoadingScreen()
          : RefreshIndicator(
        onRefresh: _loadUserData,
        child: CustomScrollView(
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
                  _buildJobFeed(),
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildSectionHeader(
                    context,
                    'dashboard.my_bids'.tr(),
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
      ),
    );
  }
}