// lib/features/worker/screens/worker_job_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
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
import '../../../shared/widgets/job_media_gallery.dart';
import 'worker_live_bidding_screen.dart';

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
  final _amountController = TextEditingController();
  final _messageController = TextEditingController();
  final _bidService = BidService();
  final _jobService = JobService();
  final _chatService = ChatService();
  final _mapService = MapService();
  final _locationService = LocationService();
  final _paymentService = PaymentService();

  bool _isLoading = false;
  bool _hasExistingBid = false;
  BidModel? _acceptedBid;
  String _clientName = 'common.loading'.tr();
  String? _distanceLabel;
  bool _isCancelling = false;
  bool _confirmingCash = false;

  late String _liveJobStatus;
  Map<String, dynamic>? _pendingProgressRequest;

  bool _hasPendingExtras = false;
  double _approvedExtrasTotal = 0.0;

  String? _pendingPaymentId;

  StreamSubscription<DocumentSnapshot>? _jobSub;

  String _clientFullName = '';
  String _workerName = '';

  // ── Start time negotiation ─────────────────────────────────
  bool _acceptClientTime = true;
  DateTime? _workerProposedStartTime;

  // ── Start agreement fields from job stream ─────────────────
  DateTime? _agreedStartTime;
  DateTime? _startAgreementExpiry;
  DateTime? _startAgreementCreatedAt;
  String? _startAgreementStatus;

  @override
  void initState() {
    super.initState();
    _liveJobStatus = widget.job.status;
    _checkExistingBid();
    _loadClientName();
    _loadWorkerName();
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
      final data = snap.data() as Map<String, dynamic>;
      final status = data['status'] as String? ?? _liveJobStatus;
      final request = data['progressRequest'] as Map<String, dynamic>?;
      final rawExtras = data['extraCharges'] as List<dynamic>? ?? [];

      final charges = rawExtras
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final hasPending = charges
          .any((c) => c['status'] == 'pending' && c['requestedBy'] != 'worker');

      final approvedTotal = charges
          .where((c) => c['status'] == 'approved')
          .fold<double>(0, (s, c) => s + ((c['amount'] as num?)?.toDouble() ?? 0));

      final agreed = data['agreedStartTime'] as Timestamp?;
      final expiry = data['startAgreementExpiry'] as Timestamp?;
      final createdAt = data['startAgreementCreatedAt'] as Timestamp?;
      final agreementStatus = data['startAgreementStatus'] as String?;

      setState(() {
        _liveJobStatus = status;
        _pendingProgressRequest = request;
        _hasPendingExtras = hasPending;
        _approvedExtrasTotal = approvedTotal;
        _agreedStartTime = agreed?.toDate();
        _startAgreementExpiry = expiry?.toDate();
        _startAgreementCreatedAt = createdAt?.toDate();
        _startAgreementStatus = agreementStatus;
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
      final hasBid = await _bidService.hasWorkerBidOnJob(widget.workerId, widget.job.id!);
      if (mounted) setState(() => _hasExistingBid = hasBid);

      if (hasBid) {
        final snapshot = await FirebaseFirestore.instance
            .collection('bids')
            .where('jobId', isEqualTo: widget.job.id)
            .where('workerId', isEqualTo: widget.workerId)
            .where('status', isEqualTo: 'accepted')
            .limit(1)
            .get();
        if (snapshot.docs.isNotEmpty && mounted) {
          setState(() {
            _acceptedBid = BidModel.fromSnapshot(
              snapshot.docs.first as DocumentSnapshot<Map<String, dynamic>>,
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
              _clientName = fullName;
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

  Future<void> _loadWorkerName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(widget.workerId)
          .get();
      if (doc.exists) {
        final info = doc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
        final name = info['fullName'] as String? ?? '';
        if (name.isNotEmpty && mounted) setState(() => _workerName = name);
      }
    } catch (_) {}
  }

  Future<void> _loadDistanceToJob() async {
    if (!widget.job.hasLocation) return;
    try {
      final pos = await _locationService.getCurrentPosition();
      final distKm = _locationService.distanceBetweenCoords(
        pos.latitude,
        pos.longitude,
        widget.job.latitude!,
        widget.job.longitude!,
      );
      if (mounted) {
        setState(() => _distanceLabel = _locationService.formatDistance(distKm));
      }
    } catch (_) {}
  }

  Future<void> _cancelJob() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Job?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Are you sure you want to cancel this job? '
              'The client will be notified.'),
          const SizedBox(height: 12),
          TextField(
            controller: reasonController,
            decoration: const InputDecoration(
                labelText: 'Reason (optional)', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: CColors.error),
            child:
            const Text('Cancel Job', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isCancelling = true);
    try {
      await _bidService.cancelJob(
        jobId: widget.job.id!,
        cancelledBy: 'worker',
        reason: reasonController.text.trim().isEmpty
            ? null
            : reasonController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _liveJobStatus = 'cancelled';
          _isCancelling = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Job cancelled.'),
          backgroundColor: CColors.warning,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to cancel: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _confirmCashReceived() async {
    if (_pendingPaymentId == null) return;

    final baseAmount = _acceptedBid?.amount ?? 0;
    final totalAmount = baseAmount + _approvedExtrasTotal;
    final amountText = totalAmount > 0
        ? totalAmount.toStringAsFixed(0)
        : baseAmount.toStringAsFixed(0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Cash Receipt'),
        content: Text(
          'Confirm you have received Rs. $amountText in cash from the client?'
              '${_approvedExtrasTotal > 0 ? '\n(includes Rs. ${_approvedExtrasTotal.toStringAsFixed(0)} in approved extra charges)' : ''}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: CColors.success),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _confirmingCash = true);
    try {
      await _paymentService.confirmCashReceived(
        paymentId: _pendingPaymentId!,
        jobId: widget.job.id!,
      );
      if (mounted) {
        setState(() {
          _confirmingCash = false;
          _pendingPaymentId = null;
          _liveJobStatus = 'completed';
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cash confirmed! Job marked as completed.'),
          backgroundColor: CColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _confirmingCash = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _confirmStartTime() async {
    try {
      await _bidService.confirmStartTime(widget.job.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Start time confirmed! Job is now in progress.'),
          backgroundColor: CColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _placeBid() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('bid.valid_amount_required'.tr()),
        backgroundColor: CColors.warning,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final bid = BidModel(
        jobId: widget.job.id!,
        workerId: widget.workerId,
        clientId: widget.job.clientId,
        amount: amount,
        message: _messageController.text.isNotEmpty ? _messageController.text : null,
        createdAt: Timestamp.now(),
        availableTime: null,
        workerProposedStartTime: widget.job.isUrgent ? null : (_acceptClientTime ? null : _workerProposedStartTime),
      );
      await _bidService.createBid(bid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('bid.bid_placed'.tr()),
          backgroundColor: CColors.success,
          behavior: SnackBarBehavior.floating,
        ));
        widget.onBidPlaced();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => LiveBiddingScreen(
              job: widget.job,
              workerId: widget.workerId,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('bid.place_failed'.tr(args: [e.toString()])),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickWorkerProposedTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _workerProposedStartTime ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _workerProposedStartTime != null
          ? TimeOfDay.fromDateTime(_workerProposedStartTime!)
          : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    final chosen = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (chosen.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please choose a future date and time.'),
        backgroundColor: CColors.warning,
      ));
      return;
    }
    setState(() => _workerProposedStartTime = chosen);
  }

  Color _getStatusColor(String s) {
    switch (s) {
      case 'open': return CColors.success;
      case 'in-progress': return CColors.warning;
      case 'completed': return CColors.info;
      case 'cancelled': return CColors.error;
      default: return CColors.grey;
    }
  }

  String _getStatusText(String s) {
    switch (s) {
      case 'open': return 'job.status_open'.tr();
      case 'in-progress': return 'job.status_in_progress'.tr();
      case 'completed': return 'job.status_completed'.tr();
      case 'cancelled': return 'job.status_cancelled'.tr();
      default: return s;
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
            title: 'job.job_details'.tr(),
            showBackButton: true,
            onBackPressed: () => Navigator.pop(context),
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

                if (_acceptedBid != null &&
                    (_liveJobStatus == 'in-progress' ||
                        _liveJobStatus == 'completed')) ...[
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildExtraChargesCard(isDark, isUrdu),
                ],

                if (_pendingPaymentId != null &&
                    _liveJobStatus == 'in-progress') ...[
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildCashConfirmBanner(isDark, isUrdu),
                ],

                if (_liveJobStatus == 'pending_start_agreement') ...[
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildStartAgreementBanner(isDark, isUrdu),
                ],

                const SizedBox(height: CSizes.spaceBtwSections),
                _buildBidForm(isDark, isUrdu),

                if (_acceptedBid != null && _liveJobStatus == 'completed') ...[
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildCompletedBanner(isDark, isUrdu),
                ],

                if (_acceptedBid != null) ...[
                  const SizedBox(height: CSizes.spaceBtwSections),
                  DisputeStatusBanner(
                    jobId: widget.job.id!,
                    currentUserId: widget.workerId,
                    currentUserRole: 'worker',
                  ),
                ],

                if (_acceptedBid != null &&
                    (_liveJobStatus == 'in-progress' ||
                        _liveJobStatus == 'completed')) ...[
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildRaiseDisputeButton(isDark, isUrdu),
                ],

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

  Widget _buildJobDetailsCard(bool isDark, bool isUrdu) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: isDark ? CColors.darkContainer : CColors.white,
        border: Border.all(
            color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _getStatusColor(_liveJobStatus).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_getStatusText(_liveJobStatus),
                style: TextStyle(
                    color: _getStatusColor(_liveJobStatus),
                    fontWeight: FontWeight.w600,
                    fontSize: isUrdu ? 12 : 10)),
          ),
          if (_distanceLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: CColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.near_me_rounded,
                    size: 12, color: CColors.primary),
                const SizedBox(width: 4),
                Text(_distanceLabel!,
                    style: const TextStyle(
                        color: CColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 10)),
              ]),
            ),
          if (_hasPendingExtras)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: CColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_amber_rounded,
                    size: 12, color: CColors.warning),
                SizedBox(width: 4),
                Text('Extras Pending',
                    style: TextStyle(
                        color: CColors.warning,
                        fontWeight: FontWeight.w600,
                        fontSize: 10)),
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
                color: isDark
                    ? CColors.textWhite.withValues(alpha: 0.8)
                    : CColors.darkerGrey,
                height: 1.5,
                fontSize: isUrdu ? 16 : 14)),

        if (widget.job.hasBudget || widget.job.hasSchedule) ...[
          const SizedBox(height: 12),
          _buildBudgetScheduleRow(isDark, isUrdu),
        ],

        if (widget.job.hasMedia) ...[
          const SizedBox(height: CSizes.spaceBtwItems),
          JobMediaGallery(
            mediaUrls: widget.job.mediaUrls,
            mediaTypes: widget.job.mediaTypes,
            mediaBase64: widget.job.mediaBase64,
          ),
        ],

        const SizedBox(height: 16),

        Wrap(spacing: 16, runSpacing: 8, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.person_outline, size: 16, color: CColors.darkGrey),
            const SizedBox(width: 6),
            Flexible(
                child: Text('${'job.posted_by'.tr()}: $_clientName',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: CColors.darkGrey, fontSize: isUrdu ? 14 : 12),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1)),
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis)),
          ]),
        ],
      ]),
    );
  }

  Widget _buildBudgetScheduleRow(bool isDark, bool isUrdu) {
    final textColor = isDark ? CColors.textWhite.withValues(alpha: 0.8) : CColors.darkerGrey;
    final labelStyle = TextStyle(
      fontSize: isUrdu ? 13 : 11,
      fontWeight: FontWeight.w500,
      color: isDark ? CColors.textWhite.withValues(alpha: 0.5) : CColors.darkGrey,
    );
    final valueStyle = TextStyle(
      fontSize: isUrdu ? 15 : 13,
      fontWeight: FontWeight.w600,
      color: textColor,
    );

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        if (widget.job.hasBudget)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.account_balance_wallet_outlined,
                size: 16, color: CColors.primary),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Budget', style: labelStyle),
                Text(widget.job.budgetDisplay, style: valueStyle),
              ],
            ),
          ]),
        if (widget.job.hasSchedule)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.event_available_rounded,
                size: 16, color: CColors.primary),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Start By', style: labelStyle),
                Text(
                  DateFormat('d MMM yyyy, hh:mm a')
                      .format(widget.job.scheduledAt!.toDate()),
                  style: valueStyle,
                ),
              ],
            ),
          ]),
      ],
    );
  }

  Widget _buildExtraChargesCard(bool isDark, bool isUrdu) {
    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color: isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(
            color: _hasPendingExtras
                ? CColors.warning.withValues(alpha: 0.5)
                : (isDark ? CColors.darkerGrey : CColors.borderPrimary)),
      ),
      child: Row(children: [
        Icon(
          _hasPendingExtras
              ? Icons.warning_amber_rounded
              : Icons.add_circle_outline,
          color: _hasPendingExtras ? CColors.warning : CColors.primary,
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            jobId: widget.job.id!,
            currentRole: 'worker',
          ),
          child: const Text('Manage'),
        ),
      ]),
    );
  }

  Widget _buildCashConfirmBanner(bool isDark, bool isUrdu) {
    final baseAmount = _acceptedBid?.amount ?? 0;
    final totalAmount = baseAmount + _approvedExtrasTotal;

    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color: CColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(color: CColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.payments_outlined, color: CColors.warning, size: 20),
          SizedBox(width: 8),
          Text('Cash Payment Pending',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: CColors.warning,
                  fontSize: 15)),
        ]),
        const SizedBox(height: 6),
        Text(
          _approvedExtrasTotal > 0
              ? 'The client has chosen to pay Rs. ${totalAmount.toStringAsFixed(0)} in cash '
              '(Rs. ${baseAmount.toStringAsFixed(0)} base + '
              'Rs. ${_approvedExtrasTotal.toStringAsFixed(0)} extras). '
              'Once you receive the cash, confirm below to complete the job.'
              : 'The client has chosen to pay in cash. '
              'Once you receive the cash, confirm below to complete the job.',
          style: const TextStyle(fontSize: 13, color: CColors.darkGrey),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _confirmingCash ? null : _confirmCashReceived,
            icon: const Icon(Icons.check_circle_outline),
            label: _confirmingCash
                ? const SizedBox(
                width: 16,
                height: 16,
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

  Widget _buildMiniMap(bool isDark, bool isUrdu) {
    final jobLatLng = LatLng(widget.job.latitude!, widget.job.longitude!);
    return Container(
      height: 200,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          border: Border.all(
              color: isDark ? CColors.darkerGrey : CColors.borderPrimary)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: jobLatLng,
            initialZoom: 15.0,
            interactionOptions:
            const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            _mapService.osmTileLayer(),
            _mapService.selectedPinLayer(jobLatLng),
          ],
        ),
        Positioned(
          bottom: 10,
          right: 10,
          child: ElevatedButton.icon(
            onPressed: () async {
              try {
                final pos = await _locationService.getCurrentPosition();
                await _mapService.openDirections(
                  from: _locationService
                      .latLngToGeoPoint(LatLng(pos.latitude, pos.longitude)),
                  to: widget.job.location!,
                  destinationLabel: widget.job.title,
                );
              } catch (e) {
                await _mapService.openDirections(
                  from: widget.job.location!,
                  to: widget.job.location!,
                  destinationLabel: widget.job.title,
                );
              }
            },
            icon: const Icon(Icons.directions_rounded, size: 16),
            label: Text('job.get_directions'.tr(),
                style: TextStyle(fontSize: isUrdu ? 14 : 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 3,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildStartAgreementBanner(bool isDark, bool isUrdu) {
    if (_agreedStartTime == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final canConfirm = _startAgreementCreatedAt != null &&
        now.isAfter(_startAgreementCreatedAt!.add(const Duration(seconds: 60)));
    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color: CColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(color: CColors.info.withValues(alpha: 0.5)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.event_available_rounded, color: CColors.info),
          const SizedBox(width: 8),
          Expanded(child: Text('Start time agreement pending',
              style: const TextStyle(fontWeight: FontWeight.bold, color: CColors.info))),
        ]),
        const SizedBox(height: 8),
        Text('Agreed start: ${DateFormat('d MMM yyyy, hh:mm a').format(_agreedStartTime!)}',
            style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        if (!canConfirm)
          Text('You can confirm the start time after the 60-second client grace period.',
              style: TextStyle(fontSize: 12, color: CColors.darkGrey))
        else
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _confirmStartTime,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Confirm Start Time'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: CColors.success, foregroundColor: Colors.white),
            ),
          ),
      ]),
    );
  }

  Widget _buildBidForm(bool isDark, bool isUrdu) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LiveBiddingScreen(
                  job: widget.job,
                  workerId: widget.workerId,
                ),
              ),
            ),
            icon: const Icon(Icons.list_alt_rounded, size: 20, color: CColors.primary),
            label: Text(
              'View Bids',
              style: TextStyle(
                fontSize: isUrdu ? 16 : 14,
                fontWeight: FontWeight.w600,
                color: CColors.primary,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: CColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
              ),
            ),
          ),
        ),
        const SizedBox(height: CSizes.spaceBtwItems),

        if (_acceptedBid != null)
          _buildAcceptedPanel(isDark, isUrdu)
        else if (_hasExistingBid)
          _buildAlreadyPlacedMessage(isDark, isUrdu)
        else if (widget.job.status != 'open')
            _buildJobClosedMessage(isDark, isUrdu)
          else
            _buildPlaceBidForm(isDark, isUrdu),
      ],
    );
  }

  // ── Client start time info (professional, bold, prominent) ─────────
  Widget _buildClientStartTimeInfo(bool isDark, bool isUrdu) {
    if (widget.job.isUrgent) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [CColors.warning.withValues(alpha: 0.15), CColors.warning.withValues(alpha: 0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CColors.warning, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.flash_on, color: CColors.warning, size: 24),
              const SizedBox(width: 12),
              Text(
                'URGENT / ASAP JOB',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: CColors.warning,
                  fontSize: isUrdu ? 18 : 16,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              'This job must be started immediately. The client expects work to begin as soon as you are accepted.',
              style: TextStyle(fontSize: isUrdu ? 13 : 12, color: CColors.darkGrey),
            ),
            const SizedBox(height: 4),
            Text(
              'Posted: ${DateFormat('d MMM yyyy, hh:mm a').format(widget.job.createdAt.toDate())}',
              style: TextStyle(fontSize: 11, color: CColors.darkGrey),
            ),
          ],
        ),
      );
    }

    if (widget.job.scheduledAt == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: CColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, size: 20, color: CColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No specific start time requested. You may propose your own start time.',
              style: TextStyle(fontSize: isUrdu ? 13 : 12, fontWeight: FontWeight.w500),
            ),
          ),
        ]),
      );
    }

    final clientTime = widget.job.scheduledAt!.toDate();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [CColors.primary.withValues(alpha: 0.1), Colors.transparent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CColors.primary, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_available_rounded, color: CColors.primary, size: 22),
              const SizedBox(width: 12),
              Text(
                'Client\'s Preferred Start Time',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isUrdu ? 16 : 14,
                  color: CColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            DateFormat('EEEE, d MMMM yyyy').format(clientTime),
            style: TextStyle(
              fontSize: isUrdu ? 16 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            'at ${DateFormat('hh:mm a').format(clientTime)}',
            style: TextStyle(
              fontSize: isUrdu ? 14 : 12,
              fontWeight: FontWeight.w500,
              color: CColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Worker start time choice (only show if not urgent) ─────────────
  Widget _buildWorkerStartTimeChoice(bool isDark, bool isUrdu) {
    if (widget.job.isUrgent) {
      return const SizedBox.shrink(); // No time choice for urgent jobs
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your start time proposal',
            style: TextStyle(fontSize: isUrdu ? 14 : 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: RadioListTile<bool>(
                title: Text('Accept client\'s time', style: TextStyle(fontSize: isUrdu ? 13 : 12)),
                value: true,
                groupValue: _acceptClientTime,
                onChanged: (val) {
                  setState(() {
                    _acceptClientTime = true;
                    _workerProposedStartTime = null;
                  });
                },
                activeColor: CColors.primary,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
            Expanded(
              child: RadioListTile<bool>(
                title: Text('Propose different time', style: TextStyle(fontSize: isUrdu ? 13 : 12)),
                value: false,
                groupValue: _acceptClientTime,
                onChanged: (val) {
                  setState(() {
                    _acceptClientTime = false;
                    if (_workerProposedStartTime == null) _pickWorkerProposedTime();
                  });
                },
                activeColor: CColors.primary,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
          ],
        ),
        if (!_acceptClientTime && _workerProposedStartTime != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: CColors.primary),
              ),
              child: Row(children: [
                Icon(Icons.access_time, color: CColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your proposed start: ${DateFormat('d MMM yyyy, hh:mm a').format(_workerProposedStartTime!)}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: _pickWorkerProposedTime,
                ),
              ]),
            ),
          ),
        if (!_acceptClientTime && _workerProposedStartTime == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              onPressed: _pickWorkerProposedTime,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text('Tap to pick your proposed start time', style: TextStyle(fontSize: isUrdu ? 13 : 12)),
              style: TextButton.styleFrom(foregroundColor: CColors.primary),
            ),
          ),
      ],
    );
  }

  Widget _buildAlreadyPlacedMessage(bool isDark, bool isUrdu) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: CColors.success.withValues(alpha: 0.1),
        border: Border.all(color: CColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline, size: 40, color: CColors.success),
          const SizedBox(height: 12),
          Text(
            'bid.already_placed'.tr(),
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              fontWeight: FontWeight.w700,
              color: CColors.success,
              fontSize: isUrdu ? 20 : 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your bid is live. Tap "View Bids" above to see all bids.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: isDark ? CColors.textWhite.withValues(alpha: 0.8) : CColors.darkerGrey,
              fontSize: isUrdu ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobClosedMessage(bool isDark, bool isUrdu) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: CColors.warning.withValues(alpha: 0.1),
        border: Border.all(color: CColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline, size: 40, color: CColors.warning),
          const SizedBox(height: 12),
          Text(
            'job.job_closed'.tr(),
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              fontWeight: FontWeight.w700,
              color: CColors.warning,
              fontSize: isUrdu ? 20 : 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'job.no_longer_accepting'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: isDark ? CColors.textWhite.withValues(alpha: 0.8) : CColors.darkerGrey,
              fontSize: isUrdu ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceBidForm(bool isDark, bool isUrdu) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'bid.place_your_bid'.tr(),
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: isUrdu ? 22 : 20,
          ),
        ),
        const SizedBox(height: CSizes.spaceBtwItems),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openPreBidChat,
            icon: const Icon(Icons.chat_rounded, size: 20, color: Colors.white),
            label: Text(
              'Ask Client Before Bidding',
              style: TextStyle(
                fontSize: isUrdu ? 16 : 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
              ),
              elevation: 3,
              shadowColor: CColors.primary.withValues(alpha: 0.4),
            ),
          ),
        ),

        const SizedBox(height: CSizes.spaceBtwItems),

        _buildClientStartTimeInfo(isDark, isUrdu),
        const SizedBox(height: CSizes.spaceBtwInputFields),

        _buildWorkerStartTimeChoice(isDark, isUrdu),
        const SizedBox(height: CSizes.spaceBtwInputFields),

        Container(
          padding: const EdgeInsets.all(CSizes.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
            color: isDark ? CColors.darkContainer : CColors.white,
            border: Border.all(
              color: isDark ? CColors.darkerGrey : CColors.borderPrimary,
            ),
          ),
          child: Column(
            children: [
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'bid.amount_label'.tr(),
                  hintText: 'bid.amount_hint'.tr(),
                  prefixText: 'Rs. ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                    borderSide: BorderSide(
                      color: isDark ? CColors.darkerGrey : CColors.borderPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: CSizes.spaceBtwInputFields),

              TextField(
                controller: _messageController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'bid.message_label'.tr(),
                  hintText: 'bid.message_hint'.tr(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                    borderSide: BorderSide(
                      color: isDark ? CColors.darkerGrey : CColors.borderPrimary,
                    ),
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
                      borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
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

  Widget _buildCompletedBanner(bool isDark, bool isUrdu) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CColors.info.withValues(alpha: 0.12),
            CColors.success.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: CColors.info.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
              color: Color(0x260288D1), shape: BoxShape.circle),
          child:
          const Icon(Icons.verified_rounded, size: 36, color: CColors.info),
        ),
        const SizedBox(height: 14),
        Text('Job Completed!',
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
                fontWeight: FontWeight.bold,
                color: CColors.info,
                fontSize: isUrdu ? 22 : 20)),
        const SizedBox(height: 8),
        Text('The client has approved the completion. Great work!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: isDark
                    ? CColors.textWhite.withValues(alpha: 0.75)
                    : CColors.darkerGrey,
                fontSize: isUrdu ? 15 : 13)),
      ]),
    );
  }

  Widget _buildAcceptedPanel(bool isDark, bool isUrdu) {
    final baseAmount = _acceptedBid!.amount;
    final totalAmount = baseAmount + _approvedExtrasTotal;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CColors.success.withValues(alpha: 0.12),
            CColors.primary.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: CColors.success.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
              color: Color(0x2643A047), shape: BoxShape.circle),
          child: const Icon(Icons.emoji_events_rounded,
              size: 40, color: CColors.success),
        ),
        const SizedBox(height: 16),
        Text('bid.bid_accepted_congrats'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
                fontWeight: FontWeight.w800,
                color: CColors.success,
                fontSize: isUrdu ? 22 : 20)),
        const SizedBox(height: 8),
        Text('bid.bid_accepted_message'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: isDark
                    ? CColors.textWhite.withValues(alpha: 0.75)
                    : CColors.darkerGrey,
                fontSize: isUrdu ? 15 : 13,
                height: 1.5)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: CColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: CColors.primary.withValues(alpha: 0.3)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Rs. ${totalAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: CColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            if (_approvedExtrasTotal > 0)
              Text(
                'Base Rs. ${baseAmount.toStringAsFixed(0)}'
                    ' + Extras Rs. ${_approvedExtrasTotal.toStringAsFixed(0)}',
                style: const TextStyle(color: CColors.darkGrey, fontSize: 10),
              ),
          ]),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openChat,
            icon: const Icon(Icons.chat_rounded, size: 20),
            label: Text('chat.open_chat'.tr(),
                style: TextStyle(
                    fontSize: isUrdu ? 17 : 15, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
              elevation: 3,
              shadowColor: CColors.primary.withValues(alpha: 0.4),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildCancelButton(bool isDark, bool isUrdu) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isCancelling ? null : _cancelJob,
        icon: _isCancelling
            ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                color: CColors.warning, strokeWidth: 2))
            : const Icon(Icons.cancel_outlined, color: CColors.warning),
        label: Text('Cancel Job',
            style: TextStyle(
                color: CColors.warning,
                fontWeight: FontWeight.w600,
                fontSize: isUrdu ? 15 : 13)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: CColors.warning),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
        ),
      ),
    );
  }

  Widget _buildRaiseDisputeButton(bool isDark, bool isUrdu) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => RaiseDisputeDialog.show(
          context,
          jobId: widget.job.id!,
          jobTitle: widget.job.title,
          clientId: widget.job.clientId,
          clientName: _clientFullName,
          workerId: widget.workerId,
          workerName: widget.workerCategory,
          currentUserId: widget.workerId,
          currentUserRole: 'worker',
          onDisputeRaised: () => setState(() {}),
        ),
        icon: const Icon(Icons.flag_outlined, color: CColors.error, size: 18),
        label: Text('Raise a Dispute',
            style: TextStyle(
                color: CColors.error,
                fontWeight: FontWeight.w600,
                fontSize: isUrdu ? 15 : 13)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: CColors.error),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
        ),
      ),
    );
  }

  Future<void> _openPreBidChat() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      if (_workerName.isEmpty) await _loadWorkerName();
      final chatId = await _chatService.createOrGetChat(
        jobId: widget.job.id!,
        jobTitle: widget.job.title,
        clientId: widget.job.clientId,
        workerId: widget.workerId,
        workerName: _workerName.isNotEmpty ? _workerName : widget.workerCategory,
        clientName: _clientFullName.isNotEmpty ? _clientFullName : _clientName,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            jobTitle: widget.job.title,
            otherName: _clientName,
            currentUserId: widget.workerId,
            otherUserId: widget.job.clientId,
            otherRole: 'client',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open chat: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openChat() async {
    if (_acceptedBid == null || !mounted) return;
    setState(() => _isLoading = true);
    try {
      if (_workerName.isEmpty) await _loadWorkerName();
      final chatId = await _chatService.createOrGetChat(
        jobId: widget.job.id!,
        jobTitle: widget.job.title,
        clientId: _acceptedBid!.clientId,
        workerId: widget.workerId,
        workerName: _workerName.isNotEmpty ? _workerName : widget.workerCategory,
        clientName: _clientFullName.isNotEmpty ? _clientFullName : _clientName,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            jobTitle: widget.job.title,
            otherName: _clientName,
            currentUserId: widget.workerId,
            otherUserId: _acceptedBid!.clientId,
            otherRole: 'client',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open chat: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}