// lib/features/worker/screens/find_jobs_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/models/job_model.dart';
import '../../../core/models/worker_model.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/worker_service.dart';
import '../../../shared/widgets/common_header.dart';
import '../../../shared/widgets/job_media_gallery.dart';
import '../../core/routes/app_routes.dart';
import 'worker_job_details_screen.dart';

class FindJobsScreen extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  final bool showAppBar;

  const FindJobsScreen({
    super.key,
    this.scrollController,
    this.showAppBar = true,
  });

  @override
  ConsumerState<FindJobsScreen> createState() => _FindJobsScreenState();
}

class _FindJobsScreenState extends ConsumerState<FindJobsScreen> {
  final _locationService = LocationService();
  final _workerService   = WorkerService();

  String _workerId           = '';
  String _workerCategory     = '';
  String _workerCategoryName = '';

  WorkerModel? _currentWorker;
  final Map<String, String> _distanceCache = {};
  bool _locationReady = false;

  @override
  void initState() {
    super.initState();
    _loadWorkerData();
  }

  Future<void> _loadWorkerData() async {
    final prefs    = await SharedPreferences.getInstance();
    final workerId = prefs.getString('user_uid') ?? '';
    if (mounted) setState(() => _workerId = workerId);
    if (workerId.isEmpty) return;
    await _loadWorkerCategory();
    await _loadWorkerLocation();
  }

  Future<void> _loadWorkerCategory() async {
    try {
      final workerDoc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(_workerId)
          .get();

      if (!workerDoc.exists) return;

      final data      = workerDoc.data() as Map<String, dynamic>;
      final workInfo  = data['workInfo'] as Map<String, dynamic>? ?? {};
      final categoryId = workInfo['categoryId'] as String?;

      if (categoryId == null) return;

      final categoryDoc = await FirebaseFirestore.instance
          .collection('workCategories')
          .doc(categoryId)
          .get();

      if (categoryDoc.exists && mounted) {
        final categoryData = categoryDoc.data() as Map<String, dynamic>;
        setState(() {
          _workerCategory     = categoryId;
          _workerCategoryName = categoryData['name'] as String? ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading worker category: $e');
    }
  }

  Future<void> _loadWorkerLocation() async {
    try {
      _currentWorker = await _workerService.getWorkerById(_workerId);
      if (mounted) setState(() => _locationReady = true);
    } catch (e) {
      debugPrint('Error loading worker location: $e');
      if (mounted) setState(() => _locationReady = true);
    }
  }

  String? _getDistanceLabel(JobModel job) {
    if (!job.hasLocation) return null;
    if (_distanceCache.containsKey(job.id)) return _distanceCache[job.id];
    final workerLoc = _currentWorker?.effectiveLocation;
    if (workerLoc == null) return null;
    final distKm = _locationService.distanceBetween(workerLoc, job.location!);
    final label  = _locationService.formatDistance(distKm);
    if (job.id != null) _distanceCache[job.id!] = label;
    return label;
  }

  void _showJobDetails(JobModel job) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkerJobDetailsScreen(
          job:            job,
          workerId:       _workerId,
          workerCategory: _workerCategory,
          onBidPlaced:    () {},
        ),
      ),
    );
  }

  void _openMapView(List<JobModel> jobs) {
    Navigator.pushNamed(
      context,
      AppRoutes.jobsMap,
      arguments: {
        'worker': _currentWorker,
        'jobs':   jobs,
      },
    );
  }

  // ── Gradient helper ──────────────────────────────────────────────
  LinearGradient _getHeaderGradient(JobModel job) {
    if (job.isUrgent) {
      return LinearGradient(
        colors: [CColors.primary, CColors.primary.withValues(alpha: 0.75)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );
    } else if (job.hasSchedule) {
      return LinearGradient(
        colors: [CColors.secondary, CColors.secondary.withValues(alpha: 0.75)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );
    } else {
      return LinearGradient(
        colors: [Colors.grey.shade700, Colors.grey.shade600],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'open': return CColors.success;
      case 'in-progress': return CColors.warning;
      case 'completed': return CColors.info;
      case 'cancelled': return CColors.error;
      case 'scheduled': return CColors.secondary;
      case 'active': return const Color(0xFFF59E0B);
      case 'grace_period': return const Color(0xFFF97316);
      default: return CColors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status.trim().toLowerCase()) {
      case 'open': return 'Open';
      case 'in-progress': return 'In Progress';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      case 'scheduled': return 'Scheduled';
      case 'active': return 'Active';
      case 'grace_period': return 'Grace Period';
      default: return status;
    }
  }

  Widget _buildJobCard(JobModel job) {
    final isUrdu = context.locale.languageCode == 'ur';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final distLabel = _getDistanceLabel(job);
    final statusColor = _getStatusColor(job.status);
    final statusText = _getStatusText(job.status);

    return Card(
      margin: const EdgeInsets.only(bottom: CSizes.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.cardRadiusMd)),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showJobDetails(job),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gradient header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: CSizes.md, vertical: 12),
              decoration: BoxDecoration(gradient: _getHeaderGradient(job)),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      job.title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(CSizes.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.description,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontSize: isUrdu ? 16 : 14,
                      color: isDark ? CColors.textWhite.withValues(alpha: 0.8) : CColors.darkerGrey,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: CSizes.sm),
                  if (job.hasMedia) ...[
                    JobMediaGallery(
                      mediaUrls: job.mediaUrls,
                      mediaTypes: job.mediaTypes,
                      mediaBase64: job.mediaBase64,
                    ),
                    const SizedBox(height: CSizes.sm),
                  ],
                  if (job.hasLocation)
                    Padding(
                      padding: const EdgeInsets.only(bottom: CSizes.sm),
                      child: Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 14, color: CColors.darkGrey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              job.displayLocation,
                              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                fontSize: isUrdu ? 13 : 11,
                                color: CColors.darkGrey,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (job.hasSchedule)
                    Padding(
                      padding: const EdgeInsets.only(bottom: CSizes.sm),
                      child: Row(
                        children: [
                          Icon(Icons.event_available_rounded, size: 14, color: CColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Scheduled: ${DateFormat('d MMM yyyy, hh:mm a').format(job.scheduledAt!.toDate())}',
                            style: TextStyle(fontSize: isUrdu ? 13 : 11, color: CColors.primary, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: CColors.darkGrey),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          timeago.format(job.createdAt.toDate()),
                          style: Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: isUrdu ? 14 : 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (distLabel != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: CColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.near_me_rounded, size: 11, color: CColors.primary),
                            const SizedBox(width: 3),
                            Text(distLabel, style: TextStyle(fontSize: isUrdu ? 12 : 10, color: CColors.primary, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ],
                      const Spacer(),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('bids')
                            .where('jobId', isEqualTo: job.id)
                            .snapshots(),
                        builder: (context, bidSnapshot) {
                          final bidCount = bidSnapshot.data?.docs.length ?? 0;
                          return Row(children: [
                            const Icon(Icons.gavel, size: 16, color: CColors.primary),
                            const SizedBox(width: 4),
                            Text('$bidCount bids', style: Theme.of(context).textTheme.labelMedium!.copyWith(
                              color: CColors.primary, fontWeight: FontWeight.bold, fontSize: isUrdu ? 14 : 12,
                            )),
                          ]);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title: 'Find Jobs',
            showBackButton: widget.showAppBar,
            onBackPressed: widget.showAppBar ? () => Navigator.pop(context) : null,
          ),
          Expanded(child: _buildJobsList()),
        ],
      ),
    );
  }

  Widget _buildJobsList() {
    if (_workerId.isEmpty) {
      return const Center(child: Text('Please login to view jobs', style: TextStyle(fontSize: 16)));
    }

    if (_workerCategoryName.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final Query query = FirebaseFirestore.instance
        .collection('jobs')
        .where('status',   isEqualTo: 'open')
        .where('category', isEqualTo: _workerCategoryName)
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.work_off_outlined, size: 64, color: CColors.grey),
                const SizedBox(height: CSizes.md),
                Text('No $_workerCategoryName jobs available', style: const TextStyle(fontSize: 16, color: CColors.darkGrey)),
                const SizedBox(height: CSizes.sm),
                const Text('Check back later for new postings.', style: TextStyle(fontSize: 13, color: CColors.darkGrey)),
              ],
            ),
          );
        }

        final jobs = snapshot.data!.docs
            .map((doc) => JobModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList();

        final jobsWithLocation = jobs.where((j) => j.hasLocation).toList();

        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async => Future.delayed(const Duration(milliseconds: 500)),
              child: ListView.builder(
                controller: widget.scrollController,
                padding: const EdgeInsets.all(CSizes.defaultSpace),
                itemCount: jobs.length,
                itemBuilder: (context, index) => _buildJobCard(jobs[index]),
              ),
            ),
            if (jobsWithLocation.isNotEmpty)
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton.extended(
                  heroTag: 'find_jobs_map',
                  onPressed: () => _openMapView(jobs),
                  backgroundColor: CColors.primary,
                  icon: const Icon(Icons.map_rounded, color: Colors.white),
                  label: const Text('Map View', style: TextStyle(color: Colors.white)),
                ),
              ),
          ],
        );
      },
    );
  }
}