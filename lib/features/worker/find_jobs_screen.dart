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
import '../../../shared/widgets/common_header.dart';
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
  String _workerId = '';
  String _workerCategory = '';
  int _selectedFilter = 0; // 0: All, 1: My Category
  final List<String> _filterOptions = ['All Jobs', 'My Category'];
  String _workerCategoryName = '';

  @override
  void initState() {
    super.initState();
    _loadWorkerData();
  }

  Future<void> _loadWorkerData() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getString('user_uid') ?? '';

    if (mounted) {
      setState(() {
        _workerId = workerId;
      });
    }

    if (workerId.isNotEmpty) {
      _loadWorkerCategory();
    }
  }

  Future<void> _loadWorkerCategory() async {
    try {
      final workerDoc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(_workerId)
          .get();

      if (workerDoc.exists) {
        final data = workerDoc.data() as Map<String, dynamic>;
        final workInfo = data['workInfo'] as Map<String, dynamic>? ?? {};
        final categoryId = workInfo['categoryId'] as String?;

        if (categoryId != null) {
          // Get category name
          final categoryDoc = await FirebaseFirestore.instance
              .collection('workCategories')
              .doc(categoryId)
              .get();

          if (categoryDoc.exists) {
            final categoryData = categoryDoc.data() as Map<String, dynamic>;
            if (mounted) {
              setState(() {
                _workerCategory = categoryId;
                _workerCategoryName = categoryData['name'] ?? '';
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading worker category: $e');
    }
  }

  void _showJobDetails(JobModel job) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkerJobDetailsScreen(
          job: job,
          workerId: _workerId,
          workerCategory: _workerCategory,
          onBidPlaced: () {
            // Refresh or show message
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          // Header with conditional back button
          CommonHeader(
            title: 'Find Jobs',
            showBackButton: widget.showAppBar,
            onBackPressed: widget.showAppBar
                ? () => Navigator.pop(context)
                : null,
          ),
          _buildFilterChips(),
          Expanded(
            child: _buildJobsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace, vertical: CSizes.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filterOptions.asMap().entries.map((entry) {
            final idx = entry.key;
            final label = entry.value;
            final isSelected = _selectedFilter == idx;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: FilterChip(
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
                ),
                backgroundColor: isDark ? CColors.darkContainer : CColors.lightContainer,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildJobsList() {
    if (_workerId.isEmpty) {
      return Center(
        child: Text(
          'Please login to view jobs',
          style: TextStyle(fontSize: 16),
        ),
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
                Icon(Icons.work_outline, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'No jobs available',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(CSizes.defaultSpace),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                    stream: FirebaseFirestore.instance
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
                            '$bidCount bids',
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
}