// lib/features/client/widgets/jobs_list_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/models/job_model.dart';
import 'client_job_details_screen.dart';

// Provider to get bid count for a job
final bidCountProvider = FutureProvider.family<int, String>((ref, jobId) async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .count()
        .get();
    return snapshot.count ?? 0;
  } catch (e) {
    debugPrint('Error getting bid count: $e');
    return 0;
  }
});

class JobsListWidget extends ConsumerStatefulWidget {
  final String clientId;
  final ScrollController? scrollController;
  final bool showFilters;
  final int? limit; // For showing limited jobs on home page
  final Function(JobModel)? onJobTap; // Optional callback
  final EdgeInsetsGeometry? padding;

  const JobsListWidget({
    super.key,
    required this.clientId,
    this.scrollController,
    this.showFilters = true,
    this.limit,
    this.onJobTap,
    this.padding,
  });

  @override
  ConsumerState<JobsListWidget> createState() => _JobsListWidgetState();
}

class _JobsListWidgetState extends ConsumerState<JobsListWidget> {
  String _selectedFilter = 'all';

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open': return CColors.success;
      case 'in-progress': return CColors.warning;
      case 'completed': return CColors.info;
      case 'cancelled': return CColors.error;
      default: return CColors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'open': return 'job.status_open'.tr();
      case 'in-progress': return 'job.status_in_progress'.tr();
      case 'completed': return 'job.status_completed'.tr();
      case 'cancelled': return 'job.status_cancelled'.tr();
      default: return status;
    }
  }

  void _handleJobTap(JobModel job) {
    if (widget.onJobTap != null) {
      widget.onJobTap!(job);
    } else {
      // Default behavior: navigate to details
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClientJobDetailsScreen(job: job),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.locale.languageCode == 'ur';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        if (widget.showFilters) _buildFilterChips(context, isDark, isUrdu),
        Expanded(
          child: _buildJobsList(context, isDark, isUrdu),
        ),
      ],
    );
  }

  Widget _buildFilterChips(BuildContext context, bool isDark, bool isUrdu) {
    final filters = [
      'common.all'.tr(),
      'job.status_open'.tr(),
      'job.status_in_progress'.tr(),
      'job.status_completed'.tr(),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace, vertical: CSizes.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.asMap().entries.map((entry) {
            final index = entry.key;
            final filter = entry.value;
            final filterKey = ['all', 'open', 'in-progress', 'completed'][index];
            final isSelected = _selectedFilter == filterKey;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(
                  filter,
                  style: TextStyle(
                    fontSize: isUrdu ? 14 : 12,
                    color: isSelected ? Colors.white : (isDark ? Colors.white : CColors.textPrimary),
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedFilter = filterKey);
                  }
                },
                selectedColor: CColors.primary,
                backgroundColor: isDark ? CColors.darkContainer : CColors.lightContainer,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildJobsList(BuildContext context, bool isDark, bool isUrdu) {
    if (widget.clientId.isEmpty) {
      return Center(
        child: Text(
          'job.login_to_view'.tr(),
          style: TextStyle(fontSize: isUrdu ? 16 : 14),
        ),
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
                Icon(Icons.work_outline, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'job.no_jobs_found'.tr(),
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        // Apply limit if specified
        int itemCount = snapshot.data!.docs.length;
        if (widget.limit != null && widget.limit! < itemCount) {
          itemCount = widget.limit!;
        }

        return ListView.builder(
          controller: widget.scrollController,
          padding: widget.padding ?? const EdgeInsets.all(CSizes.defaultSpace),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final job = JobModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);

            return Consumer(
              builder: (context, ref, _) {
                final bidCountAsync = ref.watch(bidCountProvider(job.id!));

                return Card(
                  margin: const EdgeInsets.only(bottom: CSizes.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
                  ),
                  elevation: 2,
                  child: InkWell(
                    onTap: () => _handleJobTap(job),
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
                              bidCountAsync.when(
                                data: (count) => Row(
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
                                ),
                                loading: () => Row(
                                  children: [
                                    Icon(Icons.gavel, size: 16, color: CColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${'bid.total_bids'.tr()}: ...',
                                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                                        color: CColors.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: isUrdu ? 14 : 12,
                                      ),
                                    ),
                                  ],
                                ),
                                error: (_, __) => Row(
                                  children: [
                                    Icon(Icons.gavel, size: 16, color: CColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${'bid.total_bids'.tr()}: 0',
                                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                                        color: CColors.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: isUrdu ? 14 : 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}