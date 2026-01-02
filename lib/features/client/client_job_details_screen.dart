// lib/features/client/client_job_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/bid_model.dart';
import '../../core/models/job_model.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/job_service.dart';
import '../../shared/widgets/common_header.dart';

// Provider to fetch worker details efficiently and cache them
final workerDetailsProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, workerId) async {
  try {
    final doc = await FirebaseFirestore.instance.collection('workers').doc(workerId).get();
    return doc.data();
  } catch (e) {
    debugPrint('Error fetching worker details: $e');
    return null;
  }
});

class ClientJobDetailsScreen extends ConsumerStatefulWidget {
  final JobModel job;

  const ClientJobDetailsScreen({super.key, required this.job});

  @override
  ConsumerState<ClientJobDetailsScreen> createState() => _ClientJobDetailsScreenState();
}

class _ClientJobDetailsScreenState extends ConsumerState<ClientJobDetailsScreen> {
  List<BidModel> _bids = [];
  final BidService _bidService = BidService();
  final JobService _jobService = JobService();
  bool _isLoadingBids = true;

  @override
  void initState() {
    super.initState();
    _loadBids();
  }

  Future<void> _loadBids() async {
    if (!mounted) return;
    setState(() => _isLoadingBids = true);
    try {
      final bids = await _bidService.getBidsByJob(widget.job.id!);
      if (mounted) {
        setState(() {
          _bids = bids;
          _isLoadingBids = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading bids: $e');
      if (mounted) {
        setState(() => _isLoadingBids = false);
      }
    }
  }

  Future<void> _acceptBid(BidModel bid) async {
    try {
      await _bidService.updateBidStatus(bid.id!, 'accepted');
      await _jobService.updateJobStatus(widget.job.id!, 'in-progress');
      await _loadBids();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bid accepted successfully!'),
            backgroundColor: CColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept bid: $e'),
            backgroundColor: CColors.error,
          ),
        );
      }
    }
  }

  Future<void> _rejectBid(BidModel bid) async {
    try {
      await _bidService.updateBidStatus(bid.id!, 'rejected');
      await _loadBids();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bid rejected'),
            backgroundColor: CColors.info,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject bid: $e'),
            backgroundColor: CColors.error,
          ),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open': return CColors.info;
      case 'in-progress': return CColors.warning;
      case 'completed': return CColors.success;
      case 'cancelled': return CColors.error;
      default: return CColors.grey;
    }
  }

  Color _getBidStatusColor(String status) {
    switch (status) {
      case 'pending': return CColors.warning;
      case 'accepted': return CColors.success;
      case 'rejected': return CColors.error;
      default: return CColors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CommonHeader(
              title: 'Job Details',
              showBackButton: true,
              onBackPressed: () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildJobDetailsCard(context, isDark),
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildBidsSection(context, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobDetailsCard(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: isDark ? CColors.darkContainer : CColors.white,
        border: Border.all(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(widget.job.status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.job.status.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: _getStatusColor(widget.job.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: CColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.job.category,
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: CColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            widget.job.title,
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? CColors.textWhite : CColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.job.description,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: isDark ? CColors.textWhite.withOpacity(0.8) : CColors.darkerGrey,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.access_time_outlined, size: 16, color: CColors.darkGrey),
              const SizedBox(width: 6),
              Text(
                'Posted ${timeago.format(widget.job.createdAt.toDate())}',
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: CColors.darkGrey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBidsSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bids Received (${_bids.length})',
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark ? CColors.textWhite : CColors.textPrimary,
          ),
        ),
        const SizedBox(height: CSizes.spaceBtwItems),
        _isLoadingBids
            ? const Center(child: CircularProgressIndicator())
            : _bids.isEmpty
                ? _buildEmptyBidsState(context)
                : Column(children: _bids.map((bid) => _buildBidItem(bid, context, isDark)).toList()),
      ],
    );
  }

  Widget _buildEmptyBidsState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: isDark ? CColors.darkContainer : CColors.lightContainer,
        border: Border.all(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
      ),
      child: Column(
        children: [
          Icon(Icons.gavel_outlined, size: 50, color: CColors.darkGrey.withOpacity(0.5)),
          const SizedBox(height: CSizes.md),
          Text(
            'No bids yet',
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              color: isDark ? CColors.textWhite : CColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: CSizes.sm),
          Text(
            'Bids will appear here when workers apply to your job',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: CColors.darkGrey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBidItem(BidModel bid, BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: CSizes.spaceBtwItems),
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        color: isDark ? CColors.darkContainer : CColors.white,
        border: Border.all(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _getBidStatusColor(bid.status).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_outline, size: 20, color: _getBidStatusColor(bid.status)),
          ),
          const SizedBox(width: CSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rs. ${bid.amount}',
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? CColors.textWhite : CColors.textPrimary,
                  ),
                ),
                
                // Use Riverpod to watch worker details
                Consumer(
                  builder: (context, ref, _) {
                    final workerAsync = ref.watch(workerDetailsProvider(bid.workerId));
                    
                    return workerAsync.when(
                      data: (data) {
                         final workerName = data?['name'] ?? 'Unknown Worker';
                         return Text(
                            'Worker: $workerName',
                            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              color: CColors.darkGrey,
                            ),
                          );
                      },
                      loading: () => Text(
                        'Loading worker...',
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(color: CColors.darkGrey),
                      ),
                      error: (_, __) => Text(
                        'Worker: ${bid.workerId.substring(0, 8)}...',
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(color: CColors.darkGrey),
                      ),
                    );
                  },
                ),
                
                if (bid.message != null && bid.message!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '"${bid.message!}"',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: CColors.darkGrey,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (bid.status == 'pending') ...[
            const SizedBox(width: CSizes.sm),
            Column(
               mainAxisSize: MainAxisSize.min,
               children: [
                ElevatedButton(
                  onPressed: () => _acceptBid(bid),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CColors.success,
                    foregroundColor: CColors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: const Size(60, 30),
                  ),
                  child: const Text('Accept', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 4),
                OutlinedButton(
                  onPressed: () => _rejectBid(bid),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CColors.error,
                    side: BorderSide(color: CColors.error),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: const Size(60, 30),
                  ),
                  child: const Text('Reject', style: TextStyle(fontSize: 12)),
                ),
               ],
            )
          ] else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getBidStatusColor(bid.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                bid.status.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: _getBidStatusColor(bid.status),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
