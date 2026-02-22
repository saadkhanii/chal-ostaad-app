// lib/features/client/client_job_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/bid_model.dart';
import '../../core/models/job_model.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/job_service.dart';
import '../../core/services/map_service.dart';
import '../../shared/widgets/common_header.dart';

class ClientJobDetailsScreen extends ConsumerStatefulWidget {
  final JobModel job;

  const ClientJobDetailsScreen({super.key, required this.job});

  @override
  ConsumerState<ClientJobDetailsScreen> createState() =>
      _ClientJobDetailsScreenState();
}

class _ClientJobDetailsScreenState
    extends ConsumerState<ClientJobDetailsScreen> {
  final _mapService = MapService();
  final _bidService = BidService();
  final _jobService = JobService();

  // Track which bid is being accepted — shows spinner on that button only
  String? _acceptingBidId;

  // Local copy of job status so UI updates instantly
  late String _jobStatus;

  @override
  void initState() {
    super.initState();
    _jobStatus = widget.job.status;
  }

  // ── Accept bid ────────────────────────────────────────────────────
  Future<void> _acceptBid(BidModel bid) async {
    // Confirm dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept Bid?'),
        content: Text(
          'Accept this bid for Rs. ${bid.amount.toStringAsFixed(0)}?\n'
              'All other bids will be rejected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: CColors.primary),
            child: Text('bid.accept'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _acceptingBidId = bid.id);

    try {
      // 1. Accept this bid
      await _bidService.updateBidStatus(bid.id!, 'accepted');

      // 2. Reject all other pending bids on this job
      final allBids = await _bidService.getBidsByJob(widget.job.id!);
      for (final other in allBids) {
        if (other.id != bid.id && other.status == 'pending') {
          await _bidService.updateBidStatus(other.id!, 'rejected');
        }
      }

      // 3. Mark job as in-progress
      await _jobService.updateJobStatus(widget.job.id!, 'in-progress');

      if (mounted) {
        setState(() {
          _jobStatus      = 'in-progress';
          _acceptingBidId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         const Text('Bid accepted! Job is now in progress.'),
          backgroundColor: CColors.success,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _acceptingBidId = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Failed to accept bid: $e'),
          backgroundColor: CColors.error,
          behavior:        SnackBarBehavior.floating,
        ));
      }
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
            title:          'job.job_details'.tr(),
            showBackButton: true,
            onBackPressed:  () => Navigator.pop(context),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildJobDetails(context, isDark, isUrdu),
                  if (widget.job.hasLocation) ...[
                    const SizedBox(height: CSizes.spaceBtwItems),
                    _buildMiniMap(isDark),
                  ],
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildBidsList(context, isDark, isUrdu),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Job info card ─────────────────────────────────────────────────
  Widget _buildJobDetails(
      BuildContext context, bool isDark, bool isUrdu) {
    return Container(
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.job.title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall!
                      .copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize:   isUrdu ? 24 : 22),
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusChip(_jobStatus, isUrdu),
            ],
          ),
          const SizedBox(height: CSizes.sm),
          Text(widget.job.description,
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                  fontSize: isUrdu ? 18 : 16)),
          const SizedBox(height: CSizes.md),
          Row(children: [
            Icon(Icons.category, size: 20, color: CColors.primary),
            const SizedBox(width: 8),
            Text(widget.job.category,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    fontSize: isUrdu ? 16 : 14)),
          ]),
          const SizedBox(height: CSizes.sm),
          Row(children: [
            Icon(Icons.access_time, size: 20, color: CColors.primary),
            const SizedBox(width: 8),
            Text(timeago.format(widget.job.createdAt.toDate()),
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    fontSize: isUrdu ? 16 : 14)),
          ]),
          if (widget.job.hasLocation) ...[
            const SizedBox(height: CSizes.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined,
                    size: 20, color: CColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.job.displayLocation,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium!
                          .copyWith(fontSize: isUrdu ? 16 : 14)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Status chip ───────────────────────────────────────────────────
  Widget _buildStatusChip(String status, bool isUrdu) {
    Color  color;
    String label;
    switch (status) {
      case 'open':
        color = CColors.success;
        label = 'job.status_open'.tr();
        break;
      case 'in-progress':
        color = CColors.warning;
        label = 'job.status_in_progress'.tr();
        break;
      case 'completed':
        color = CColors.info;
        label = 'job.status_completed'.tr();
        break;
      case 'cancelled':
        color = CColors.error;
        label = 'job.status_cancelled'.tr();
        break;
      default:
        color = CColors.grey;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color:      color,
              fontWeight: FontWeight.bold,
              fontSize:   isUrdu ? 12 : 10)),
    );
  }

  // ── Mini-map ──────────────────────────────────────────────────────
  Widget _buildMiniMap(bool isDark) {
    final jobLatLng =
    LatLng(widget.job.latitude!, widget.job.longitude!);

    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        border: Border.all(
            color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: jobLatLng,
              initialZoom:   15.0,
              interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none),
            ),
            children: [
              _mapService.osmTileLayer(),
              _mapService.selectedPinLayer(jobLatLng),
            ],
          ),
          Positioned(
            bottom: 10,
            right:  10,
            child: ElevatedButton.icon(
              onPressed: () async {
                try {
                  await _mapService.openDirections(
                    from:             widget.job.location!,
                    to:               widget.job.location!,
                    destinationLabel: widget.job.title,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:         Text('Could not open maps: $e'),
                      backgroundColor: CColors.error,
                    ));
                  }
                }
              },
              icon:  const Icon(Icons.directions_rounded, size: 16),
              label: Text('job.directions'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: CColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bids list ─────────────────────────────────────────────────────
  Widget _buildBidsList(
      BuildContext context, bool isDark, bool isUrdu) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bids')
          .where('jobId', isEqualTo: widget.job.id)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text('bid.no_bids_yet'.tr(),
                style: TextStyle(fontSize: isUrdu ? 16 : 14)),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('bid.bids_received'.tr(),
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize:   isUrdu ? 22 : 20)),
            const SizedBox(height: CSizes.md),
            ListView.builder(
              shrinkWrap: true,
              physics:    const NeverScrollableScrollPhysics(),
              itemCount:  snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                final bid = BidModel.fromSnapshot(
                    doc as DocumentSnapshot<Map<String, dynamic>>);
                return _buildBidCard(bid, context, isDark, isUrdu);
              },
            ),
          ],
        );
      },
    );
  }

  // ── Bid card ──────────────────────────────────────────────────────
  Widget _buildBidCard(BidModel bid, BuildContext context,
      bool isDark, bool isUrdu) {
    final isAccepted  = bid.status == 'accepted';
    final isRejected  = bid.status == 'rejected';
    final isAccepting = _acceptingBidId == bid.id;
    final canAccept   =
        _jobStatus == 'open' && !isRejected && !isAccepted;

    return Card(
      margin: const EdgeInsets.only(bottom: CSizes.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        side: isAccepted
            ? const BorderSide(color: CColors.success, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(CSizes.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Amount + status badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Rs. ${bid.amount.toStringAsFixed(0)}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium!
                      .copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize:   isUrdu ? 20 : 18,
                    color:      CColors.primary,
                  ),
                ),
                _buildBidStatusBadge(bid.status, isUrdu),
              ],
            ),

            // Message
            if (bid.message != null && bid.message!.isNotEmpty) ...[
              const SizedBox(height: CSizes.sm),
              Text(bid.message!,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    fontSize: isUrdu ? 15 : 13,
                    color:    isDark
                        ? CColors.textWhite.withOpacity(0.7)
                        : CColors.darkerGrey,
                  )),
            ],

            // Accept button — only shown on open jobs for pending bids
            if (canAccept) ...[
              const SizedBox(height: CSizes.md),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                  isAccepting ? null : () => _acceptBid(bid),
                  icon: isAccepting
                      ? const SizedBox(
                      width:  16,
                      height: 16,
                      child:  CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                      : const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18),
                  label: Text(
                    isAccepting
                        ? 'common.loading'.tr()
                        : 'bid.accept'.tr(),
                    style: TextStyle(fontSize: isUrdu ? 16 : 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            CSizes.borderRadiusMd)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Bid status badge ──────────────────────────────────────────────
  Widget _buildBidStatusBadge(String status, bool isUrdu) {
    Color  color;
    String label;
    switch (status) {
      case 'accepted':
        color = CColors.success; label = 'Accepted'; break;
      case 'rejected':
        color = CColors.error;   label = 'Rejected';  break;
      default:
        color = CColors.warning; label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color:      color,
              fontWeight: FontWeight.bold,
              fontSize:   isUrdu ? 12 : 10)),
    );
  }
}