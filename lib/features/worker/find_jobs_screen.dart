// lib/features/worker/screens/find_jobs_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/models/job_model.dart';
import '../../../core/models/worker_model.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/worker_service.dart';
import '../../../shared/widgets/common_header.dart';
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

  String  _workerId           = '';
  String  _workerCategory     = '';
  String  _workerCategoryName = '';
  int     _selectedFilter     = 0; // 0: All, 1: My Category
  final List<String> _filterOptions = ['All Jobs', 'My Category'];

  // Location state
  WorkerModel? _currentWorker;
  Map<String, String> _distanceCache = {}; // jobId → "2.4 km"
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

      if (workerDoc.exists) {
        final data      = workerDoc.data() as Map<String, dynamic>;
        final workInfo  = data['workInfo'] as Map<String, dynamic>? ?? {};
        final categoryId = workInfo['categoryId'] as String?;

        if (categoryId != null) {
          final categoryDoc = await FirebaseFirestore.instance
              .collection('workCategories')
              .doc(categoryId)
              .get();

          if (categoryDoc.exists && mounted) {
            final categoryData = categoryDoc.data() as Map<String, dynamic>;
            setState(() {
              _workerCategory     = categoryId;
              _workerCategoryName = categoryData['name'] ?? '';
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading worker category: $e');
    }
  }

  // Load worker's location for distance calculations
  Future<void> _loadWorkerLocation() async {
    try {
      _currentWorker = await _workerService.getWorkerById(_workerId);
      if (mounted) setState(() => _locationReady = true);
    } catch (e) {
      debugPrint('Error loading worker location: $e');
      if (mounted) setState(() => _locationReady = true);
    }
  }

  // Calculate and cache distance from worker to a job
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
          _buildFilterChips(),
          Expanded(child: _buildJobsList()),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CSizes.defaultSpace, vertical: CSizes.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filterOptions.asMap().entries.map((entry) {
            final idx      = entry.key;
            final label    = entry.value;
            final isSelected = _selectedFilter == idx;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: FilterChip(
                label: Text(label,
                    style: TextStyle(fontSize: isUrdu ? 16 : 14)),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedFilter = idx);
                },
                selectedColor: CColors.primary,
                labelStyle: TextStyle(
                  color: isSelected
                      ? CColors.white
                      : (isDark ? CColors.white : CColors.textPrimary),
                ),
                backgroundColor: isDark
                    ? CColors.darkContainer
                    : CColors.lightContainer,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildJobsList() {
    if (_workerId.isEmpty) {
      return const Center(
        child: Text('Please login to view jobs',
            style: TextStyle(fontSize: 16)),
      );
    }

    Query query = FirebaseFirestore.instance
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
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.work_outline, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('No jobs available',
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
          );
        }

        final jobs = snapshot.data!.docs.map((doc) {
          return JobModel.fromMap(
              doc.data() as Map<String, dynamic>, doc.id);
        }).toList();

        final jobsWithLocation = jobs.where((j) => j.hasLocation).toList();

        return Stack(
          children: [
            ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              itemCount: jobs.length,
              itemBuilder: (context, index) =>
                  _buildJobCard(jobs[index]),
            ),

            // ── Map view FAB (only when some jobs have locations) ──
            if (jobsWithLocation.isNotEmpty)
              Positioned(
                bottom: 16,
                right:  16,
                child: FloatingActionButton.extended(
                  heroTag: 'find_jobs_map',
                  onPressed: () => _openMapView(jobs),
                  backgroundColor: CColors.primary,
                  icon: const Icon(Icons.map_rounded, color: Colors.white),
                  label: const Text('Map View',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildJobCard(JobModel job) {
    final isUrdu    = context.locale.languageCode == 'ur';
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final distLabel = _getDistanceLabel(job);

    return Card(
      margin: const EdgeInsets.only(bottom: CSizes.md),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusMd)),
      elevation: 2,
      child: InkWell(
        onTap:        () => _showJobDetails(job),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        child: Padding(
          padding: const EdgeInsets.all(CSizes.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title + category badge ─────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      job.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium!
                          .copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: isUrdu ? 18 : 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:        CColors.info.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border:       Border.all(color: CColors.info),
                    ),
                    child: Text(
                      job.category,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall!
                          .copyWith(
                        color:      CColors.info,
                        fontWeight: FontWeight.bold,
                        fontSize:   isUrdu ? 12 : 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CSizes.sm),

              // ── Description ───────────────────────────────────
              Text(
                job.description,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontSize: isUrdu ? 16 : 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: CSizes.sm),

              // ── Location row ──────────────────────────────────
              if (job.hasLocation)
                Padding(
                  padding: const EdgeInsets.only(bottom: CSizes.sm),
                  child: Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: CColors.darkGrey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          job.displayLocation,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall!
                              .copyWith(
                            fontSize: isUrdu ? 13 : 11,
                            color:    CColors.darkGrey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Time + distance + bid count ───────────────────
              Row(
                children: [
                  Icon(Icons.access_time,
                      size: 16, color: CColors.darkGrey),
                  const SizedBox(width: 4),
                  Text(
                    timeago.format(job.createdAt.toDate()),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall!
                        .copyWith(fontSize: isUrdu ? 14 : 12),
                  ),

                  // Distance badge
                  if (distLabel != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:        CColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.near_me_rounded,
                              size: 11, color: CColors.primary),
                          const SizedBox(width: 3),
                          Text(
                            distLabel,
                            style: TextStyle(
                              fontSize:   isUrdu ? 12 : 10,
                              color:      CColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Spacer(),

                  // Bid count
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('bids')
                        .where('jobId', isEqualTo: job.id)
                        .snapshots(),
                    builder: (context, bidSnapshot) {
                      final bidCount =
                          bidSnapshot.data?.docs.length ?? 0;
                      return Row(
                        children: [
                          Icon(Icons.gavel,
                              size: 16, color: CColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            '$bidCount bids',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium!
                                .copyWith(
                              color:      CColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize:   isUrdu ? 14 : 12,
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
}