// lib/features/client/client_dashboard.dart
import 'package:chal_ostaad/features/client/post_job_screen.dart';
import 'package:chal_ostaad/features/client/client_job_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/bid_model.dart';
import '../../core/models/job_model.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/job_service.dart';
import '../../shared/widgets/dashboard_drawer.dart';
import 'client_dashboard_header.dart';

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  String _userName = 'Client';
  String _clientId = '';
  String _clientEmail = '';
  bool _isLoading = true;
  String _bidFilter = 'all';
  String _jobFilter = 'all';

  final JobService _jobService = JobService();
  final BidService _bidService = BidService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
      final userEmail = prefs.getString('user_email');

      debugPrint('Loading client data - UID: $userUid, Name: $userName');

      if (userUid != null) {
        setState(() {
          _clientId = userUid;
          _userName = userName ?? 'Client';
          _clientEmail = userEmail ?? '';
          _isLoading = false;
        });
        _debugJobPosting();
      } else {
        debugPrint('No user UID found in SharedPreferences');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading client data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _debugJobPosting() {
    if (_clientId.isNotEmpty) {
      debugPrint('=== DEBUG JOB POSTING ===');
      debugPrint('Client ID: $_clientId');
      debugPrint('Client Name: $_userName');
      debugPrint('Client Email: $_clientEmail');

      FirebaseFirestore.instance
          .collection('jobs')
          .where('clientId', isEqualTo: _clientId)
          .get()
          .then((snapshot) {
        debugPrint('Total jobs found for client: ${snapshot.docs.length}');
        for (var doc in snapshot.docs) {
          final data = doc.data();
          debugPrint('Job: ${doc.id} - ${data['title']} - Status: ${data['status']}');
        }
      }).catchError((e) {
        debugPrint('Error checking jobs: $e');
      });
    }
  }

  Future<int> _getBidCountForJob(String jobId) async {
    try {
      final bids = await _bidService.getBidsByJob(jobId);
      return bids.length;
    } catch (e) {
      debugPrint('Error getting bid count for job $jobId: $e');
      if (e.toString().contains('index') || e.toString().contains('FAILED_PRECONDITION')) {
        return 0;
      }
      return 0;
    }
  }

  void _navigateToPostJob() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PostJobScreen()),
    ).then((_) {
      setState(() {});
    });
  }

  void _showJobDetails(JobModel job) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClientJobDetailsScreen(job: job),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return CColors.info;
      case 'in-progress':
        return CColors.warning;
      case 'completed':
        return CColors.success;
      case 'cancelled':
        return CColors.error;
      default:
        return CColors.grey;
    }
  }

  Future<void> _updateJobStatus(String jobId, String newStatus) async {
    try {
      await _jobService.updateJobStatus(jobId, newStatus);

      String message = '';
      switch (newStatus) {
        case 'completed':
          message = 'Job marked as completed!';
          break;
        case 'cancelled':
          message = 'Job cancelled!';
          break;
        case 'in-progress':
          message = 'Job started!';
          break;
        case 'open':
          message = 'Job reopened!';
          break;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: CColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update job: $e'),
            backgroundColor: CColors.error,
          ),
        );
      }
    }
  }

  void _showJobActions(JobModel job) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(CSizes.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Job Actions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: CSizes.md),

              if (job.status == 'open') ...[
                _buildActionTile(
                  context,
                  icon: Icons.edit,
                  title: 'Edit Job',
                  color: CColors.info,
                  onTap: () => _editJob(job),
                ),
                _buildActionTile(
                  context,
                  icon: Icons.cancel,
                  title: 'Cancel Job',
                  color: CColors.warning,
                  onTap: () => _cancelJob(job.id!),
                ),
              ],

              if (job.status == 'in-progress') ...[
                _buildActionTile(
                  context,
                  icon: Icons.check_circle,
                  title: 'Mark Complete',
                  color: CColors.success,
                  onTap: () => _markJobAsCompleted(job.id!),
                ),
                _buildActionTile(
                  context,
                  icon: Icons.cancel,
                  title: 'Cancel Job',
                  color: CColors.warning,
                  onTap: () => _cancelJob(job.id!),
                ),
              ],

              if (job.status == 'completed') ...[
                _buildActionTile(
                  context,
                  icon: Icons.replay,
                  title: 'Reopen Job',
                  color: CColors.info,
                  onTap: () => _reopenJob(job.id!),
                ),
              ],

              _buildActionTile(
                context,
                icon: Icons.delete,
                title: 'Delete Job',
                color: CColors.error,
                onTap: () => _deleteJob(job.id!),
              ),

              const SizedBox(height: CSizes.md),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionTile(BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  Future<void> _editJob(JobModel job) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit Job - Coming Soon!')),
    );
  }

  Future<void> _cancelJob(String jobId) async {
    bool? confirmCancel = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cancel Job'),
          content: const Text('Are you sure you want to cancel this job?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: CColors.error),
              child: const Text('Yes, Cancel'),
            ),
          ],
        );
      },
    );

    if (confirmCancel == true) {
      await _updateJobStatus(jobId, 'cancelled');
    }
  }

  Future<void> _reopenJob(String jobId) async {
    await _updateJobStatus(jobId, 'open');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      endDrawer: const DashboardDrawer(),
      backgroundColor: isDark ? CColors.dark : CColors.light,
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToPostJob,
        backgroundColor: CColors.primary,
        foregroundColor: CColors.white,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? _buildLoadingScreen()
          : RefreshIndicator(
        onRefresh: _loadUserData,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  ClientDashboardHeader(
                    userName: _userName,
                    onNotificationTap: _showNotifications,
                  ),
                ],
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildWelcomeSection(context),
                  const SizedBox(height: CSizes.spaceBtwSections),

                  _buildSectionHeader(
                    context,
                    'Project Overview',
                    showAction: false,
                  ),
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildStatsRow(context),
                  const SizedBox(height: CSizes.spaceBtwSections),

                  _buildSectionHeader(
                    context,
                    'My Posted Jobs',
                    actionText: 'View All',
                    onAction: () => _showAllJobs(),
                  ),
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildJobFilterChips(),
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildMyJobsList(),
                  const SizedBox(height: CSizes.spaceBtwSections),

                  _buildSectionHeader(
                    context,
                    'Recent Bids',
                    showAction: false,
                  ),
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildBidFilterChips(),
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildRecentBidsList(),
                  const SizedBox(height: CSizes.spaceBtwSections * 2),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAllJobs() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All Jobs Screen - Coming Soon!')),
    );
  }

  void _showNotifications() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notifications'),
        content: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('bids')
              .where('clientId', isEqualTo: _clientId)
              .where('status', isEqualTo: 'pending')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final bids = snapshot.data!.docs;
            if (bids.isEmpty) {
              return const Text('No new notifications');
            }

            return SizedBox(
              height: 300,
              width: 400,
              child: ListView.builder(
                itemCount: bids.length,
                itemBuilder: (context, index) {
                  final bid = BidModel.fromSnapshot(bids[index] as DocumentSnapshot<Map<String, dynamic>>);
                  return ListTile(
                    leading: const Icon(Icons.gavel),
                    title: Text('New bid: Rs. ${bid.amount}'),
                    subtitle: Text('Job: ${bid.jobId.substring(0, 8)}...'),
                    trailing: Text(timeago.format(bid.createdAt.toDate())),
                  );
                },
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // UI Building Methods
  Widget _buildWelcomeSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
                Icon(Icons.rocket_launch_outlined, size: 14, color: CColors.white),
                const SizedBox(width: 6),
                Text(
                  'WELCOME BACK',
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
            'Hello, $_userName!',
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              color: CColors.white,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ready to find the perfect professional for your project?',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: CColors.white.withOpacity(0.9),
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _navigateToPostJob,
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.white,
              foregroundColor: CColors.primary,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
            child: const Text(
              'Post New Job',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, {
    String? actionText, VoidCallback? onAction, bool showAction = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? CColors.textWhite : CColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showAction && actionText != null && onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: CColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CColors.primary.withOpacity(0.3)),
              ),
              child: Text(
                actionText,
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color: CColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildJobFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('All Jobs', 'all', _jobFilter, (value) => setState(() => _jobFilter = value)),
          _buildFilterChip('Open', 'open', _jobFilter, (value) => setState(() => _jobFilter = value)),
          _buildFilterChip('In Progress', 'in-progress', _jobFilter, (value) => setState(() => _jobFilter = value)),
          _buildFilterChip('Completed', 'completed', _jobFilter, (value) => setState(() => _jobFilter = value)),
        ],
      ),
    );
  }

  Widget _buildBidFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('All Bids', 'all', _bidFilter, (value) => setState(() => _bidFilter = value)),
          _buildFilterChip('Pending', 'pending', _bidFilter, (value) => setState(() => _bidFilter = value)),
          _buildFilterChip('Accepted', 'accepted', _bidFilter, (value) => setState(() => _bidFilter = value)),
          _buildFilterChip('Rejected', 'rejected', _bidFilter, (value) => setState(() => _bidFilter = value)),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, String currentValue, ValueChanged<String> onSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: currentValue == value,
        onSelected: (selected) => onSelected(value),
        backgroundColor: Colors.transparent,
        selectedColor: CColors.primary.withOpacity(0.2),
        checkmarkColor: CColors.primary,
        labelStyle: TextStyle(
          color: currentValue == value ? CColors.primary : CColors.darkGrey,
        ),
        shape: StadiumBorder(
          side: BorderSide(
            color: currentValue == value ? CColors.primary : CColors.borderPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Column(
      children: [
        Container(
          height: 200,
          color: CColors.primary,
          child: const Center(child: CircularProgressIndicator(color: CColors.white)),
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
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: CColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    if (_clientId.isEmpty) return _buildStatsLoading();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('jobs').where('clientId', isEqualTo: _clientId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return _buildStatsLoading();

        final jobs = snapshot.data!.docs;
        final activeJobs = jobs.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'open').length;
        final inProgressJobs = jobs.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'in-progress').length;
        final completedJobs = jobs.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'completed').length;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('bids').where('clientId', isEqualTo: _clientId).snapshots(),
          builder: (context, bidSnapshot) {
            if (!bidSnapshot.hasData) return _buildStatsLoading();

            final totalBids = bidSnapshot.data!.docs.length;

            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 2.2,
              mainAxisSpacing: CSizes.spaceBtwItems,
              crossAxisSpacing: CSizes.spaceBtwItems,
              children: [
                _buildStatCard(context, icon: Icons.assignment_outlined, value: activeJobs.toString(), label: 'Active Jobs', color: CColors.info),
                _buildStatCard(context, icon: Icons.timelapse_outlined, value: inProgressJobs.toString(), label: 'In Progress', color: CColors.warning),
                _buildStatCard(context, icon: Icons.gavel_outlined, value: totalBids.toString(), label: 'Total Bids', color: CColors.primary),
                _buildStatCard(context, icon: Icons.check_circle_outlined, value: completedJobs.toString(), label: 'Completed', color: CColors.success),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard(BuildContext context, {
    required IconData icon, required String value, required String label, required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(CSizes.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        color: isDark ? CColors.darkContainer : CColors.white,
        border: Border.all(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w700, color: isDark ? CColors.textWhite : CColors.textPrimary, fontSize: 12)),
              Text(label, style: Theme.of(context).textTheme.labelSmall!.copyWith(color: CColors.darkGrey, fontSize: 8)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsLoading() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.5,
      mainAxisSpacing: CSizes.spaceBtwItems,
      crossAxisSpacing: CSizes.spaceBtwItems,
      children: [
        _buildStatCard(context, icon: Icons.assignment_outlined, value: '0', label: 'Loading...', color: CColors.grey),
        _buildStatCard(context, icon: Icons.timelapse_outlined, value: '0', label: 'Loading...', color: CColors.grey),
        _buildStatCard(context, icon: Icons.gavel_outlined, value: '0', label: 'Loading...', color: CColors.grey),
        _buildStatCard(context, icon: Icons.check_circle_outlined, value: '0', label: 'Loading...', color: CColors.grey),
      ],
    );
  }

  Widget _buildMyJobsList() {
    if (_clientId.isEmpty) {
      return _buildEmptyState(context, icon: Icons.work_outline, title: 'Loading...', subtitle: 'Please wait while we load your jobs', actionText: null, onAction: null);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('jobs').where('clientId', isEqualTo: _clientId).orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return _buildLoadingState();

        if (snapshot.hasError) {
          debugPrint('CLIENT JOBS FIRESTORE ERROR: ${snapshot.error}');
          final error = snapshot.error.toString();
          if (error.contains('index') || error.contains('FAILED_PRECONDITION')) {
            return _buildIndexErrorState(context, 'Database indexes are being created...', 'This may take a few minutes. Please wait or try again shortly.', onRetry: () => setState(() {}));
          }
          return _buildErrorState(context, 'Failed to load your jobs: ${snapshot.error}', onRetry: () => setState(() {}));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState(context, icon: Icons.work_outline, title: 'No jobs posted yet', subtitle: 'Post your first job to start receiving bids from skilled workers', actionText: 'Post Your First Job', onAction: _navigateToPostJob);
        }

        final jobDocs = snapshot.data!.docs;
        debugPrint('CLIENT: Loaded ${jobDocs.length} jobs for client $_clientId');

        List<DocumentSnapshot> filteredJobs = _jobFilter == 'all' ? jobDocs : jobDocs.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == _jobFilter).toList();
        final displayJobs = filteredJobs.take(3).toList();

        return Column(
          children: [
            ...displayJobs.map((doc) {
              try {
                final job = JobModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
                return _buildJobCard(job);
              } catch (e) {
                debugPrint('Error parsing job document: $e');
                return _buildErrorCard(context, 'Failed to load job details');
              }
            }),
            if (filteredJobs.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: CSizes.md),
                child: TextButton(onPressed: _showAllJobs, child: const Text('View All Jobs')),
              ),
          ],
        );
      },
    );
  }

  Widget _buildJobCard(JobModel job) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: CSizes.spaceBtwItems),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: isDark ? CColors.darkContainer : CColors.white,
        border: Border.all(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showJobDetails(job),
          onLongPress: () => _showJobActions(job),
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          child: Padding(
            padding: const EdgeInsets.all(CSizes.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: _getStatusColor(job.status).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: Text(job.status.toUpperCase(), style: Theme.of(context).textTheme.labelSmall!.copyWith(color: _getStatusColor(job.status), fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: CColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: Text(job.category, style: Theme.of(context).textTheme.labelSmall!.copyWith(color: CColors.primary, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.more_vert, size: 18, color: CColors.darkGrey),
                      onPressed: () => _showJobActions(job),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(job.title, style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w600, color: isDark ? CColors.textWhite : CColors.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Text(job.description, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: isDark ? CColors.textWhite.withOpacity(0.7) : CColors.darkerGrey), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                FutureBuilder<int>(
                  future: _getBidCountForJob(job.id!),
                  builder: (context, snapshot) {
                    final bidCount = snapshot.data ?? 0;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text('$bidCount ${bidCount == 1 ? 'Bid' : 'Bids'} Received', style: Theme.of(context).textTheme.bodySmall!.copyWith(color: CColors.primary, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        Text('Details →', style: Theme.of(context).textTheme.bodySmall!.copyWith(color: CColors.primary, fontWeight: FontWeight.w600)),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentBidsList() {
    if (_clientId.isEmpty) {
      return _buildEmptyState(context, icon: Icons.gavel_outlined, title: 'Loading...', subtitle: 'Please wait while we load your bids', actionText: null, onAction: null);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('bids').where('clientId', isEqualTo: _clientId).orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return _buildLoadingState();

        if (snapshot.hasError) {
          debugPrint('CLIENT BIDS FIRESTORE ERROR: ${snapshot.error}');
          final error = snapshot.error.toString();
          if (error.contains('index') || error.contains('FAILED_PRECONDITION')) {
            return _buildIndexErrorState(context, 'Database indexes are being created...', 'Bids will load automatically once indexes are ready.', onRetry: () => setState(() {}));
          }
          return _buildErrorState(context, 'Failed to load bids: ${snapshot.error}', onRetry: () => setState(() {}));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState(context, icon: Icons.gavel_outlined, title: 'No bids received yet', subtitle: 'Bids will appear here when workers apply to your jobs', actionText: 'Post a Job', onAction: _navigateToPostJob);
        }

        final bidDocs = snapshot.data!.docs;
        debugPrint('CLIENT: Loaded ${bidDocs.length} bids for client $_clientId');

        List<DocumentSnapshot> filteredBids = _bidFilter == 'all' ? bidDocs : bidDocs.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == _bidFilter).toList();
        final recentBids = filteredBids.take(3).toList();

        return Column(
          children: [
            ...recentBids.map((doc) {
              try {
                final bid = BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
                return _buildBidCard(bid);
              } catch (e) {
                debugPrint('Error parsing bid document: $e');
                return _buildErrorCard(context, 'Failed to load bid details');
              }
            }),
            if (filteredBids.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: CSizes.md),
                child: TextButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('View All Bids - Coming Soon!'))),
                  child: const Text('View All Bids'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBidCard(BidModel bid) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: CSizes.spaceBtwItems),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        color: isDark ? CColors.darkContainer : CColors.white,
        border: Border.all(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CSizes.md),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: CColors.primary.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.person_outline, size: 20, color: CColors.primary),
            ),
            const SizedBox(width: CSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bid: Rs. ${bid.amount}', style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: isDark ? CColors.textWhite : CColors.textPrimary)),
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('workers').doc(bid.workerId).get(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data!.exists) {
                        final workerData = snapshot.data!.data() as Map<String, dynamic>;
                        final workerName = workerData['name'] ?? 'Unknown Worker';
                        final workerEmail = workerData['email'] ?? '';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Worker: $workerName', style: Theme.of(context).textTheme.bodySmall!.copyWith(color: CColors.darkGrey)),
                            if (workerEmail.isNotEmpty) Text(workerEmail, style: Theme.of(context).textTheme.bodySmall!.copyWith(color: CColors.darkGrey, fontSize: 10)),
                          ],
                        );
                      }
                      return Text('Worker: ${bid.workerId.substring(0, 8)}...', style: Theme.of(context).textTheme.bodySmall!.copyWith(color: CColors.darkGrey));
                    },
                  ),
                  if (bid.message != null && bid.message!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('"${bid.message!}"', style: Theme.of(context).textTheme.bodySmall!.copyWith(color: CColors.darkGrey, fontStyle: FontStyle.italic), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: _getBidStatusColor(bid.status).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Text(bid.status.toUpperCase(), style: Theme.of(context).textTheme.labelSmall!.copyWith(color: _getBidStatusColor(bid.status), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBidStatusColor(String status) {
    switch (status) {
      case 'pending': return CColors.warning;
      case 'accepted': return CColors.success;
      case 'rejected': return CColors.error;
      default: return CColors.grey;
    }
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40.0),
      child: const Column(children: [CircularProgressIndicator(), SizedBox(height: CSizes.md), Text('Loading...')]),
    );
  }

  Widget _buildErrorState(BuildContext context, String error, {VoidCallback? onRetry}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(CSizes.cardRadiusMd), color: isDark ? CColors.darkContainer : CColors.lightContainer),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 40, color: CColors.error),
          const SizedBox(height: CSizes.md),
          Text('Loading Error', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: CSizes.sm),
          Text(error, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: CColors.darkGrey), textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: CSizes.md),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }

  Widget _buildIndexErrorState(BuildContext context, String title, String subtitle, {VoidCallback? onRetry}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(CSizes.cardRadiusMd), color: isDark ? CColors.darkContainer : CColors.lightContainer),
      child: Column(
        children: [
          Icon(Icons.sync_outlined, size: 40, color: CColors.warning),
          const SizedBox(height: CSizes.md),
          Text(title, style: Theme.of(context).textTheme.titleMedium!.copyWith(color: CColors.warning), textAlign: TextAlign.center),
          const SizedBox(height: CSizes.sm),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: CColors.darkGrey), textAlign: TextAlign.center),
          const SizedBox(height: CSizes.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(CColors.warning), strokeWidth: 2),
              const SizedBox(width: CSizes.md),
              if (onRetry != null) ElevatedButton(onPressed: onRetry, style: ElevatedButton.styleFrom(backgroundColor: CColors.warning, foregroundColor: CColors.white), child: const Text('Retry')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: CSizes.spaceBtwItems),
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(CSizes.cardRadiusMd), color: isDark ? CColors.darkContainer : CColors.lightContainer, border: Border.all(color: CColors.error.withOpacity(0.3))),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: CColors.error),
          const SizedBox(width: CSizes.sm),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: CColors.darkGrey))),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {
    required IconData icon, required String title, required String subtitle, required String? actionText, required VoidCallback? onAction,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20.0),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(CSizes.cardRadiusLg), color: isDark ? CColors.darkContainer : CColors.lightContainer, border: Border.all(color: isDark ? CColors.darkerGrey : CColors.borderPrimary)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 60, color: CColors.darkGrey.withOpacity(0.5)),
          const SizedBox(height: CSizes.lg),
          Text(title, style: Theme.of(context).textTheme.titleLarge!.copyWith(color: isDark ? CColors.textWhite : CColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: CSizes.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Text(subtitle, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: CColors.darkGrey), textAlign: TextAlign.center),
          ),
          if (actionText != null && onAction != null) ...[
            const SizedBox(height: CSizes.lg),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(backgroundColor: CColors.primary, foregroundColor: CColors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              child: Text(actionText),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _markJobAsCompleted(String jobId) async {
    bool? confirmComplete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Mark as Completed'),
          content: const Text('Are you sure you want to mark this job as completed?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(context).pop(true), style: TextButton.styleFrom(foregroundColor: CColors.success), child: const Text('Complete')),
          ],
        );
      },
    );

    if (confirmComplete == true) await _updateJobStatus(jobId, 'completed');
  }

  Future<void> _deleteJob(String jobId) async {
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Job'),
          content: const Text('Are you sure you want to delete this job? This action cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(context).pop(true), style: TextButton.styleFrom(foregroundColor: CColors.error), child: const Text('Delete')),
          ],
        );
      },
    );

    if (confirmDelete != true) return;

    try {
      final bids = await _bidService.getBidsByJob(jobId);
      for (final bid in bids) {
        await _firestore.collection('bids').doc(bid.id).delete();
      }
      await _jobService.deleteJob(jobId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job deleted successfully!'), backgroundColor: CColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete job: $e'), backgroundColor: CColors.error));
      }
    }
  }
}