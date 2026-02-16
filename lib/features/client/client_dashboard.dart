// lib/features/client/client_dashboard.dart
import 'package:chal_ostaad/core/providers/auth_provider.dart';
import 'package:chal_ostaad/features/client/post_job_screen.dart';
import 'package:chal_ostaad/features/client/client_job_details_screen.dart';
import 'package:chal_ostaad/features/notifications/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/bid_model.dart';
import '../../core/models/job_model.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/job_service.dart';
import '../../shared/widgets/dashboard_drawer.dart';
import '../../shared/widgets/curved_nav_bar.dart';
import 'client_dashboard_header.dart';
import 'my_jobs_screen.dart';

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
  String _bidFilter = 'all';
  String _jobFilter = 'all';

  // Create separate controllers for each scrollable page
  final ScrollController _homeScrollController = ScrollController();
  final ScrollController _myJobsScrollController = ScrollController();
  final ScrollController _notificationsScrollController = ScrollController();

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
    _homeScrollController.dispose();
    _myJobsScrollController.dispose();
    _notificationsScrollController.dispose();
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

  String _getStatusText(String status) {
    switch (status) {
      case 'open':
        return 'job.status_open'.tr();
      case 'in-progress':
        return 'job.status_in_progress'.tr();
      case 'completed':
        return 'job.status_completed'.tr();
      case 'cancelled':
        return 'job.status_cancelled'.tr();
      default:
        return status;
    }
  }

  Future<void> _updateJobStatus(String jobId, String newStatus) async {
    try {
      await _jobService.updateJobStatus(jobId, newStatus);

      String message = '';
      switch (newStatus) {
        case 'completed':
          message = 'job.job_completed'.tr();
          break;
        case 'cancelled':
          message = 'job.job_cancelled'.tr();
          break;
        case 'in-progress':
          message = 'job.job_started'.tr();
          break;
        case 'open':
          message = 'job.job_reopened'.tr();
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
            content: Text('errors.update_failed'.tr(args: [e.toString()])),
            backgroundColor: CColors.error,
          ),
        );
      }
    }
  }

  void _showJobActions(JobModel job) {
    final isUrdu = context.locale.languageCode == 'ur';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(CSizes.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'job.job_actions'.tr(),
                style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: isUrdu ? 22 : 20,
                ),
              ),
              const SizedBox(height: CSizes.lg),

              _buildActionTile(
                context,
                icon: Icons.remove_red_eye,
                title: 'job.view_details'.tr(),
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
                  title: 'job.edit_job'.tr(),
                  color: CColors.info,
                  onTap: () => _editJob(job),
                ),
                const SizedBox(height: CSizes.sm),
                _buildActionTile(
                  context,
                  icon: Icons.cancel,
                  title: 'job.cancel_job'.tr(),
                  color: CColors.warning,
                  onTap: () => _cancelJob(job.id!),
                ),
                const SizedBox(height: CSizes.sm),
              ],

              if (job.status == 'in-progress') ...[
                _buildActionTile(
                  context,
                  icon: Icons.check_circle,
                  title: 'job.mark_completed'.tr(),
                  color: CColors.success,
                  onTap: () => _markJobAsCompleted(job.id!),
                ),
                const SizedBox(height: CSizes.sm),
                _buildActionTile(
                  context,
                  icon: Icons.cancel,
                  title: 'job.cancel_job'.tr(),
                  color: CColors.warning,
                  onTap: () => _cancelJob(job.id!),
                ),
                const SizedBox(height: CSizes.sm),
              ],

              if (job.status == 'completed') ...[
                _buildActionTile(
                  context,
                  icon: Icons.replay,
                  title: 'job.reopen_job'.tr(),
                  color: CColors.info,
                  onTap: () => _reopenJob(job.id!),
                ),
                const SizedBox(height: CSizes.sm),
              ],

              _buildActionTile(
                context,
                icon: Icons.delete,
                title: 'job.delete_job'.tr(),
                color: CColors.error,
                onTap: () => _deleteJob(job.id!),
              ),

              const SizedBox(height: CSizes.lg),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text('common.close'.tr()),
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
    final isUrdu = context.locale.languageCode == 'ur';

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(fontSize: isUrdu ? 18 : 16),
      ),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  Future<void> _editJob(JobModel job) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('common.coming_soon'.tr())),
    );
  }

  Future<void> _cancelJob(String jobId) async {
    bool? confirmCancel = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final isUrdu = context.locale.languageCode == 'ur';

        return AlertDialog(
          title: Text(
            'job.cancel_job'.tr(),
            style: TextStyle(fontSize: isUrdu ? 22 : 20),
          ),
          content: Text(
            'job.confirm_cancel'.tr(),
            style: TextStyle(fontSize: isUrdu ? 16 : 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'common.no'.tr(),
                style: TextStyle(fontSize: isUrdu ? 16 : 14),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: CColors.error),
              child: Text(
                'job.yes_cancel'.tr(),
                style: TextStyle(fontSize: isUrdu ? 16 : 14),
              ),
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
        final isUrdu = context.locale.languageCode == 'ur';

        return AlertDialog(
          title: Text(
            'job.complete_job'.tr(),
            style: TextStyle(fontSize: isUrdu ? 22 : 20),
          ),
          content: Text(
            'job.confirm_complete'.tr(),
            style: TextStyle(fontSize: isUrdu ? 16 : 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'common.no'.tr(),
                style: TextStyle(fontSize: isUrdu ? 16 : 14),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: CColors.success),
              child: Text(
                'job.yes_complete'.tr(),
                style: TextStyle(fontSize: isUrdu ? 16 : 14),
              ),
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
        final isUrdu = context.locale.languageCode == 'ur';

        return AlertDialog(
          title: Text(
            'job.delete_job'.tr(),
            style: TextStyle(fontSize: isUrdu ? 22 : 20),
          ),
          content: Text(
            'job.confirm_delete'.tr(),
            style: TextStyle(fontSize: isUrdu ? 16 : 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'common.cancel'.tr(),
                style: TextStyle(fontSize: isUrdu ? 16 : 14),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: CColors.error),
              child: Text(
                'job.delete'.tr(),
                style: TextStyle(fontSize: isUrdu ? 16 : 14),
              ),
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
            SnackBar(
              content: Text('job.job_deleted'.tr()),
              backgroundColor: CColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('errors.delete_failed'.tr(args: [e.toString()])),
              backgroundColor: CColors.error,
            ),
          );
        }
      }
    }
  }

  void _showAllJobs() {
    // Navigate to My Jobs tab (index 0)
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
            onPressed: _navigateToPostJob,
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

      final completedJobIds = jobs
          .where((doc) => doc['status'] == 'completed')
          .map((doc) => doc.id)
          .toList();

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

  Widget _buildJobFilterChips() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    final filters = [
      'common.all'.tr(),
      'job.status_open'.tr(),
      'job.status_in_progress'.tr(),
      'job.status_completed'.tr(),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.asMap().entries.map((entry) {
          final index = entry.key;
          final filter = entry.value;
          final filterKey = ['all', 'open', 'in-progress', 'completed'][index];
          final isSelected = _jobFilter == filterKey;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(
                filter,
                style: TextStyle(fontSize: isUrdu ? 14 : 12),
              ),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _jobFilter = filterKey;
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

  Widget _buildJobList() {
    if (_clientId.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'job.login_to_view'.tr(),
            style: TextStyle(fontSize: context.locale.languageCode == 'ur' ? 16 : 14),
          ),
        ),
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
            child: Center(
              child: Text(
                '${'errors.jobs_load_failed'.tr()}: ${snapshot.error}',
                style: TextStyle(fontSize: context.locale.languageCode == 'ur' ? 16 : 14),
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return SizedBox(
            height: 200,
            child: Center(
              child: Text(
                'job.no_jobs_found'.tr(),
                style: TextStyle(fontSize: context.locale.languageCode == 'ur' ? 16 : 14),
              ),
            ),
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
                      color: _getStatusColor(job.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _getStatusColor(job.status)),
                    ),
                    child: Text(
                      _getStatusText(job.status),
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: _getStatusColor(job.status),
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
                  FutureBuilder<int>(
                    future: _getBidCountForJob(job.id!),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return Row(
                        children: [
                          Icon(Icons.gavel, size: 16, color: CColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${'bid.total_bids'.tr()}: $count',
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

  // Pages for bottom navigation
  List<Widget> _getPages() {
    return [
      // Index 0: My Jobs (left button)
      MyJobsScreen(scrollController: _myJobsScrollController),

      // Index 1: Profile (left-center) - placeholder
      _buildProfilePlaceholder(),

      // Index 2: HOME (center button) - MAIN DASHBOARD
      _buildHomePage(),

      // Index 3: Notifications (right-center)
      NotificationsScreen(scrollController: _notificationsScrollController,
        showAppBar: false,
      ),

      // Index 4: Post Job (right button)
      PostJobScreen(
        showAppBar: false, // Add this parameter to hide the app bar
        onJobPosted: () {
          // After posting, go back to home
          ref.read(clientPageIndexProvider.notifier).state = 2;
        },
      ),
    ];
  }

  Widget _buildPostJobPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_circle_outline, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Tap + to post a job',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
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
        cacheExtent: 1000,
        semanticChildCount: 10,
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
                  'dashboard.my_jobs'.tr(),
                  actionText: 'common.view_all'.tr(),
                  onAction: () => _showAllJobs(),
                ),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildJobFilterChips(),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildJobList(),
                const SizedBox(height: CSizes.spaceBtwSections),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePlaceholder() {
    return Center(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    final currentPageIndex = ref.watch(clientPageIndexProvider);

    // Select the right controller based on active page
    ScrollController activeController;
    switch (currentPageIndex) {
      case 0:
        activeController = _myJobsScrollController;
        break;
      case 2:
        activeController = _homeScrollController;
        break;
      case 3:
        activeController = _notificationsScrollController;
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
          ref.read(clientPageIndexProvider.notifier).state = index;
        },
        userRole: 'client',
        scrollController: activeController,
      ),
    );
  }
}