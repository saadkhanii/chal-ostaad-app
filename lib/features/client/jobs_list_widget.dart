// lib/features/client/widgets/jobs_list_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/models/job_model.dart';
import '../../core/routes/app_routes.dart';
import 'client_job_details_screen.dart';

final bidCountProvider =
FutureProvider.family<int, String>((ref, jobId) async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .get();
    return snapshot.docs.length;
  } catch (e) {
    debugPrint('Error getting bid count: $e');
    return 0;
  }
});

class JobsListWidget extends ConsumerStatefulWidget {
  final String clientId;
  final ScrollController? scrollController;
  final bool showFilters;
  final bool showMapButton;
  final int? limit;
  final Function(JobModel)? onJobTap;
  final EdgeInsetsGeometry? padding;

  const JobsListWidget({
    super.key,
    required this.clientId,
    this.scrollController,
    this.showFilters   = true,
    this.showMapButton = true,
    this.limit,
    this.onJobTap,
    this.padding,
  });

  @override
  ConsumerState<JobsListWidget> createState() => _JobsListWidgetState();
}

class _JobsListWidgetState extends ConsumerState<JobsListWidget> {
  String _selectedFilter = 'all';

  // Track which job IDs are currently being deleted to show a spinner
  final Set<String> _deletingIds = {};

  Color _getStatusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'open':        return CColors.success;
      case 'in-progress': return CColors.warning;
      case 'completed':   return CColors.info;
      case 'cancelled':   return CColors.error;
      default:            return CColors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status.trim().toLowerCase()) {
      case 'open':        return 'job.status_open'.tr();
      case 'in-progress': return 'job.status_in_progress'.tr();
      case 'completed':   return 'job.status_completed'.tr();
      case 'cancelled':   return 'job.status_cancelled'.tr();
      default:            return status;
    }
  }

  void _handleJobTap(JobModel job) {
    if (widget.onJobTap != null) {
      widget.onJobTap!(job);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ClientJobDetailsScreen(job: job)),
      );
    }
  }

  void _openMapView(List<JobModel> jobs) {
    Navigator.pushNamed(
      context,
      AppRoutes.jobsMap,
      arguments: {'jobs': jobs},
    );
  }

  /// Deletes a job directly from Firestore.
  /// Only open jobs can be deleted — confirmed via dialog.
  Future<void> _deleteJob(JobModel job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('job.delete_job'.tr()),
        content: Text('job.delete_job_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: CColors.error),
            child: Text(
              'common.delete'.tr(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deletingIds.add(job.id!));
    try {
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(job.id)
          .delete();
      // Stream auto-removes the card — no manual setState needed.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Failed to delete job: $e'),
          backgroundColor: CColors.error,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _deletingIds.remove(job.id!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.locale.languageCode == 'ur';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        if (widget.showFilters)
          _buildFilterChips(context, isDark, isUrdu),
        Expanded(child: _buildJobsList(context, isDark, isUrdu)),
      ],
    );
  }

  Widget _buildFilterChips(
      BuildContext context, bool isDark, bool isUrdu) {
    final filters = [
      'common.all'.tr(),
      'job.status_open'.tr(),
      'job.status_in_progress'.tr(),
      'job.status_completed'.tr(),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CSizes.defaultSpace, vertical: CSizes.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.asMap().entries.map((entry) {
            final index     = entry.key;
            final filter    = entry.value;
            final filterKey =
            ['all', 'open', 'in-progress', 'completed'][index];
            final isSelected = _selectedFilter == filterKey;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(filter,
                    style: TextStyle(
                      fontSize: isUrdu ? 14 : 12,
                      color: isSelected
                          ? Colors.white
                          : (isDark
                          ? Colors.white
                          : CColors.textPrimary),
                    )),
                selected:        isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedFilter = filterKey);
                  }
                },
                selectedColor:   CColors.primary,
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

  Widget _buildJobsList(
      BuildContext context, bool isDark, bool isUrdu) {
    if (widget.clientId.isEmpty) {
      return Center(
        child: Text('job.login_to_view'.tr(),
            style: TextStyle(fontSize: isUrdu ? 16 : 14)),
      );
    }

    Query query = FirebaseFirestore.instance
        .collection('jobs')
        .where('clientId', isEqualTo: widget.clientId)
        .orderBy('createdAt', descending: true);

    if (_selectedFilter != 'all') {
      query = query.where('status', isEqualTo: _selectedFilter);
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
                const Icon(Icons.work_outline,
                    size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text('job.no_jobs_found'.tr(),
                    style: const TextStyle(
                        fontSize: 16, color: Colors.grey)),
              ],
            ),
          );
        }

        int itemCount = snapshot.data!.docs.length;
        if (widget.limit != null && widget.limit! < itemCount) {
          itemCount = widget.limit!;
        }

        final allJobs = snapshot.data!.docs.map((doc) {
          return JobModel.fromMap(
              doc.data() as Map<String, dynamic>, doc.id);
        }).toList();

        final jobsWithLocation =
        allJobs.where((j) => j.hasLocation).toList();

        return Stack(
          children: [
            ListView.builder(
              controller: widget.scrollController,
              padding: widget.padding ??
                  const EdgeInsets.all(CSizes.defaultSpace),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                final job = allJobs[index];
                return Consumer(
                  builder: (context, ref, _) {
                    final bidCountAsync =
                    ref.watch(bidCountProvider(job.id!));
                    return _buildJobCard(
                        context, isDark, isUrdu, job, bidCountAsync);
                  },
                );
              },
            ),

            // ── Map view FAB ────────────────────────────────────
            if (widget.showMapButton && jobsWithLocation.isNotEmpty)
              Positioned(
                bottom: 16,
                right:  16,
                child: FloatingActionButton.extended(
                  heroTag:         'jobs_list_map',
                  onPressed:       () => _openMapView(allJobs),
                  backgroundColor: CColors.primary,
                  icon: const Icon(Icons.map_rounded,
                      color: Colors.white),
                  label: const Text('Map View',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildJobCard(
      BuildContext context,
      bool isDark,
      bool isUrdu,
      JobModel job,
      AsyncValue<int> bidCountAsync,
      ) {
    final statusNorm = job.status.trim().toLowerCase();
    final isOpen     = statusNorm == 'open' || statusNorm == 'cancelled';
    final isDeleting = _deletingIds.contains(job.id);

    return Card(
      margin: const EdgeInsets.only(bottom: CSizes.md),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusMd)),
      elevation: 2,
      child: InkWell(
        onTap:        () => _handleJobTap(job),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        child: Padding(
          padding: const EdgeInsets.all(CSizes.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title + status badge + delete button ─────────
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
                        fontSize:   isUrdu ? 18 : 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(job.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _getStatusColor(job.status)),
                    ),
                    child: Text(
                      _getStatusText(job.status),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall!
                          .copyWith(
                        color:      _getStatusColor(job.status),
                        fontWeight: FontWeight.bold,
                        fontSize:   isUrdu ? 12 : 10,
                      ),
                    ),
                  ),
                  // ── Delete button (only for open jobs) ────────
                  if (isOpen) ...[
                    const SizedBox(width: 4),
                    SizedBox(
                      width:  32,
                      height: 32,
                      child: isDeleting
                          ? const Padding(
                        padding: EdgeInsets.all(6),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: CColors.error,
                        ),
                      )
                          : IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: CColors.error,
                          size: 20,
                        ),
                        tooltip: 'job.delete_job'.tr(),
                        onPressed: () => _deleteJob(job),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: CSizes.sm),

              // ── Description ──────────────────────────────────
              Text(
                job.description,
                style:
                Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontSize: isUrdu ? 16 : 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: CSizes.sm),

              // ── Location row ─────────────────────────────────
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

              // ── Time + bid count ─────────────────────────────
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
                  const Spacer(),
                  bidCountAsync.when(
                    data:    (count) =>
                        _buildBidCount(context, isUrdu, count.toString()),
                    loading: () =>
                        _buildBidCount(context, isUrdu, '...'),
                    error:   (_, __) =>
                        _buildBidCount(context, isUrdu, '0'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBidCount(
      BuildContext context, bool isUrdu, String count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.gavel, size: 16, color: CColors.primary),
        const SizedBox(width: 4),
        Text(
          '${'bid.total_bids'.tr()}: $count',
          style: Theme.of(context).textTheme.labelMedium!.copyWith(
            color:      CColors.primary,
            fontWeight: FontWeight.bold,
            fontSize:   isUrdu ? 14 : 12,
          ),
        ),
      ],
    );
  }
}