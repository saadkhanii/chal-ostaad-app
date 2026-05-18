// lib/features/worker/my_bids_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/models/bid_model.dart';
import '../../../core/models/job_model.dart';
import '../../../core/services/bid_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../shared/widgets/common_header.dart';
import '../../../shared/widgets/job_media_gallery.dart';
import '../chat/chat_screen.dart';
import 'worker_job_details_screen.dart';
import 'edit_bid_screen.dart';

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
  String _selectedFilter = 'all';
  final BidService _bidService = BidService();
  String? _deletingBidId;

  @override
  void initState() {
    super.initState();
    _loadWorkerId();
  }

  Future<void> _loadWorkerId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _workerId = prefs.getString('user_uid') ?? '');
    }
  }

  Color _getBidStatusColor(String status) {
    switch (status) {
      case 'accepted': return CColors.success;
      case 'pending': return CColors.warning;
      case 'rejected': return CColors.error;
      default: return CColors.grey;
    }
  }

  String _getBidStatusText(String status) {
    switch (status) {
      case 'accepted': return 'bid.status_accepted'.tr();
      case 'pending': return 'bid.status_pending'.tr();
      case 'rejected': return 'bid.status_rejected'.tr();
      default: return status;
    }
  }

  LinearGradient _getJobHeaderGradient(JobModel? job) {
    if (job == null) return LinearGradient(colors: [Colors.grey, Colors.grey.shade600]);
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

  DateTime? _getProposedStartTime(BidModel bid, JobModel? job) {
    if (bid.workerProposedStartTime != null) return bid.workerProposedStartTime;
    if (job?.scheduledAt != null) return job!.scheduledAt!.toDate();
    return null;
  }

  Future<void> _deleteBid(String bidId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bid'),
        content: const Text('Are you sure you want to delete this bid? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('common.cancel'.tr())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: CColors.error),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deletingBidId = bidId);
    try {
      await _bidService.deleteBid(bidId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bid deleted successfully'),
          backgroundColor: CColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to delete bid: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _deletingBidId = null);
    }
  }

  Future<void> _editBid(BidModel bid, String jobTitle) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditBidScreen(bid: bid, jobTitle: jobTitle)),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bid updated successfully'),
        backgroundColor: CColors.success,
        behavior: SnackBarBehavior.floating,
      ));
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
          CommonHeader(
            title: 'My Bids',
            showBackButton: widget.showAppBar,
            onBackPressed: widget.showAppBar ? () => Navigator.pop(context) : null,
          ),
          _buildFilterChips(context, isDark, isUrdu),
          Expanded(child: _buildBidsList(context, isDark, isUrdu)),
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
                label: Text(filter,
                    style: TextStyle(
                      fontSize: isUrdu ? 14 : 12,
                      color: isSelected ? Colors.white : (isDark ? Colors.white : CColors.textPrimary),
                    )),
                selected: isSelected,
                onSelected: (selected) { if (selected) setState(() => _selectedFilter = filterKey); },
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
      return Center(child: Text('errors.login_to_view_bids'.tr(), style: TextStyle(fontSize: isUrdu ? 16 : 14)));
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
                Text('bid.no_bids_placed'.tr(), style: const TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => Future.delayed(const Duration(milliseconds: 500)),
          child: ListView.builder(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(CSizes.defaultSpace),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final bid = BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
              return Consumer(
                builder: (context, ref, _) {
                  final jobAsync = ref.watch(jobForBidProvider(bid.jobId));
                  return jobAsync.when(
                    data: (job) => _buildBidCard(bid, job, isDark, isUrdu),
                    loading: () => _buildBidCard(bid, null, isDark, isUrdu),
                    error: (_, __) => _buildBidCard(bid, null, isDark, isUrdu),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBidCard(BidModel bid, JobModel? job, bool isDark, bool isUrdu) {
    final isDeleting = _deletingBidId == bid.id;
    final proposedStart = _getProposedStartTime(bid, job);
    final statusColor = _getBidStatusColor(bid.status);
    final statusText = _getBidStatusText(bid.status);

    return Card(
      margin: const EdgeInsets.only(bottom: CSizes.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.cardRadiusMd)),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
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
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gradient header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: CSizes.md, vertical: 12),
              decoration: BoxDecoration(gradient: _getJobHeaderGradient(job)),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      job?.title ?? 'Unknown Job',
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
                    '${'bid.amount'.tr()}: Rs. ${bid.amount.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                      color: CColors.primary,
                      fontSize: isUrdu ? 16 : 14,
                    ),
                  ),
                  if (bid.availableTime != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Icon(Icons.access_time_outlined, size: 14, color: CColors.primary),
                        const SizedBox(width: 4),
                        Text('Available: ${DateFormat('d MMM yyyy, hh:mm a').format(bid.availableTime!)}',
                            style: TextStyle(fontSize: isUrdu ? 13 : 11, color: CColors.darkGrey)),
                      ]),
                    ),
                  if (proposedStart != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Icon(Icons.event_available_rounded, size: 14, color: CColors.primary),
                        const SizedBox(width: 4),
                        Text('Proposed start: ${DateFormat('d MMM yyyy, hh:mm a').format(proposedStart)}',
                            style: TextStyle(fontSize: isUrdu ? 13 : 11, color: CColors.darkGrey)),
                      ]),
                    ),
                  if (job != null && job.hasMedia)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: JobMediaGallery(
                        mediaUrls: job.mediaUrls,
                        mediaTypes: job.mediaTypes,
                        mediaBase64: job.mediaBase64,
                      ),
                    ),
                  if (bid.message != null && bid.message!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('"${bid.message}"',
                          style: Theme.of(context).textTheme.bodySmall!.copyWith(
                            fontStyle: FontStyle.italic,
                            color: CColors.darkGrey,
                            fontSize: isUrdu ? 14 : 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  const SizedBox(height: CSizes.sm),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: CColors.darkGrey),
                      const SizedBox(width: 4),
                      Text(timeago.format(bid.createdAt.toDate()),
                          style: Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: isUrdu ? 14 : 12)),
                      const Spacer(),
                      if (bid.status == 'pending')
                        Row(
                          children: [
                            if (!isDeleting)
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18, color: CColors.primary),
                                onPressed: () => job != null ? _editBid(bid, job.title) : null,
                                tooltip: 'Edit',
                              ),
                            IconButton(
                              icon: isDeleting
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.delete_outline, size: 18, color: CColors.error),
                              onPressed: isDeleting ? null : () => _deleteBid(bid.id!),
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                      if (bid.status == 'accepted')
                        GestureDetector(
                          onTap: () async {
                            final chatService = ChatService();
                            final chatId = chatService.getChatId(bid.jobId, _workerId);
                            String clientName = 'Client';
                            try {
                              final doc = await FirebaseFirestore.instance.collection('clients').doc(bid.clientId).get();
                              final info = doc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
                              clientName = info['fullName'] ?? info['name'] ?? 'Client';
                            } catch (_) {}
                            if (job != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    chatId: chatId,
                                    jobTitle: job.title,
                                    otherName: clientName,
                                    currentUserId: _workerId,
                                    otherUserId: bid.clientId,
                                    otherRole: 'client',
                                  ),
                                ),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: CColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: CColors.primary),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chat_outlined, size: 14, color: CColors.primary),
                                const SizedBox(width: 4),
                                Text('chat.chat'.tr(),
                                    style: TextStyle(fontSize: 12, color: CColors.primary, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
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
}