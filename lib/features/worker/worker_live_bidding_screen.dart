// lib/features/worker/screens/worker_live_bidding_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/models/bid_model.dart';
import '../../../core/models/job_model.dart';
import '../../../core/services/bid_service.dart';
import '../../../shared/widgets/common_header.dart';
import '../../../features/profile/worker_profile_preview_sheet.dart';
import 'edit_bid_screen.dart';

final liveBidsProvider = StreamProvider.family<List<BidModel>, String>((ref, jobId) {
  return FirebaseFirestore.instance
      .collection('bids')
      .where('jobId', isEqualTo: jobId)
      .snapshots()
      .map((snapshot) {
    final bids = snapshot.docs
        .map((doc) => BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>))
        .toList();

    final filtered = bids.where((b) {
      final status = b.status.trim().toLowerCase();
      return status == 'pending' || status == 'accepted';
    }).toList();

    filtered.sort((a, b) => a.amount.compareTo(b.amount));
    return filtered;
  });
});

class LiveBiddingScreen extends ConsumerStatefulWidget {
  final JobModel job;
  final String workerId;

  const LiveBiddingScreen({
    super.key,
    required this.job,
    required this.workerId,
  });

  @override
  ConsumerState<LiveBiddingScreen> createState() => _LiveBiddingScreenState();
}

class _LiveBiddingScreenState extends ConsumerState<LiveBiddingScreen> {
  final BidService _bidService = BidService();
  String? _deletingBidId;
  final Map<String, String> _workerNames = {};

  Future<String> _getWorkerName(String workerId) async {
    if (_workerNames.containsKey(workerId)) return _workerNames[workerId]!;
    try {
      final doc = await FirebaseFirestore.instance.collection('workers').doc(workerId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final personal = data['personalInfo'] as Map<String, dynamic>? ?? {};
        final name = personal['fullName'] ?? personal['name'] ?? 'Worker';
        _workerNames[workerId] = name;
        return name;
      }
      return 'Worker';
    } catch (_) {
      return 'Worker';
    }
  }

  DateTime? _getProposedStartTime(BidModel bid) {
    if (bid.workerProposedStartTime != null) return bid.workerProposedStartTime;
    if (widget.job.scheduledAt != null) return widget.job.scheduledAt!.toDate();
    return null;
  }

  Future<void> _deleteBid(String bidId) async {
    if (bidId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bid'),
        content: const Text('Are you sure you want to delete your bid? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
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

  Future<void> _editBid(BidModel bid) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditBidScreen(bid: bid, jobTitle: widget.job.title),
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bid updated successfully'),
        backgroundColor: CColors.success,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _showWorkerProfile(String workerId) {
    WorkerProfilePreviewSheet.show(context, workerId: workerId);
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
            title: 'Live Bidding',
            showBackButton: true,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CSizes.defaultSpace,
              CSizes.defaultSpace,
              CSizes.defaultSpace,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: CColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.work_outline_rounded, size: 14, color: CColors.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Live Auction',
                            style: TextStyle(
                              fontSize: isUrdu ? 12 : 11,
                              color: CColors.primary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.job.title,
                  style: Theme.of(context).textTheme.titleLarge!.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: isUrdu ? 20 : 18,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: CSizes.spaceBtwSections),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
              child: Consumer(
                builder: (context, ref, _) {
                  final bidsAsync = ref.watch(liveBidsProvider(widget.job.id!));
                  return bidsAsync.when(
                    data: (bids) {
                      if (bids.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.gavel_outlined, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'No bids yet',
                                style: TextStyle(fontSize: isUrdu ? 16 : 14, color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        key: const PageStorageKey('live_bids_list'),
                        itemCount: bids.length,
                        itemBuilder: (context, index) {
                          final bid = bids[index];
                          final isMyBid = bid.workerId == widget.workerId;
                          return _buildBidCard(bid, isMyBid, isDark, isUrdu, bids);
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error loading bids: $e')),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBidCard(BidModel bid, bool isMyBid, bool isDark, bool isUrdu, List<BidModel> allBids) {
    final isDeleting = _deletingBidId == bid.id;
    final isAccepted = bid.status.trim().toLowerCase() == 'accepted';
    final rank = allBids.indexOf(bid) + 1;
    final proposedStart = _getProposedStartTime(bid);

    if (isMyBid) {
      return _buildMyBidCard(bid, isAccepted, rank, isDark, isUrdu, isDeleting, proposedStart);
    }

    return FutureBuilder<String>(
      future: _getWorkerName(bid.workerId),
      builder: (context, nameSnapshot) {
        final bidderName = nameSnapshot.data ?? 'Worker';
        return Card(
          key: ValueKey(bid.id ?? 'bid_${bid.workerId}_${bid.jobId}'),
          margin: const EdgeInsets.only(bottom: CSizes.sm),
          elevation: 2,
          shadowColor: CColors.secondary.withOpacity(0.18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
          ),
          clipBehavior: Clip.antiAlias,
          color: isDark ? CColors.darkContainer : Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: CSizes.md, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [CColors.secondary, CColors.secondary.withOpacity(0.75)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        bidderName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.4,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Rank #$rank',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (isAccepted) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: CColors.success,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Accepted ✓',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(CSizes.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'Rs. ${bid.amount.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isUrdu ? 22 : 20,
                            color: CColors.secondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '— quoted amount',
                          style: TextStyle(fontSize: 11, color: CColors.darkGrey),
                        ),
                      ],
                    ),
                    const SizedBox(height: CSizes.sm),

                    if (proposedStart != null) ...[
                      Row(children: [
                        Icon(Icons.event_available_rounded, size: 14, color: CColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Proposed start: ${DateFormat('d MMM yyyy, hh:mm a').format(proposedStart)}',
                            style: TextStyle(fontSize: isUrdu ? 13 : 11, color: CColors.darkGrey),
                          ),
                        ),
                        if (bid.workerProposedStartTime == null && widget.job.scheduledAt != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: CColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Client\'s time',
                              style: TextStyle(fontSize: 9, color: CColors.primary),
                            ),
                          ),
                      ]),
                      const SizedBox(height: CSizes.sm),
                    ],

                    _buildCardBody(bid, isDark, isUrdu),
                    _buildCardFooter(bid, isUrdu),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMyBidCard(BidModel bid, bool isAccepted, int rank, bool isDark, bool isUrdu, bool isDeleting, DateTime? proposedStart) {
    return Card(
      key: ValueKey(bid.id ?? 'my_bid_${bid.workerId}'),
      margin: const EdgeInsets.only(bottom: CSizes.sm),
      elevation: 3,
      shadowColor: CColors.primary.withOpacity(0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: CSizes.md, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [CColors.primary, CColors.primary.withOpacity(0.75)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.gavel_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Your Bid',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Rank #$rank',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                if (isAccepted) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: CColors.success,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Accepted ✓',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(CSizes.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'Rs. ${bid.amount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isUrdu ? 22 : 20,
                        color: CColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '— your quoted amount',
                      style: TextStyle(fontSize: 11, color: CColors.darkGrey),
                    ),
                  ],
                ),
                const SizedBox(height: CSizes.sm),

                if (proposedStart != null) ...[
                  Row(children: [
                    Icon(Icons.event_available_rounded, size: 14, color: CColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Proposed start: ${DateFormat('d MMM yyyy, hh:mm a').format(proposedStart)}',
                        style: TextStyle(fontSize: isUrdu ? 13 : 11, color: CColors.darkGrey),
                      ),
                    ),
                    if (bid.workerProposedStartTime == null && widget.job.scheduledAt != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: CColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Client\'s time',
                          style: TextStyle(fontSize: 9, color: CColors.primary),
                        ),
                      ),
                  ]),
                  const SizedBox(height: CSizes.sm),
                ],

                _buildCardBody(bid, isDark, isUrdu),
                if (bid.status.trim().toLowerCase() == 'pending' && !isDeleting)
                  Padding(
                    padding: const EdgeInsets.only(top: CSizes.sm),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _editBid(bid),
                          icon: const Icon(Icons.edit_outlined, size: 15),
                          label: Text('Edit', style: TextStyle(fontSize: isUrdu ? 13 : 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: CColors.primary,
                            side: BorderSide(color: CColors.primary),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _deleteBid(bid.id!),
                          icon: const Icon(Icons.delete_outline, size: 15),
                          label: Text('Delete', style: TextStyle(fontSize: isUrdu ? 13 : 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: CColors.error,
                            side: BorderSide(color: CColors.error),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isDeleting)
                  const Padding(
                    padding: EdgeInsets.only(top: CSizes.sm),
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBody(BidModel bid, bool isDark, bool isUrdu) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bid.message != null && bid.message!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: CSizes.sm),
            child: Text(
              '"${bid.message}"',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: isUrdu ? 15 : 13,
                color: isDark ? CColors.textWhite.withOpacity(0.7) : CColors.darkerGrey,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCardFooter(BidModel bid, bool isUrdu) {
    return Row(
      children: [
        Icon(Icons.person_outline, size: 16, color: CColors.darkGrey),
        const SizedBox(width: 6),
        FutureBuilder<String>(
          future: _getWorkerName(bid.workerId),
          builder: (context, snapshot) {
            return Text(
              snapshot.data ?? 'Worker',
              style: TextStyle(
                fontSize: isUrdu ? 13 : 11,
                color: CColors.darkGrey,
                fontWeight: FontWeight.w500,
              ),
            );
          },
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () => _showWorkerProfile(bid.workerId),
          icon: const Icon(Icons.person_rounded, size: 16, color: CColors.primary),
          label: Text(
            'View Profile',
            style: TextStyle(fontSize: isUrdu ? 12 : 10, color: CColors.primary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}