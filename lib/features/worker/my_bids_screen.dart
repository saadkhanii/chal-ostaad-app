// lib/features/worker/screens/my_bids_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/models/bid_model.dart';
import '../../../core/models/job_model.dart';
import '../../../core/services/chat_service.dart';
import '../../../shared/widgets/common_header.dart';
import '../chat/chat_screen.dart';
import 'worker_job_details_screen.dart';

// Provider to get job details for a bid
final jobForBidProvider = FutureProvider.family<JobModel?, String>((ref, jobId) async {
  try {
    final doc = await FirebaseFirestore.instance.collection('jobs').doc(jobId).get();
    if (doc.exists) {
      return JobModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    }
    return null;
  } catch (e) {
    debugPrint('Error getting job: $e');
    return null;
  }
});

class MyBidsScreen extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  final bool showAppBar;

  const MyBidsScreen({
    super.key,
    this.scrollController,
    this.showAppBar = true,
  });

  @override
  ConsumerState<MyBidsScreen> createState() => _MyBidsScreenState();
}

class _MyBidsScreenState extends ConsumerState<MyBidsScreen> {
  String _workerId = '';
  String _selectedFilter = 'all'; // all, pending, accepted, rejected

  @override
  void initState() {
    super.initState();
    _loadWorkerId();
  }

  Future<void> _loadWorkerId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _workerId = prefs.getString('user_uid') ?? '';
      });
    }
  }

  Color _getStatusColor(String status) {
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

  String _getStatusText(String status) {
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
            title: 'My Bids',
            showBackButton: widget.showAppBar,
            onBackPressed: widget.showAppBar
                ? () => Navigator.pop(context)
                : null,
          ),
          _buildFilterChips(context, isDark, isUrdu),
          Expanded(
            child: _buildBidsList(context, isDark, isUrdu),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context, bool isDark, bool isUrdu) {
    final filters = [
      'common.all'.tr(),
      'bid.status_pending'.tr(),
      'bid.status_accepted'.tr(),
      'bid.status_rejected'.tr(),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace, vertical: CSizes.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.asMap().entries.map((entry) {
            final index = entry.key;
            final filter = entry.value;
            final filterKey = ['all', 'pending', 'accepted', 'rejected'][index];
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

  Widget _buildBidsList(BuildContext context, bool isDark, bool isUrdu) {
    if (_workerId.isEmpty) {
      return Center(
        child: Text(
          'errors.login_to_view_bids'.tr(),
          style: TextStyle(fontSize: isUrdu ? 16 : 14),
        ),
      );
    }

    Query query = FirebaseFirestore.instance
        .collection('bids')
        .where('workerId', isEqualTo: _workerId)
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
                Icon(Icons.gavel_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'bid.no_bids_placed'.tr(),
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
            final bid = BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);

            return Consumer(
              builder: (context, ref, _) {
                final jobAsync = ref.watch(jobForBidProvider(bid.jobId));

                return Card(
                  margin: const EdgeInsets.only(bottom: CSizes.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
                  ),
                  elevation: 2,
                  child: InkWell(
                    onTap: () {
                      jobAsync.whenData((job) {
                        if (job != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WorkerJobDetailsScreen(
                                job: job,
                                workerId: _workerId,
                                workerCategory: '',
                                onBidPlaced: () {},
                              ),
                            ),
                          );
                        }
                      });
                    },
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
                                child: jobAsync.when(
                                  data: (job) => Text(
                                    job?.title ?? 'job.unknown'.tr(),
                                    style: Theme.of(context).textTheme.titleMedium!.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: isUrdu ? 18 : 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  loading: () => Text(
                                    'common.loading'.tr(),
                                    style: Theme.of(context).textTheme.titleMedium!.copyWith(
                                      fontSize: isUrdu ? 18 : 16,
                                    ),
                                  ),
                                  error: (_, __) => Text(
                                    'job.unknown'.tr(),
                                    style: Theme.of(context).textTheme.titleMedium!.copyWith(
                                      fontSize: isUrdu ? 18 : 16,
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(bid.status).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _getStatusColor(bid.status)),
                                ),
                                child: Text(
                                  _getStatusText(bid.status),
                                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                                    color: _getStatusColor(bid.status),
                                    fontWeight: FontWeight.bold,
                                    fontSize: isUrdu ? 12 : 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: CSizes.sm),
                          Text(
                            '${'bid.amount'.tr()}: Rs. ${bid.amount.toStringAsFixed(0)}',
                            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                              fontWeight: FontWeight.w600,
                              color: CColors.primary,
                              fontSize: isUrdu ? 16 : 14,
                            ),
                          ),
                          if (bid.message != null && bid.message!.isNotEmpty) ...[
                            const SizedBox(height: CSizes.xs),
                            Text(
                              '"${bid.message}"',
                              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                fontStyle: FontStyle.italic,
                                color: CColors.darkGrey,
                                fontSize: isUrdu ? 14 : 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: CSizes.sm),
                          Row(
                            children: [
                              Icon(Icons.access_time, size: 16, color: CColors.darkGrey),
                              const SizedBox(width: 4),
                              Text(
                                timeago.format(bid.createdAt.toDate()),
                                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                  fontSize: isUrdu ? 14 : 12,
                                ),
                              ),
                              const Spacer(),
                              // Chat button for accepted bids
                              if (bid.status == 'accepted')
                                GestureDetector(
                                  onTap: () {
                                    final chatService = ChatService();
                                    final chatId = chatService.getChatId(bid.jobId, _workerId);
                                    jobAsync.whenData((job) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(
                                            chatId:        chatId,
                                            jobTitle:      job?.title ?? '',
                                            otherName:     'Client',
                                            currentUserId: _workerId,
                                            otherUserId:   bid.clientId,
                                            otherRole:     'client',
                                          ),
                                        ),
                                      );
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color:        CColors.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border:       Border.all(color: CColors.primary),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.chat_outlined,
                                            size: 14, color: CColors.primary),
                                        const SizedBox(width: 4),
                                        Text('chat.chat'.tr(),
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: CColors.primary,
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
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