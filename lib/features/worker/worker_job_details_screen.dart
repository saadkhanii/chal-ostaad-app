// lib/features/worker/screens/worker_job_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';
import 'dart:async';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/models/job_model.dart';
import '../../../core/models/bid_model.dart';
import '../../../core/services/bid_service.dart';
import '../../../core/services/job_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/map_service.dart';
import '../../../core/services/payment_service.dart';
import '../../../shared/widgets/common_header.dart';
import '../../../core/services/chat_service.dart';
import '../chat/chat_screen.dart';
import '../dispute/raise_dispute_dialog.dart';
import '../dispute/dispute_status_banner.dart';
import '../payment/extra_charges_sheet.dart';

class WorkerJobDetailsScreen extends ConsumerStatefulWidget {
  final JobModel job;
  final String   workerId;
  final String   workerCategory;
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
  final _jobService        = JobService();
  final _chatService       = ChatService();
  final _mapService        = MapService();
  final _locationService   = LocationService();
  final _paymentService    = PaymentService();

  bool      _isLoading              = false;
  bool      _hasExistingBid         = false;
  BidModel? _acceptedBid;
  String    _clientName             = 'common.loading'.tr();
  String?   _distanceLabel;
  bool      _isCancelling           = false;
  bool      _confirmingCash         = false;

  late String _liveJobStatus;
  Map<String, dynamic>? _pendingProgressRequest;
  bool _isRequestingProgress = false;

  // Extra charges notification
  bool _hasPendingExtras = false;

  // Cash payment
  String? _pendingPaymentId;

  StreamSubscription<DocumentSnapshot>? _jobSub;

  String _clientFullName = '';

  @override
  void initState() {
    super.initState();
    _liveJobStatus = widget.job.status;
    _checkExistingBid();
    _loadClientName();
    _loadDistanceToJob();
    _subscribeToJob();
    _loadPendingPayment();
  }

  void _subscribeToJob() {
    _jobSub = FirebaseFirestore.instance
        .collection('jobs')
        .doc(widget.job.id)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final data    = snap.data() as Map<String, dynamic>;
      final status  = data['status']          as String? ?? _liveJobStatus;
      final request = data['progressRequest'] as Map<String, dynamic>?;
      final rawExtras = data['extraCharges']  as List<dynamic>? ?? [];
      final hasPending = rawExtras
          .map((e) => Map<String, dynamic>.from(e as Map))
          .any((c) => c['status'] == 'pending' && c['requestedBy'] != 'worker');
      setState(() {
        _liveJobStatus          = status;
        _pendingProgressRequest = request;
        _hasPendingExtras       = hasPending;
      });
    });
  }

  @override
  void dispose() {
    _jobSub?.cancel();
    _amountController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingPayment() async {
    if (widget.job.id == null) return;
    try {
      final payment = await _paymentService.getPaymentByJobId(widget.job.id!);
      if (payment != null && payment.isCash && payment.status == 'pending') {
        if (mounted) setState(() => _pendingPaymentId = payment.id);
      }
    } catch (_) {}
  }

  Future<void> _checkExistingBid() async {
    try {
      final hasBid =
      await _bidService.hasWorkerBidOnJob(widget.workerId, widget.job.id!);
      if (mounted) setState(() => _hasExistingBid = hasBid);

      if (hasBid) {
        final snapshot = await FirebaseFirestore.instance
            .collection('bids')
            .where('jobId',    isEqualTo: widget.job.id)
            .where('workerId', isEqualTo: widget.workerId)
            .where('status',   isEqualTo: 'accepted')
            .limit(1)
            .get();
        if (snapshot.docs.isNotEmpty && mounted) {
          setState(() {
            _acceptedBid = BidModel.fromSnapshot(
              snapshot.docs.first
              as DocumentSnapshot<Map<String, dynamic>>,
            );
          });
        }
      }
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
            setState(() {
              _clientName     = fullName;
              _clientFullName = fullName;
            });
            return;
          }
        }
      }
      if (mounted) setState(() => _clientName = 'dashboard.client'.tr());
    } catch (e) {
      if (mounted) setState(() => _clientName = 'dashboard.client'.tr());
    }
  }

  Future<void> _loadDistanceToJob() async {
    if (!widget.job.hasLocation) return;
    try {
      final pos = await _locationService.getCurrentPosition();
      final distKm = _locationService.distanceBetweenCoords(
        pos.latitude, pos.longitude,
        widget.job.latitude!, widget.job.longitude!,
      );
      if (mounted) {
        setState(() => _distanceLabel = _locationService.formatDistance(distKm));
      }
    } catch (_) {}
  }

  // ── Request job completion ────────────────────────────────────────
  Future<void> _requestProgressUpdate() async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Completion Approval'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Send the client a request to mark this job as complete.'
                  '\n\nOptional note:'),
          const SizedBox(height: 12),
          TextField(
            controller: noteController,
            maxLines:   3,
            decoration: InputDecoration(
              hintText: 'e.g. All work is done, please review.',
              border:   OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: CColors.primary),
            child: const Text('Send Request',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRequestingProgress = true);
    try {
      await _jobService.requestProgressUpdate(
        jobId:    widget.job.id!,
        workerId: widget.workerId,
        clientId: widget.job.clientId,
        jobTitle: widget.job.title,
        note:     noteController.text.trim().isEmpty
            ? null
            : noteController.text.trim(),
      );
      if (mounted) {
        setState(() => _isRequestingProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:         Text('Completion request sent!'),
          backgroundColor: CColors.success,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRequestingProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Failed: $e'),
          backgroundColor: CColors.error,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Cancel job (worker side) ──────────────────────────────────────
  Future<void> _cancelJob() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Job?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Are you sure you want to cancel this job? '
                  'The client will be notified.'),
          const SizedBox(height: 12),
          TextField(
            controller: reasonController,
            decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: CColors.error),
            child: const Text('Cancel Job',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isCancelling = true);
    try {
      await _bidService.cancelJob(
        jobId:       widget.job.id!,
        cancelledBy: 'worker',
        reason:      reasonController.text.trim().isEmpty
            ? null
            : reasonController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _liveJobStatus = 'cancelled';
          _isCancelling  = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:         Text('Job cancelled.'),
          backgroundColor: CColors.warning,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Failed to cancel: $e'),
          backgroundColor: CColors.error,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Confirm cash receipt ──────────────────────────────────────────
  Future<void> _confirmCashReceived() async {
    if (_pendingPaymentId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Cash Receipt'),
        content: Text(
          'Confirm you have received Rs. '
              '${_acceptedBid?.amount.toStringAsFixed(0) ?? ''} in cash from the client?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: CColors.success),
            child: const Text('Confirm',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _confirmingCash = true);
    try {
      await _paymentService.confirmCashReceived(
        paymentId: _pendingPaymentId!,
        jobId:     widget.job.id!,
      );
      if (mounted) {
        setState(() {
          _confirmingCash   = false;
          _pendingPaymentId = null;
          _liveJobStatus    = 'completed';
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:         Text('Cash confirmed! Job marked as completed.'),
          backgroundColor: CColors.success,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _confirmingCash = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Error: $e'),
          backgroundColor: CColors.error,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Place bid ─────────────────────────────────────────────────────
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
          content: Text('bid.place_failed'.tr(args: [e.toString()])),
          backgroundColor: CColors.error,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getStatusColor(String s) {
    switch (s) {
      case 'open':        return CColors.success;
      case 'in-progress': return CColors.warning;
      case 'completed':   return CColors.info;
      case 'cancelled':   return CColors.error;
      default:            return CColors.grey;
    }
  }

  String _getStatusText(String s) {
    switch (s) {
      case 'open':        return 'job.status_open'.tr();
      case 'in-progress': return 'job.status_in_progress'.tr();
      case 'completed':   return 'job.status_completed'.tr();
      case 'cancelled':   return 'job.status_cancelled'.tr();
      default:            return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CommonHeader(
            title:          'job.job_details'.tr(),
            showBackButton: true,
            onBackPressed:  () => Navigator.pop(context),
          ),
          Padding(
            padding: const EdgeInsets.all(CSizes.defaultSpace),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildJobDetailsCard(isDark, isUrdu),

                if (widget.job.hasLocation) ...[
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildMiniMap(isDark, isUrdu),
                ],

                // Extra charges
                if (_acceptedBid != null &&
                    (_liveJobStatus == 'in-progress' ||
                        _liveJobStatus == 'completed')) ...[
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildExtraChargesCard(isDark, isUrdu),
                ],

                // Cash confirmation banner
                if (_pendingPaymentId != null &&
                    _liveJobStatus == 'in-progress') ...[
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildCashConfirmBanner(isDark, isUrdu),
                ],

                const SizedBox(height: CSizes.spaceBtwSections),
                _buildBidForm(isDark, isUrdu),

                // Progress controls
                if (_acceptedBid != null &&
                    _liveJobStatus == 'in-progress') ...[
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildProgressSection(isDark, isUrdu),
                ],

                // Completed banner
                if (_acceptedBid != null &&
                    _liveJobStatus == 'completed') ...[
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildCompletedBanner(isDark, isUrdu),
                ],

                // Dispute
                if (_acceptedBid != null) ...[
                  const SizedBox(height: CSizes.spaceBtwSections),
                  DisputeStatusBanner(
                    jobId:           widget.job.id!,
                    currentUserId:   widget.workerId,
                    currentUserRole: 'worker',
                  ),
                ],

                if (_acceptedBid != null &&
                    (_liveJobStatus == 'in-progress' ||
                        _liveJobStatus == 'completed')) ...[
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildRaiseDisputeButton(isDark, isUrdu),
                ],

                // Cancel button
                if (_acceptedBid != null &&
                    _liveJobStatus == 'in-progress') ...[
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildCancelButton(isDark, isUrdu),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Job details card ──────────────────────────────────────────────
  Widget _buildJobDetailsCard(bool isDark, bool isUrdu) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color:  isDark ? CColors.darkContainer : CColors.white,
        border: Border.all(
            color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:        _getStatusColor(_liveJobStatus).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_getStatusText(_liveJobStatus),
                style: TextStyle(
                    color:      _getStatusColor(_liveJobStatus),
                    fontWeight: FontWeight.w600,
                    fontSize:   isUrdu ? 12 : 10)),
          ),
          if (_distanceLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:        CColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.near_me_rounded,
                    size: 12, color: CColors.primary),
                const SizedBox(width: 4),
                Text(_distanceLabel!,
                    style: const TextStyle(
                        color:      CColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize:   10)),
              ]),
            ),
          if (_hasPendingExtras)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:        CColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_amber_rounded,
                    size: 12, color: CColors.warning),
                SizedBox(width: 4),
                Text('Extras Pending',
                    style: TextStyle(
                        color:      CColors.warning,
                        fontWeight: FontWeight.w600,
                        fontSize:   10)),
              ]),
            ),
        ]),
        const SizedBox(height: 16),
        Text(widget.job.title,
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                fontWeight: FontWeight.w700, fontSize: isUrdu ? 24 : 22)),
        const SizedBox(height: 8),
        Text(widget.job.description,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color:    isDark
                    ? CColors.textWhite.withOpacity(0.8)
                    : CColors.darkerGrey,
                height:   1.5,
                fontSize: isUrdu ? 16 : 14)),
        const SizedBox(height: 16),
        Wrap(spacing: 16, runSpacing: 8, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.person_outline,
                size: 16, color: CColors.darkGrey),
            const SizedBox(width: 6),
            Flexible(
                child: Text('${'job.posted_by'.tr()}: $_clientName',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: CColors.darkGrey, fontSize: isUrdu ? 14 : 12),
                    overflow: TextOverflow.ellipsis, maxLines: 1)),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.access_time_outlined,
                size: 16, color: CColors.darkGrey),
            const SizedBox(width: 6),
            Text(timeago.format(widget.job.createdAt.toDate()),
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: CColors.darkGrey, fontSize: isUrdu ? 14 : 12)),
          ]),
        ]),
        if (widget.job.hasLocation) ...[
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.location_on_outlined,
                size: 16, color: CColors.darkGrey),
            const SizedBox(width: 6),
            Flexible(
                child: Text(widget.job.displayLocation,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: CColors.darkGrey, fontSize: isUrdu ? 14 : 12),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
        ],
      ]),
    );
  }

  // ── Extra charges card ────────────────────────────────────────────
  Widget _buildExtraChargesCard(bool isDark, bool isUrdu) {
    return Container(
      padding:    const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border:       Border.all(
            color: _hasPendingExtras
                ? CColors.warning.withOpacity(0.5)
                : (isDark ? CColors.darkerGrey : CColors.borderPrimary)),
      ),
      child: Row(children: [
        Icon(
          _hasPendingExtras
              ? Icons.warning_amber_rounded
              : Icons.add_circle_outline,
          color: _hasPendingExtras ? CColors.warning : CColors.primary,
          size:  22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _hasPendingExtras
                  ? 'Extra charge awaiting your approval'
                  : 'Extra Charges',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: _hasPendingExtras
                      ? CColors.warning
                      : (isDark ? CColors.textWhite : CColors.textPrimary)),
            ),
            const Text('View, approve or propose additional charges',
                style: TextStyle(fontSize: 12, color: CColors.darkGrey)),
          ]),
        ),
        TextButton(
          onPressed: () => ExtraChargesSheet.show(
            context,
            jobId:       widget.job.id!,
            currentRole: 'worker',
          ),
          child: const Text('Manage'),
        ),
      ]),
    );
  }

  // ── Cash confirm banner ───────────────────────────────────────────
  Widget _buildCashConfirmBanner(bool isDark, bool isUrdu) {
    return Container(
      padding:    const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color:        CColors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border:       Border.all(color: CColors.warning.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.payments_outlined, color: CColors.warning, size: 20),
          SizedBox(width: 8),
          Text('Cash Payment Pending',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color:      CColors.warning,
                  fontSize:   15)),
        ]),
        const SizedBox(height: 6),
        const Text(
          'The client has chosen to pay in cash. '
              'Once you receive the cash, confirm below to complete the job.',
          style: TextStyle(fontSize: 13, color: CColors.darkGrey),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _confirmingCash ? null : _confirmCashReceived,
            icon:  const Icon(Icons.check_circle_outline),
            label: _confirmingCash
                ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
                : const Text('Confirm Cash Received'),
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Mini map ──────────────────────────────────────────────────────
  Widget _buildMiniMap(bool isDark, bool isUrdu) {
    final jobLatLng = LatLng(widget.job.latitude!, widget.job.longitude!);
    return Container(
      height:       200,
      decoration:   BoxDecoration(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          border: Border.all(
              color: isDark ? CColors.darkerGrey : CColors.borderPrimary)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
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
          bottom: 10, right: 10,
          child: ElevatedButton.icon(
            onPressed: () async {
              try {
                final pos = await _locationService.getCurrentPosition();
                await _mapService.openDirections(
                  from: _locationService.latLngToGeoPoint(
                      LatLng(pos.latitude, pos.longitude)),
                  to:   widget.job.location!,
                  destinationLabel: widget.job.title,
                );
              } catch (e) {
                await _mapService.openDirections(
                  from:             widget.job.location!,
                  to:               widget.job.location!,
                  destinationLabel: widget.job.title,
                );
              }
            },
            icon:  const Icon(Icons.directions_rounded, size: 16),
            label: Text('job.get_directions'.tr(),
                style: TextStyle(fontSize: isUrdu ? 14 : 12)),
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
      ]),
    );
  }

  // ── Bid form ──────────────────────────────────────────────────────
  Widget _buildBidForm(bool isDark, bool isUrdu) {
    if (_acceptedBid != null) return _buildAcceptedPanel(isDark, isUrdu);

    if (_hasExistingBid) {
      return Container(
        width:   double.infinity,
        padding: const EdgeInsets.all(CSizes.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          color:  CColors.success.withOpacity(0.1),
          border: Border.all(color: CColors.success.withOpacity(0.3)),
        ),
        child: Column(children: [
          const Icon(Icons.check_circle_outline,
              size: 40, color: CColors.success),
          const SizedBox(height: 12),
          Text('bid.already_placed'.tr(),
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.w700,
                  color:      CColors.success,
                  fontSize:   isUrdu ? 20 : 18)),
          const SizedBox(height: 8),
          Text('bid.already_placed_message'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color:    isDark
                      ? CColors.textWhite.withOpacity(0.8)
                      : CColors.darkerGrey,
                  fontSize: isUrdu ? 16 : 14)),
        ]),
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
        child: Column(children: [
          const Icon(Icons.lock_outline, size: 40, color: CColors.warning),
          const SizedBox(height: 12),
          Text('job.job_closed'.tr(),
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.w700,
                  color:      CColors.warning,
                  fontSize:   isUrdu ? 20 : 18)),
          const SizedBox(height: 8),
          Text('job.no_longer_accepting'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color:    isDark
                      ? CColors.textWhite.withOpacity(0.8)
                      : CColors.darkerGrey,
                  fontSize: isUrdu ? 16 : 14)),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('bid.place_your_bid'.tr(),
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
              fontWeight: FontWeight.w700,
              fontSize:   isUrdu ? 22 : 20)),
      const SizedBox(height: CSizes.spaceBtwItems),
      Container(
        padding: const EdgeInsets.all(CSizes.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          color:  isDark ? CColors.darkContainer : CColors.white,
          border: Border.all(
              color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
        ),
        child: Column(children: [
          TextField(
            controller:   _amountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText:  'bid.amount_label'.tr(),
              hintText:   'bid.amount_hint'.tr(),
              prefixText: 'Rs. ',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(CSizes.borderRadiusMd),
                borderSide: BorderSide(
                    color: isDark
                        ? CColors.darkerGrey
                        : CColors.borderPrimary),
              ),
            ),
          ),
          const SizedBox(height: CSizes.spaceBtwInputFields),
          TextField(
            controller: _messageController,
            maxLines:   3,
            decoration: InputDecoration(
              labelText: 'bid.message_label'.tr(),
              hintText:  'bid.message_hint'.tr(),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(CSizes.borderRadiusMd),
                borderSide: BorderSide(
                    color: isDark
                        ? CColors.darkerGrey
                        : CColors.borderPrimary),
              ),
            ),
          ),
          const SizedBox(height: CSizes.spaceBtwSections),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _placeBid,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: CSizes.md),
                backgroundColor: CColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(CSizes.borderRadiusLg)),
              ),
              child: _isLoading
                  ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                  : Text('bid.submit_bid'.tr(),
                  style: TextStyle(fontSize: isUrdu ? 18 : 16)),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ── Progress section ──────────────────────────────────────────────
  Widget _buildProgressSection(bool isDark, bool isUrdu) {
    final hasPending = _pendingProgressRequest != null &&
        _pendingProgressRequest!['status'] == 'pending';

    if (hasPending) {
      return Container(
        width:   double.infinity,
        padding: const EdgeInsets.all(CSizes.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          color:  CColors.info.withOpacity(0.08),
          border: Border.all(color: CColors.info.withOpacity(0.3)),
        ),
        child: Column(children: [
          const SizedBox(
            width: 36, height: 36,
            child: CircularProgressIndicator(
                color: CColors.info, strokeWidth: 2.5),
          ),
          const SizedBox(height: 14),
          Text('Awaiting Client Approval',
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.bold,
                  color:      CColors.info,
                  fontSize:   isUrdu ? 18 : 16)),
          const SizedBox(height: 8),
          Text(
            'Your completion request has been sent. '
                'The client will review and approve or reject it.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color:    isDark
                    ? CColors.textWhite.withOpacity(0.75)
                    : CColors.darkerGrey,
                fontSize: isUrdu ? 15 : 13),
          ),
        ]),
      );
    }

    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color:  isDark ? CColors.darkContainer : CColors.white,
        border: Border.all(
            color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Update Job Progress',
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
                fontWeight: FontWeight.bold, fontSize: isUrdu ? 18 : 16)),
        const SizedBox(height: 8),
        Text(
          'Once you have finished, send the client a request to '
              'mark this job as complete.',
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color:    isDark
                  ? CColors.textWhite.withOpacity(0.75)
                  : CColors.darkerGrey,
              fontSize: isUrdu ? 15 : 13),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed:
            _isRequestingProgress ? null : _requestProgressUpdate,
            icon: _isRequestingProgress
                ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.task_alt_rounded, size: 20),
            label: Text(
              _isRequestingProgress
                  ? 'common.loading'.tr()
                  : 'Request Completion Approval',
              style: TextStyle(
                  fontSize:   isUrdu ? 16 : 14,
                  fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(CSizes.borderRadiusLg)),
              elevation: 2,
            ),
          ),
        ),
      ]),
    );
  }

  // ── Completed banner ──────────────────────────────────────────────
  Widget _buildCompletedBanner(bool isDark, bool isUrdu) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            CColors.info.withOpacity(0.12),
            CColors.success.withOpacity(0.08),
          ],
        ),
        border: Border.all(color: CColors.info.withOpacity(0.4)),
      ),
      child: Column(children: [
        Container(
          padding:    const EdgeInsets.all(12),
          decoration: const BoxDecoration(
              color:  Color(0x260288D1), shape: BoxShape.circle),
          child: const Icon(Icons.verified_rounded,
              size: 36, color: CColors.info),
        ),
        const SizedBox(height: 14),
        Text('Job Completed!',
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
                fontWeight: FontWeight.bold,
                color:      CColors.info,
                fontSize:   isUrdu ? 22 : 20)),
        const SizedBox(height: 8),
        Text('The client has approved the completion. Great work!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color:    isDark
                    ? CColors.textWhite.withOpacity(0.75)
                    : CColors.darkerGrey,
                fontSize: isUrdu ? 15 : 13)),
      ]),
    );
  }

  // ── Accepted panel ────────────────────────────────────────────────
  Widget _buildAcceptedPanel(bool isDark, bool isUrdu) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            CColors.success.withOpacity(0.12),
            CColors.primary.withOpacity(0.08),
          ],
        ),
        border: Border.all(color: CColors.success.withOpacity(0.4)),
      ),
      child: Column(children: [
        Container(
          padding:    const EdgeInsets.all(16),
          decoration: const BoxDecoration(
              color:  Color(0x2643A047), shape: BoxShape.circle),
          child: const Icon(Icons.emoji_events_rounded,
              size: 40, color: CColors.success),
        ),
        const SizedBox(height: 16),
        Text('bid.bid_accepted_congrats'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
                fontWeight: FontWeight.w800,
                color:      CColors.success,
                fontSize:   isUrdu ? 22 : 20)),
        const SizedBox(height: 8),
        Text('bid.bid_accepted_message'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color:    isDark
                    ? CColors.textWhite.withOpacity(0.75)
                    : CColors.darkerGrey,
                fontSize: isUrdu ? 15 : 13,
                height:   1.5)),
        if (_acceptedBid != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color:        CColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: CColors.primary.withOpacity(0.3)),
            ),
            child: Text('Rs. ${_acceptedBid!.amount.toStringAsFixed(0)}',
                style: const TextStyle(
                    color:      CColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize:   14)),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openChat,
            icon:  const Icon(Icons.chat_rounded, size: 20),
            label: Text('chat.open_chat'.tr(),
                style: TextStyle(
                    fontSize:   isUrdu ? 17 : 15,
                    fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(CSizes.borderRadiusLg)),
              elevation:   3,
              shadowColor: CColors.primary.withOpacity(0.4),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Cancel button ─────────────────────────────────────────────────
  Widget _buildCancelButton(bool isDark, bool isUrdu) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isCancelling ? null : _cancelJob,
        icon: _isCancelling
            ? const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
                color: CColors.warning, strokeWidth: 2))
            : const Icon(Icons.cancel_outlined, color: CColors.warning),
        label: Text('Cancel Job',
            style: TextStyle(
                color:      CColors.warning,
                fontWeight: FontWeight.w600,
                fontSize:   isUrdu ? 15 : 13)),
        style: OutlinedButton.styleFrom(
          side:    const BorderSide(color: CColors.warning),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius:
              BorderRadius.circular(CSizes.borderRadiusLg)),
        ),
      ),
    );
  }

  // ── Raise dispute button ──────────────────────────────────────────
  Widget _buildRaiseDisputeButton(bool isDark, bool isUrdu) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => RaiseDisputeDialog.show(
          context,
          jobId:           widget.job.id!,
          jobTitle:        widget.job.title,
          clientId:        widget.job.clientId,
          clientName:      _clientFullName,
          workerId:        widget.workerId,
          workerName:      widget.workerCategory,
          currentUserId:   widget.workerId,
          currentUserRole: 'worker',
          onDisputeRaised: () => setState(() {}),
        ),
        icon:  const Icon(Icons.flag_outlined,
            color: CColors.error, size: 18),
        label: Text('Raise a Dispute',
            style: TextStyle(
                color:      CColors.error,
                fontWeight: FontWeight.w600,
                fontSize:   isUrdu ? 15 : 13)),
        style: OutlinedButton.styleFrom(
          side:    const BorderSide(color: CColors.error),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius:
              BorderRadius.circular(CSizes.borderRadiusLg)),
        ),
      ),
    );
  }

  // ── Open chat ─────────────────────────────────────────────────────
  void _openChat() {
    if (_acceptedBid == null) return;
    final chatId = _chatService.getChatId(widget.job.id!, widget.workerId);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId:        chatId,
          jobTitle:      widget.job.title,
          otherName:     _clientName,
          currentUserId: widget.workerId,
          otherUserId:   _acceptedBid!.clientId,
          otherRole:     'client',
        ),
      ),
    );
  }
}