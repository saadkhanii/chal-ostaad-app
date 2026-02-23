// lib/features/worker/screens/worker_job_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';           // ← NEW
import 'package:latlong2/latlong.dart';                  // ← NEW
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/models/job_model.dart';
import '../../../core/models/bid_model.dart';
import '../../../core/services/bid_service.dart';
import '../../../core/services/location_service.dart';   // ← NEW
import '../../../core/services/map_service.dart';        // ← NEW
import '../../../shared/widgets/common_header.dart';

class WorkerJobDetailsScreen extends ConsumerStatefulWidget {
  final JobModel job;
  final String workerId;
  final String workerCategory;
  final VoidCallback onBidPlaced;

  const WorkerJobDetailsScreen({
    super.key,
    required this.job,
    required this.workerId,
    required this.workerCategory,
    required this.onBidPlaced,
  });

  @override
  ConsumerState<WorkerJobDetailsScreen> createState() =>
      _WorkerJobDetailsScreenState();
}

class _WorkerJobDetailsScreenState
    extends ConsumerState<WorkerJobDetailsScreen> {
  final _amountController  = TextEditingController();
  final _messageController = TextEditingController();
  final _bidService        = BidService();
  final _mapService        = MapService();               // ← NEW
  final _locationService   = LocationService();          // ← NEW

  bool   _isLoading       = false;
  bool   _hasExistingBid  = false;
  String _clientName      = 'common.loading'.tr();
  String? _distanceLabel;                               // ← NEW

  @override
  void initState() {
    super.initState();
    _checkExistingBid();
    _loadClientName();
    _loadDistanceToJob();   // ← NEW
  }

  Future<void> _checkExistingBid() async {
    try {
      final hasBid = await _bidService.hasWorkerBidOnJob(
          widget.workerId, widget.job.id!);
      if (mounted) setState(() => _hasExistingBid = hasBid);
    } catch (e) {
      debugPrint('Error checking existing bid: $e');
    }
  }

  Future<void> _loadClientName() async {
    try {
      final clientDoc = await FirebaseFirestore.instance
          .collection('clients')
          .doc(widget.job.clientId)
          .get();

      if (clientDoc.exists) {
        final personalInfo = clientDoc.data()!['personalInfo'];
        if (personalInfo is Map<String, dynamic>) {
          final fullName = personalInfo['fullName'];
          if (fullName is String && fullName.isNotEmpty && mounted) {
            setState(() => _clientName = fullName);
            return;
          }
        }
      }
      if (mounted) setState(() => _clientName = 'dashboard.client'.tr());
    } catch (e) {
      debugPrint('Error loading client name: $e');
      if (mounted) setState(() => _clientName = 'dashboard.client'.tr());
    }
  }

  // ── NEW: calculate distance from worker's GPS to job ─────────────
  Future<void> _loadDistanceToJob() async {
    if (!widget.job.hasLocation) return;
    try {
      final pos = await _locationService.getCurrentPosition();
      final distKm = _locationService.distanceBetweenCoords(
        pos.latitude, pos.longitude,
        widget.job.latitude!, widget.job.longitude!,
      );
      if (mounted) {
        setState(() =>
        _distanceLabel = _locationService.formatDistance(distKm));
      }
    } catch (_) {
      // GPS not available — distance label stays null, no big deal
    }
  }

  Future<void> _placeBid() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:         Text('bid.valid_amount_required'.tr()),
        backgroundColor: CColors.warning,
        behavior:        SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final bid = BidModel(
        jobId:    widget.job.id!,
        workerId: widget.workerId,
        clientId: widget.job.clientId,
        amount:   amount,
        message:  _messageController.text.isNotEmpty
            ? _messageController.text
            : null,
        createdAt: Timestamp.now(),
      );

      await _bidService.createBid(bid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('bid.bid_placed'.tr()),
          backgroundColor: CColors.success,
          behavior:        SnackBarBehavior.floating,
        ));
        widget.onBidPlaced();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('bid.place_failed'.tr(args: [e.toString()])),
          backgroundColor: CColors.error,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'open':         return 'job.status_open'.tr();
      case 'in-progress':  return 'job.status_in_progress'.tr();
      case 'completed':    return 'job.status_completed'.tr();
      case 'cancelled':    return 'job.status_cancelled'.tr();
      default:             return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':        return CColors.success;
      case 'in-progress': return CColors.warning;
      case 'completed':   return CColors.info;
      case 'cancelled':   return CColors.error;
      default:            return CColors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CommonHeader(
              title:          'dashboard.job_details'.tr(),
              showBackButton: true,
              onBackPressed:  () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildJobDetailsCard(context, isDark, isUrdu),

                  // ── Mini-map (only when job has location) ────────
                  if (widget.job.hasLocation) ...[
                    const SizedBox(height: CSizes.spaceBtwItems),
                    _buildMiniMap(isDark, isUrdu),
                  ],
                  // ─────────────────────────────────────────────────

                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildBidForm(context, isDark, isUrdu),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Job details card (your original + location row added) ─────────
  Widget _buildJobDetailsCard(BuildContext context, bool isDark, bool isUrdu) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color:  isDark ? CColors.darkContainer : CColors.white,
        border: Border.all(
          color: isDark ? CColors.darkerGrey : CColors.borderPrimary,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status chip
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:        _getStatusColor(widget.job.status)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getStatusText(widget.job.status),
                  style: TextStyle(
                    color:      _getStatusColor(widget.job.status),
                    fontWeight: FontWeight.w600,
                    fontSize:   isUrdu ? 12 : 10,
                  ),
                ),
              ),
              // Distance badge
              if (_distanceLabel != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:        CColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.near_me_rounded,
                          size: 12, color: CColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        _distanceLabel!,
                        style: TextStyle(
                          color:      CColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize:   isUrdu ? 12 : 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            widget.job.title,
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              fontWeight: FontWeight.w700,
              color:     isDark ? CColors.textWhite : CColors.textPrimary,
              fontSize:  isUrdu ? 24 : 22,
            ),
          ),
          const SizedBox(height: 8),

          // Description
          Text(
            widget.job.description,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color:    isDark
                  ? CColors.textWhite.withOpacity(0.8)
                  : CColors.darkerGrey,
              height:   1.5,
              fontSize: isUrdu ? 16 : 14,
            ),
          ),
          const SizedBox(height: 16),

          // Meta row: posted by + time
          Wrap(
            spacing:    16,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_outline,
                      size: 16, color: CColors.darkGrey),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${'job.posted_by'.tr()}: $_clientName',
                      style:
                      Theme.of(context).textTheme.bodySmall!.copyWith(
                        color:    CColors.darkGrey,
                        fontSize: isUrdu ? 14 : 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time_outlined,
                      size: 16, color: CColors.darkGrey),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      timeago.format(widget.job.createdAt.toDate()),
                      style:
                      Theme.of(context).textTheme.bodySmall!.copyWith(
                        color:    CColors.darkGrey,
                        fontSize: isUrdu ? 14 : 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Location row ────────────────────────────────────────
          if (widget.job.hasLocation) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined,
                    size: 16, color: CColors.darkGrey),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.job.displayLocation,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color:    CColors.darkGrey,
                      fontSize: isUrdu ? 14 : 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

  // ── Mini-map with directions button ──────────────────────────────
  Widget _buildMiniMap(bool isDark, bool isUrdu) {
    final jobLatLng = LatLng(widget.job.latitude!, widget.job.longitude!);

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
          // Static map preview
          FlutterMap(
            options: MapOptions(
              initialCenter: jobLatLng,
              initialZoom:   15.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              _mapService.osmTileLayer(),
              _mapService.selectedPinLayer(jobLatLng),
            ],
          ),

          // Directions button (bottom-right)
          Positioned(
            bottom: 10,
            right:  10,
            child: ElevatedButton.icon(
              onPressed: () async {
                try {
                  // Get live position for 'from', open maps app
                  final pos = await _locationService.getCurrentPosition();
                  await _mapService.openDirections(
                    from: _locationService.latLngToGeoPoint(
                        LatLng(pos.latitude, pos.longitude)),
                    to:   widget.job.location!,
                    destinationLabel: widget.job.title,
                  );
                } catch (e) {
                  // GPS unavailable — open maps with just the destination
                  await _mapService.openDirections(
                    from: widget.job.location!,
                    to:   widget.job.location!,
                    destinationLabel: widget.job.title,
                  );
                }
              },
              icon:  const Icon(Icons.directions_rounded, size: 16),
              label: Text(
                'job.get_directions'.tr(),
                style: TextStyle(fontSize: isUrdu ? 14 : 12),
              ),
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

  // ── Bid form (unchanged from your original) ───────────────────────
  Widget _buildBidForm(BuildContext context, bool isDark, bool isUrdu) {
    if (_hasExistingBid) {
      return Container(
        width:   double.infinity,
        padding: const EdgeInsets.all(CSizes.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          color:  CColors.success.withOpacity(0.1),
          border: Border.all(color: CColors.success.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 40, color: CColors.success),
            const SizedBox(height: 12),
            Text(
              'bid.already_placed'.tr(),
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                fontWeight: FontWeight.w700,
                color:      CColors.success,
                fontSize:   isUrdu ? 20 : 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'bid.already_placed_message'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color:    isDark
                    ? CColors.textWhite.withOpacity(0.8)
                    : CColors.darkerGrey,
                fontSize: isUrdu ? 16 : 14,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.job.status != 'open') {
      return Container(
        width:   double.infinity,
        padding: const EdgeInsets.all(CSizes.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          color:  CColors.warning.withOpacity(0.1),
          border: Border.all(color: CColors.warning.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            const Icon(Icons.lock_outline, size: 40, color: CColors.warning),
            const SizedBox(height: 12),
            Text(
              'job.job_closed'.tr(),
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                fontWeight: FontWeight.w700,
                color:      CColors.warning,
                fontSize:   isUrdu ? 20 : 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'job.no_longer_accepting'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color:    isDark
                    ? CColors.textWhite.withOpacity(0.8)
                    : CColors.darkerGrey,
                fontSize: isUrdu ? 16 : 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'bid.place_your_bid'.tr(),
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.w700,
            color:     isDark ? CColors.textWhite : CColors.textPrimary,
            fontSize:  isUrdu ? 22 : 20,
          ),
        ),
        const SizedBox(height: CSizes.spaceBtwItems),
        Container(
          padding: const EdgeInsets.all(CSizes.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
            color:  isDark ? CColors.darkContainer : CColors.white,
            border: Border.all(
              color: isDark ? CColors.darkerGrey : CColors.borderPrimary,
            ),
          ),
          child: Column(
            children: [
              TextField(
                controller:   _amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText:  'bid.amount_label'.tr(),
                  hintText:   'bid.amount_hint'.tr(),
                  prefixText: 'Rs. ',
                  border: OutlineInputBorder(
                    borderRadius:
                    BorderRadius.circular(CSizes.borderRadiusMd),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                    BorderRadius.circular(CSizes.borderRadiusMd),
                    borderSide: BorderSide(
                      color: isDark
                          ? CColors.darkerGrey
                          : CColors.borderPrimary,
                    ),
                  ),
                  labelStyle: TextStyle(fontSize: isUrdu ? 16 : 14),
                  hintStyle:  TextStyle(fontSize: isUrdu ? 14 : 12),
                ),
                style: TextStyle(fontSize: isUrdu ? 16 : 14),
              ),
              const SizedBox(height: CSizes.spaceBtwInputFields),
              TextField(
                controller: _messageController,
                maxLines:   3,
                decoration: InputDecoration(
                  labelText: 'bid.message_label'.tr(),
                  hintText:  'bid.message_hint'.tr(),
                  border: OutlineInputBorder(
                    borderRadius:
                    BorderRadius.circular(CSizes.borderRadiusMd),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                    BorderRadius.circular(CSizes.borderRadiusMd),
                    borderSide: BorderSide(
                      color: isDark
                          ? CColors.darkerGrey
                          : CColors.borderPrimary,
                    ),
                  ),
                  labelStyle: TextStyle(fontSize: isUrdu ? 16 : 14),
                  hintStyle:  TextStyle(fontSize: isUrdu ? 14 : 12),
                ),
                style: TextStyle(fontSize: isUrdu ? 16 : 14),
              ),
              const SizedBox(height: CSizes.spaceBtwSections),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _placeBid,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: CSizes.md),
                    backgroundColor: CColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(CSizes.borderRadiusLg),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width:  20,
                    child:  CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                      : Text(
                    'bid.submit_bid'.tr(),
                    style: TextStyle(fontSize: isUrdu ? 18 : 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _messageController.dispose();
    super.dispose();
  }
}