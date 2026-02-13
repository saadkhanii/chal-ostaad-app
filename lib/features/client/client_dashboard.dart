// lib/features/client/client_dashboard.dart
import 'package:chal_ostaad/core/providers/auth_provider.dart';
import 'package:chal_ostaad/features/client/post_job_screen.dart';
import 'package:chal_ostaad/features/client/client_job_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

// Create a state provider for loading
final clientLoadingProvider = StateProvider<bool>((ref) => true);

class ClientDashboard extends ConsumerStatefulWidget {
  const ClientDashboard({super.key});

  @override
  ConsumerState<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends ConsumerState<ClientDashboard> {
  String _userName = 'Client';
  String _clientId = '';
  String _clientEmail = '';
  String _bidFilter = 'all';
  String _jobFilter = 'all';

  final JobService _jobService = JobService();
  final BidService _bidService = BidService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to modify provider state after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserData();
    });
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userUid = prefs.getString('user_uid');
      // Try to get name from prefs first
      String? userName = prefs.getString('user_name');
      String? userEmail = prefs.getString('user_email');

      debugPrint('Loading client data - UID: $userUid, Name: $userName');

      if (userUid != null) {
        // Fetch fresh data from Firestore to ensure we have the correct name
        try {
          final userDoc = await _firestore.collection('users').doc(userUid).get();
          if (userDoc.exists && userDoc.data() != null) {
            final data = userDoc.data()!;
            // Check multiple possible fields for the name
            final fetchedName = data['fullName'] ?? data['name'] ?? data['userName'] ?? userName ?? 'Client';
            final fetchedEmail = data['email'] ?? userEmail ?? '';

            // Update variables
            userName = fetchedName;
            userEmail = fetchedEmail;

            // Update SharedPreferences
            await prefs.setString('user_name', fetchedName);
            await prefs.setString('user_email', fetchedEmail);
          }
        } catch (e) {
          debugPrint('Error fetching user data from Firestore: $e');
        }

        if (mounted) {
          setState(() {
            _clientId = userUid;
            _userName = userName ?? 'Client';
            _clientEmail = userEmail ?? '';
          });
          ref.read(clientLoadingProvider.notifier).state = false;
        }
        _debugJobPosting();
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
      isScrollControlled: true, // Better for bottom sheets with content
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(CSizes.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Job Actions',
                style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: CSizes.lg),

              // View Details - Always available
              _buildActionTile(
                context,
                icon: Icons.remove_red_eye,
                title: 'View Details',
                color: CColors.info,
                onTap: () {
                  Navigator.pop(context);
                  _showJobDetails(job);
                },
              ),
              const SizedBox(height: CSizes.sm),

              if (job.status == 'open') ...[
                _buildActionTile(
                  context,
                  icon: Icons.edit,
                  title: 'Edit Job',
                  color: CColors.info,
                  onTap: () => _editJob(job),
                ),
                const SizedBox(height: CSizes.sm),
                _buildActionTile(
                  context,
                  icon: Icons.cancel,
                  title: 'Cancel Job',
                  color: CColors.warning,
                  onTap: () => _cancelJob(job.id!),
                ),
                const SizedBox(height: CSizes.sm),
              ],

              if (job.status == 'in-progress') ...[
                _buildActionTile(
                  context,
                  icon: Icons.check_circle,
                  title: 'Mark as Completed',
                  color: CColors.success,
                  onTap: () => _markJobAsCompleted(job.id!),
                ),
                const SizedBox(height: CSizes.sm),
                _buildActionTile(
                  context,
                  icon: Icons.cancel,
                  title: 'Cancel Job',
                  color: CColors.warning,
                  onTap: () => _cancelJob(job.id!),
                ),
                const SizedBox(height: CSizes.sm),
              ],

              if (job.status == 'completed') ...[
                _buildActionTile(
                  context,
                  icon: Icons.replay,
                  title: 'Reopen Job',
                  color: CColors.info,
                  onTap: () => _reopenJob(job.id!),
                ),
                const SizedBox(height: CSizes.sm),
              ],

              // Delete Job - Always available (with confirmation)
              _buildActionTile(
                context,
                icon: Icons.delete,
                title: 'Delete Job',
                color: CColors.error,
                onTap: () => _deleteJob(job.id!),
              ),

              const SizedBox(height: CSizes.lg),
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

  Future<void> _markJobAsCompleted(String jobId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Complete Job'),
          content: const Text('Are you sure you want to mark this job as completed?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: CColors.success),
              child: const Text('Yes, Complete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _updateJobStatus(jobId, 'completed');
    }
  }

  Future<void> _deleteJob(String jobId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Job'),
          content: const Text('Are you sure you want to delete this job? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: CColors.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await _jobService.deleteJob(jobId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Job deleted successfully'),
              backgroundColor: CColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete job: $e'),
              backgroundColor: CColors.error,
            ),
          );
        }
      }
    }
  }

  void _showAllJobs() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Show all jobs - Coming Soon!')),
    );
  }

  Widget _buildLoadingScreen() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildOpportunityCard(BuildContext context) {

    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            'Post a New Job',
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              color: CColors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: CSizes.sm),
          Text(
            'Find skilled workers for your needs',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: CColors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: CSizes.lg),
          ElevatedButton(
            onPressed: _navigateToPostJob,
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.white,
              foregroundColor: CColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Post Now'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, {String? actionText, VoidCallback? onAction, bool showAction = true}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (showAction && actionText != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionText),
          ),
      ],
    );
  }

  // ========== UPDATED: Dynamic Stats Row with Rupees ==========
  Widget _buildStatsRow(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchClientStats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingStats(context);
        }

        if (snapshot.hasError) {
          return _buildStatItem(context, 'Error', '!', Icons.error);
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
            _buildStatItem(context, 'Posted Jobs', '${stats['postedJobs']}', Icons.work_outline),
            _buildStatItem(context, 'Active Jobs', '${stats['activeJobs']}', Icons.work),
            _buildStatItem(context, 'Completed', '${stats['completedJobs']}', Icons.check_circle),
            _buildStatItem(context, 'Total Spent', _formatCurrency(stats['totalSpent']), Icons.attach_money),
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
      // Fetch all jobs for this client
      final jobsSnapshot = await _firestore
          .collection('jobs')
          .where('clientId', isEqualTo: _clientId)
          .get();

      final jobs = jobsSnapshot.docs;

      // Calculate basic stats
      final postedJobs = jobs.length;
      final activeJobs = jobs.where((doc) => doc['status'] == 'in-progress').length;
      final completedJobs = jobs.where((doc) => doc['status'] == 'completed').length;

      // Get completed job IDs
      final completedJobIds = jobs
          .where((doc) => doc['status'] == 'completed')
          .map((doc) => doc.id)
          .toList();

      // Calculate total spent from accepted bids
      double totalSpent = 0.0;
      if (completedJobIds.isNotEmpty) {
        final bidsSnapshot = await _firestore
            .collection('bids')
            .where('jobId', whereIn: completedJobIds)
            .where('status', isEqualTo: 'accepted')
            .get();

        totalSpent = bidsSnapshot.docs.fold(0.0, (sum, doc) {
          final amount = doc['amount'] as num? ?? 0;
          return sum + amount.toDouble();
        });
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
        _buildStatItem(context, 'Posted Jobs', '...', Icons.work_outline),
        _buildStatItem(context, 'Active Jobs', '...', Icons.work),
        _buildStatItem(context, 'Completed', '...', Icons.check_circle),
        _buildStatItem(context, 'Total Spent', '...', Icons.attach_money),
      ],
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: CColors.primary, size: 28),
        const SizedBox(height: 8),
        Text(value, style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  // Format currency in Pakistani Rupees
  String _formatCurrency(double amount) {
    if (amount == 0) return 'Rs 0';

    if (amount >= 10000000) { // 1 Crore
      return 'Rs ${(amount / 10000000).toStringAsFixed(1)}Cr';
    } else if (amount >= 100000) { // 1 Lakh
      return 'Rs ${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) { // 1 Thousand
      return 'Rs ${(amount / 1000).toStringAsFixed(1)}k';
    }

    return 'Rs ${amount.toStringAsFixed(0)}';
  }

  Widget _buildJobFilterChips() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ['All', 'Open', 'In Progress', 'Completed'].map((filter) {
          final isSelected = _jobFilter.toLowerCase() == filter.toLowerCase().replaceAll(' ', '-');
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _jobFilter = filter.toLowerCase().replaceAll(' ', '-');
                    if (_jobFilter == 'all') _jobFilter = 'all';
                  });
                }
              },
              // FIXED: Active and Inactive styling for light and dark themes
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

  Widget _buildJobList() {
    if (_clientId.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('Please log in to view your jobs')),
      );
    }

    Query query = _firestore.collection('jobs')
        .where('clientId', isEqualTo: _clientId)
        .orderBy('createdAt', descending: true);

    if (_jobFilter != 'all') {
      query = query.where('status', isEqualTo: _jobFilter);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          debugPrint('Error fetching jobs: ${snapshot.error}');
          return SizedBox(
            height: 200,
            child: Center(child: Text('Error loading jobs: ${snapshot.error}')),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox(
            height: 200,
            child: Center(child: Text('No jobs found. Post a job to get started!')),
          );
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
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(job.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _getStatusColor(job.status)),
                    ),
                    child: Text(
                      job.status.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: _getStatusColor(job.status),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CSizes.sm),
              Text(
                job.description,
                style: Theme.of(context).textTheme.bodyMedium,
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
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  FutureBuilder<int>(
                    future: _getBidCountForJob(job.id!),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return Row(
                        children: [
                          Icon(Icons.gavel, size: 16, color: CColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            '$count Bids',
                            style: Theme.of(context).textTheme.labelMedium!.copyWith(
                              color: CColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(width: CSizes.md),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showJobActions(job),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLoading = ref.watch(clientLoadingProvider);

    return Scaffold(
      endDrawer: const DashboardDrawer(),
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToPostJob,
        backgroundColor: CColors.primary,
        foregroundColor: CColors.white,
        child: const Icon(Icons.add),
      ),
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
                  _buildJobList(), // ADDED: Display the job list
                  const SizedBox(height: CSizes.spaceBtwSections),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}