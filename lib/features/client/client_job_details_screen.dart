// lib/features/client/client_job_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';           // ← NEW
import 'package:latlong2/latlong.dart';                  // ← NEW
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/job_model.dart';
import '../../core/models/bid_model.dart';
import '../../core/services/map_service.dart';           // ← NEW
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title: 'job.job_details'.tr(),
            showBackButton: true,
            onBackPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildJobDetails(context, isDark, isUrdu),
                  // ── Mini-map (shown only when job has location) ──
                  if (widget.job.hasLocation) ...[
                    const SizedBox(height: CSizes.spaceBtwItems),
                    _buildMiniMap(isDark),
                  ],
                  // ─────────────────────────────────────────────────
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
  Widget _buildJobDetails(BuildContext context, bool isDark, bool isUrdu) {
    return Container(
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.job.title,
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              fontWeight: FontWeight.bold,
              fontSize:   isUrdu ? 24 : 22,
            ),
          ),
          const SizedBox(height: CSizes.sm),
          Text(
            widget.job.description,
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(
              fontSize: isUrdu ? 18 : 16,
            ),
          ),
          const SizedBox(height: CSizes.md),

          // Category row
          Row(children: [
            Icon(Icons.category, size: 20, color: CColors.primary),
            const SizedBox(width: 8),
            Text(
              widget.job.category,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: isUrdu ? 16 : 14,
              ),
            ),
          ]),
          const SizedBox(height: CSizes.sm),

          // Time row
          Row(children: [
            Icon(Icons.access_time, size: 20, color: CColors.primary),
            const SizedBox(width: 8),
            Text(
              timeago.format(widget.job.createdAt.toDate()),
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: isUrdu ? 16 : 14,
              ),
            ),
          ]),

          // ── Location row (only when job has location) ──────────
          if (widget.job.hasLocation) ...[
            const SizedBox(height: CSizes.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined,
                    size: 20, color: CColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.job.displayLocation,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontSize: isUrdu ? 16 : 14,
                    ),
                  ),
                ),
              ],
            ),
          ],
          // ────────────────────────────────────────────────────────
        ],
      ),
    );
  }

  // ── Mini-map ─────────────────────────────────────────────────────
  Widget _buildMiniMap(bool isDark) {
    final jobLatLng = LatLng(
      widget.job.latitude!,
      widget.job.longitude!,
    );

    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        border: Border.all(
          color: isDark ? CColors.darkerGrey : CColors.borderPrimary,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Map widget — non-interactive (mini preview)
          FlutterMap(
            options: MapOptions(
              initialCenter: jobLatLng,
              initialZoom:   15.0,
              interactionOptions: const InteractionOptions(
                // Disable all gestures so it's a static preview
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              _mapService.osmTileLayer(),
              _mapService.selectedPinLayer(jobLatLng),
            ],
          ),

          // "Get Directions" button overlay (bottom-right)
          Positioned(
            bottom: 10,
            right:  10,
            child: ElevatedButton.icon(
              onPressed: () async {
                try {
                  // Get worker's current position for 'from'
                  final locationService =
                      _mapService.locationPickerScreen; // just for access
                  // Open directions with job as destination
                  // 'from' will be the device's current location via maps app
                  final uri = Uri.parse(
                    'https://www.google.com/maps/dir/?api=1'
                        '&destination=${widget.job.latitude},${widget.job.longitude}'
                        '&travelmode=driving',
                  );
                  await _mapService.openDirections(
                    // Use a neutral 'from' — maps app will use device location
                    from: widget.job.location!,
                    to:   widget.job.location!,
                    destinationLabel: widget.job.title,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not open maps: $e'),
                        backgroundColor: CColors.error,
                      ),
                    );
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
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bids list ─────────────────────────────────────────────────────
  Widget _buildBidsList(BuildContext context, bool isDark, bool isUrdu) {
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
            child: Text(
              'bid.no_bids_yet'.tr(),
              style: TextStyle(fontSize: isUrdu ? 16 : 14),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'bid.bids_received'.tr(),
              style: Theme.of(context).textTheme.titleLarge!.copyWith(
                fontWeight: FontWeight.bold,
                fontSize:   isUrdu ? 22 : 20,
              ),
            ),
            const SizedBox(height: CSizes.md),
            ListView.builder(
              shrinkWrap: true,
              physics:    const NeverScrollableScrollPhysics(),
              itemCount:  snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                final bid = BidModel.fromSnapshot(
                    doc as DocumentSnapshot<Map<String, dynamic>>);
                return _buildBidCard(bid, context, isUrdu);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildBidCard(BidModel bid, BuildContext context, bool isUrdu) {
    return Card(
      margin: const EdgeInsets.only(bottom: CSizes.sm),
      child: ListTile(
        title: Text(
          '${'bid.amount'.tr()}: Rs. ${bid.amount.toStringAsFixed(0)}',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: isUrdu ? 18 : 16),
        ),
        subtitle: bid.message != null ? Text(bid.message!) : null,
        trailing: ElevatedButton(
          onPressed: () {
            // Handle accept bid
          },
          child: Text('bid.accept'.tr()),
        ),
      ),
    );
  }
}