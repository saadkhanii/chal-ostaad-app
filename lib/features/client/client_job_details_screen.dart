// lib/features/client/client_job_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'package:intl/intl.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/bid_model.dart';
import '../client/post_job_screen.dart' show PostJobScreen;
import '../../core/models/job_model.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/job_service.dart';
import '../../core/services/map_service.dart';
import '../../shared/widgets/common_header.dart';
import '../chat/chat_screen.dart';
import '../../core/services/review_service.dart';
import '../review/submit_review_dialog.dart';
import '../review/worker_bid_profile_screen.dart';
import '../dispute/raise_dispute_dialog.dart';
import '../dispute/dispute_status_banner.dart';
import '../payment/payment_screen.dart';
import '../payment/extra_charges_sheet.dart';
import '../../core/services/payment_service.dart';
import '../../shared/widgets/job_media_gallery.dart';
import 'client_live_bidding_screen.dart';

class ClientJobDetailsScreen extends ConsumerStatefulWidget {
  final JobModel job;
  const ClientJobDetailsScreen({super.key, required this.job});

  @override
  ConsumerState<ClientJobDetailsScreen> createState() =>
      _ClientJobDetailsScreenState();
}

class _ClientJobDetailsScreenState
    extends ConsumerState<ClientJobDetailsScreen> {
  final _mapService     = MapService();
  final _bidService     = BidService();
  final _jobService     = JobService();
  final _chatService    = ChatService();
  final _paymentService = PaymentService();

  bool    _jobPaid         = false;
  late String _jobStatus;
  String _clientId         = '';
  bool   _isDeleting       = false;
  bool   _isCancelling     = false;

  Map<String, dynamic>? _pendingProgressRequest;
  bool _isRespondingToProgress = false;

  String? _acceptedWorkerId;
  bool    _reviewSubmitted  = false;
  final ReviewService _reviewService = ReviewService();
  String _workerName = '';

  // Extra charges notification
  bool _hasPendingExtras = false;
  double _approvedExtrasTotal = 0.0;

  // ── Start agreement (10‑minute window, 60s grace) ──────────────────
  DateTime? _agreedStartTime;
  DateTime? _startAgreementExpiry;
  DateTime? _startAgreementCreatedAt;
  String? _startAgreementStatus;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  StreamSubscription<DocumentSnapshot>? _jobSub;

  @override
  void initState() {
    super.initState();
    _jobStatus = widget.job.status.trim().toLowerCase();
    _loadClientId();
    _loadAcceptedWorkerId();
    _subscribeToJob();
    _checkPaymentStatus();
  }

  Future<void> _checkPaymentStatus() async {
    if (widget.job.id == null) return;
    final paid = await _paymentService.isJobPaid(widget.job.id!);
    if (mounted) setState(() => _jobPaid = paid);
  }

  void _subscribeToJob() {
    _jobSub = FirebaseFirestore.instance
        .collection('jobs')
        .doc(widget.job.id)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final status = (data['status'] as String?)?.trim().toLowerCase() ?? _jobStatus;
      final request = data['progressRequest'] as Map<String, dynamic>?;
      final reviewed = data['reviewSubmitted'] as bool? ?? false;
      final rawExtras = data['extraCharges'] as List<dynamic>? ?? [];

      final charges = rawExtras
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final hasPending = charges
          .any((c) => c['status'] == 'pending' && c['requestedBy'] != 'client');

      final approvedTotal = charges
          .where((c) => c['status'] == 'approved')
          .fold<double>(0, (s, c) => s + ((c['amount'] as num?)?.toDouble() ?? 0));

      // Start agreement fields
      final agreedTime = data['agreedStartTime'] as Timestamp?;
      final expiry = data['startAgreementExpiry'] as Timestamp?;
      final createdAt = data['startAgreementCreatedAt'] as Timestamp?;
      final agreementStatus = data['startAgreementStatus'] as String?;

      setState(() {
        _jobStatus = status;
        _pendingProgressRequest = request;
        _reviewSubmitted = reviewed;
        _hasPendingExtras = hasPending;
        _approvedExtrasTotal = approvedTotal;
        _agreedStartTime = agreedTime?.toDate();
        _startAgreementExpiry = expiry?.toDate();
        _startAgreementCreatedAt = createdAt?.toDate();
        _startAgreementStatus = agreementStatus;
      });

      _updateStartAgreementTimer();
    });
  }

  void _updateStartAgreementTimer() {
    _countdownTimer?.cancel();
    if (_jobStatus == 'pending_start_agreement' && _startAgreementExpiry != null) {
      final now = DateTime.now();
      if (now.isAfter(_startAgreementExpiry!)) {
        _autoCancelStartAgreement();
      } else {
        final remaining = _startAgreementExpiry!.difference(now).inSeconds;
        setState(() => _remainingSeconds = remaining);
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          final newRemaining = _startAgreementExpiry!.difference(DateTime.now()).inSeconds;
          if (newRemaining <= 0) {
            timer.cancel();
            _autoCancelStartAgreement();
          } else {
            setState(() => _remainingSeconds = newRemaining);
          }
        });
      }
    } else {
      setState(() => _remainingSeconds = 0);
    }
  }

  Future<void> _autoCancelStartAgreement() async {
    try {
      await _bidService.cancelStartAgreement(widget.job.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Start time agreement expired. Job reverted to open.'),
          backgroundColor: CColors.warning,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('Auto-cancel error: $e');
    }
  }

  Future<void> _cancelStartAgreement() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Job?'),
        content: const Text(
          'If you cancel now, the job will be reverted to open and all bids will become pending again. You can accept a different bid.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: CColors.error),
            child: const Text('Cancel & Revert', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _bidService.cancelStartAgreement(widget.job.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Job reverted to open. You can now accept another bid.'),
          backgroundColor: CColors.warning,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to cancel: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  void dispose() {
    _jobSub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadClientId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _clientId = prefs.getString('user_uid') ?? '');
  }

  Future<void> _loadAcceptedWorkerId() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bids')
          .where('jobId',  isEqualTo: widget.job.id)
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty && mounted) {
        final wId = snapshot.docs.first.data()['workerId'] as String?;
        setState(() => _acceptedWorkerId = wId);
        if (wId != null) {
          final name = await _getWorkerName(wId);
          if (mounted) setState(() => _workerName = name);
        }
      }
    } catch (_) {}
  }

  // ── Cancel job (client side, for non-agreement states) ─────────────
  Future<void> _cancelJob() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Job?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Are you sure you want to cancel this job? '
                    'This action cannot be undone.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
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
        cancelledBy: 'client',
        reason:      reasonController.text.trim().isEmpty
            ? null
            : reasonController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _jobStatus    = 'cancelled';
          _isCancelling = false;
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

  // ── Delete job (client only, only when open) ────────────────────────
  Future<void> _deleteJob() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('job.delete_job'.tr()),
        content: Text('job.delete_job_confirm'.tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: CColors.error),
            child: Text('common.delete'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isDeleting = true);
    try {
      await _jobService.deleteJob(widget.job.id!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Failed to delete job: $e'),
          backgroundColor: CColors.error,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Open edit screen (only while job is open) ──────────────────────
  void _openEditScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostJobScreen(
          existingJob: widget.job,
          onJobPosted: () => Navigator.pop(context),
        ),
      ),
    );
  }

  // ── Respond to worker's progress/completion request ─────────────────
  Future<void> _respondToProgressRequest(bool accepted) async {
    if (_acceptedWorkerId == null) return;
    setState(() => _isRespondingToProgress = true);
    try {
      await _jobService.respondToProgressRequest(
        jobId:    widget.job.id!,
        jobTitle: widget.job.title,
        workerId: _acceptedWorkerId!,
        accepted: accepted,
      );
      if (mounted) {
        setState(() {
          _jobStatus              = accepted ? 'completed' : 'in-progress';
          _pendingProgressRequest = null;
          _isRespondingToProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accepted
              ? 'Job marked as completed!'
              : 'Progress request rejected. Job stays in progress.'),
          backgroundColor: accepted ? CColors.success : CColors.warning,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRespondingToProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Error: $e'),
          backgroundColor: CColors.error,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Build ───────────────────────────────────────────────────────────
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
              title:          'job.job_details'.tr(),
              showBackButton: true,
              onBackPressed:  () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Job info card ──────────────────────────────
                  _buildJobInfoCard(isDark, isUrdu),

                  // ── Status lifecycle banner ────────────────────
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildStatusBanner(isDark, isUrdu),

                  // ── Pending progress request ───────────────────
                  if (_pendingProgressRequest != null &&
                      _pendingProgressRequest!['status'] == 'pending') ...[
                    const SizedBox(height: CSizes.spaceBtwItems),
                    _buildProgressRequestBanner(isDark, isUrdu),
                  ],

                  // ── Extra charges ──────────────────────────────
                  if (_jobStatus == 'in-progress' ||
                      _jobStatus == 'completed') ...[
                    const SizedBox(height: CSizes.spaceBtwItems),
                    _buildExtraChargesCard(isDark, isUrdu),
                  ],

                  // ── Start agreement banner (10‑minute window) ───
                  if (_jobStatus == 'pending_start_agreement' && _agreedStartTime != null) ...[
                    const SizedBox(height: CSizes.spaceBtwItems),
                    _buildStartAgreementBanner(isDark, isUrdu),
                  ],

                  // ── Map ────────────────────────────────────────
                  if (widget.job.hasLocation) ...[
                    const SizedBox(height: CSizes.spaceBtwItems),
                    _buildMiniMap(isDark),
                  ],

                  // ── Live Bidding button ─────────────────────────
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildLiveBiddingButton(isDark, isUrdu),

                  // ── Dispute banner ─────────────────────────────
                  if (_acceptedWorkerId != null) ...[
                    const SizedBox(height: CSizes.spaceBtwSections),
                    DisputeStatusBanner(
                      jobId:           widget.job.id!,
                      currentUserId:   _clientId,
                      currentUserRole: 'client',
                    ),
                  ],

                  // ── Raise dispute ──────────────────────────────
                  if (_acceptedWorkerId != null &&
                      (_jobStatus == 'in-progress' ||
                          _jobStatus == 'completed')) ...[
                    const SizedBox(height: CSizes.spaceBtwItems),
                    _buildRaiseDisputeButton(isDark, isUrdu),
                  ],

                  // ── Action buttons row ─────────────────────────
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildActionButtons(isDark, isUrdu),

                  const SizedBox(height: CSizes.spaceBtwSections * 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Job info card (with urgent badge) ──────────────────────────────
  Widget _buildJobInfoCard(bool isDark, bool isUrdu) {
    final statusColor = _statusColor(_jobStatus);
    final statusText  = _statusText(_jobStatus);

    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        border: Border.all(
            color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, children: [
            _badge(statusText, statusColor),
            if (widget.job.isUrgent)
              _badge('URGENT / ASAP', CColors.error, icon: Icons.flash_on, small: false),
            if (_jobPaid)
              _badge('Paid', CColors.success,
                  icon: Icons.check_circle_outline, small: true),
            if (_hasPendingExtras)
              _badge('Extra Charges Pending', CColors.warning,
                  icon: Icons.warning_amber_rounded, small: true),
          ]),
          const SizedBox(height: 16),
          Text(widget.job.title,
              style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize:   isUrdu ? 24 : 22)),
          const SizedBox(height: 8),
          Text(widget.job.description,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color:  isDark
                      ? CColors.textWhite.withOpacity(0.8)
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
              mediaUrls:   widget.job.mediaUrls,
              mediaTypes:  widget.job.mediaTypes,
              mediaBase64: widget.job.mediaBase64,
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Icon(Icons.access_time_outlined,
                size: 16, color: CColors.darkGrey),
            const SizedBox(width: 6),
            Text(timeago.format(widget.job.createdAt.toDate()),
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: CColors.darkGrey)),
            if (widget.job.hasLocation) ...[
              const SizedBox(width: 16),
              Icon(Icons.location_on_outlined,
                  size: 16, color: CColors.darkGrey),
              const SizedBox(width: 4),
              Flexible(
                  child: Text(widget.job.displayLocation,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: CColors.darkGrey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _buildBudgetScheduleRow(bool isDark, bool isUrdu) {
    final textColor = isDark
        ? CColors.textWhite.withOpacity(0.8)
        : CColors.darkerGrey;
    final labelStyle = TextStyle(
      fontSize:   isUrdu ? 13 : 11,
      fontWeight: FontWeight.w500,
      color:      isDark ? CColors.textWhite.withOpacity(0.5) : CColors.darkGrey,
    );
    final valueStyle = TextStyle(
      fontSize:   isUrdu ? 15 : 13,
      fontWeight: FontWeight.w600,
      color:      textColor,
    );

    return Wrap(
      spacing:   16,
      runSpacing: 8,
      children: [
        if (widget.job.hasBudget)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.account_balance_wallet_outlined,
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
            Icon(Icons.event_available_rounded,
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

  // ── Status lifecycle banner (supports pending_start_agreement) ──────
  Widget _buildStatusBanner(bool isDark, bool isUrdu) {
    final steps  = ['open', 'in-progress', 'completed'];
    final labels = ['Open', 'In Progress', 'Completed'];
    int idx = steps.indexOf(_jobStatus);
    if (_jobStatus == 'pending_start_agreement') idx = 0;

    if (_jobStatus == 'cancelled' || _jobStatus == 'deleted') {
      return Container(
        padding:    const EdgeInsets.all(CSizes.md),
        decoration: BoxDecoration(
          color:        CColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
          border:       Border.all(color: CColors.error.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.cancel_outlined, color: CColors.error),
          const SizedBox(width: 10),
          Text(
            _jobStatus == 'deleted' ? 'Job Deleted' : 'Job Cancelled',
            style: const TextStyle(
                color: CColors.error, fontWeight: FontWeight.bold),
          ),
        ]),
      );
    }

    return Container(
      padding:    const EdgeInsets.symmetric(
          horizontal: CSizes.md, vertical: CSizes.sm),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(
            color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final leftDone = (i ~/ 2) < idx;
            return Expanded(
              child: Container(
                height: 2,
                color:  leftDone ? CColors.primary : Colors.grey.shade300,
              ),
            );
          }
          final stepIdx = i ~/ 2;
          final done    = stepIdx <= idx;
          final active  = stepIdx == idx;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width:      28,
              height:     28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? CColors.primary : Colors.grey.shade200,
                border: active
                    ? Border.all(color: CColors.primary, width: 2)
                    : null,
              ),
              child: Icon(
                done ? Icons.check : Icons.circle,
                size:  done ? 16 : 8,
                color: done ? Colors.white : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 4),
            Text(labels[stepIdx],
                style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                    active ? FontWeight.bold : FontWeight.normal,
                    color: done ? CColors.primary : Colors.grey)),
          ]);
        }),
      ),
    );
  }

  // ── Progress request banner (unchanged) ─────────────────────────────
  Widget _buildProgressRequestBanner(bool isDark, bool isUrdu) {
    final note = _pendingProgressRequest?['note'] as String?;
    return Container(
      padding:    const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color:        CColors.info.withOpacity(0.08),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border:       Border.all(color: CColors.info.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.task_alt_rounded, color: CColors.info, size: 20),
            SizedBox(width: 8),
            Text('Worker Requests Completion',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color:      CColors.info,
                    fontSize:   15)),
          ]),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('"$note"',
                style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    color: CColors.darkGrey,
                    fontSize: 13)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isRespondingToProgress
                    ? null
                    : () => _respondToProgressRequest(false),
                style: OutlinedButton.styleFrom(
                    foregroundColor: CColors.error,
                    side: const BorderSide(color: CColors.error)),
                child: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isRespondingToProgress
                    ? null
                    : () => _respondToProgressRequest(true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: CColors.success,
                    foregroundColor: Colors.white),
                child: _isRespondingToProgress
                    ? const SizedBox(
                    width:  16,
                    height: 16,
                    child:  CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                    : const Text('Approve & Complete'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Extra charges card (unchanged) ──────────────────────────────────
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _hasPendingExtras
                    ? 'Extra charge awaiting your approval'
                    : 'Extra Charges',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize:   14,
                    color: _hasPendingExtras
                        ? CColors.warning
                        : (isDark
                        ? CColors.textWhite
                        : CColors.textPrimary)),
              ),
              const Text(
                'View, approve or propose additional charges',
                style: TextStyle(fontSize: 12, color: CColors.darkGrey),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => ExtraChargesSheet.show(
            context,
            jobId:       widget.job.id!,
            currentRole: 'client',
          ),
          child: const Text('Manage'),
        ),
      ]),
    );
  }

  // ── Start agreement banner (10‑minute window with 60s grace) ────────
  Widget _buildStartAgreementBanner(bool isDark, bool isUrdu) {
    if (_agreedStartTime == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final isGracePeriod = _startAgreementCreatedAt != null &&
        now.isBefore(_startAgreementCreatedAt!.add(const Duration(seconds: 60)));
    final minutes = (_remainingSeconds / 60).floor();
    final seconds = _remainingSeconds % 60;
    final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color: CColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(color: CColors.warning.withOpacity(0.5)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.timer_outlined, color: CColors.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Start time agreement in progress',
            style: const TextStyle(fontWeight: FontWeight.bold, color: CColors.warning),
          )),
        ]),
        const SizedBox(height: 8),
        Text(
          'Agreed start: ${DateFormat('d MMM yyyy, hh:mm a').format(_agreedStartTime!)}',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          'Time remaining: $timeStr',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: CColors.warning),
        ),
        const SizedBox(height: 8),
        if (isGracePeriod)
          const Text(
            'Grace period: you can cancel (worker cannot confirm yet)',
            style: TextStyle(fontSize: 12, color: CColors.darkGrey),
          ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _cancelStartAgreement,
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Cancel & Revert to Open'),
          style: ElevatedButton.styleFrom(
            backgroundColor: CColors.error,
            foregroundColor: Colors.white,
          ),
        ),
      ]),
    );
  }

  // ── Mini map (unchanged) ────────────────────────────────────────────
  Widget _buildMiniMap(bool isDark) {
    final ll = LatLng(widget.job.latitude!, widget.job.longitude!);
    return Container(
      height:      180,
      decoration:  BoxDecoration(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          border: Border.all(
              color: isDark ? CColors.darkerGrey : CColors.borderPrimary)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: ll,
            initialZoom:   15,
            interactionOptions:
            const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            _mapService.osmTileLayer(),
            _mapService.selectedPinLayer(ll),
          ],
        ),
        Positioned(
          bottom: 10, right: 10,
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
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not open maps: $e')));
                }
              }
            },
            icon:  const Icon(Icons.directions_rounded, size: 16),
            label: Text('job.directions'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Live Bidding button (navigates to client live bidding screen) ───
  Widget _buildLiveBiddingButton(bool isDark, bool isUrdu) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ClientLiveBiddingScreen(
                job: widget.job,
                clientId: _clientId,
              ),
            ),
          );
        },
        icon: const Icon(Icons.gavel_rounded, size: 18),
        label: Text(
          'View Live Bidding',
          style: TextStyle(fontSize: isUrdu ? 16 : 14),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: CColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
          ),
        ),
      ),
    );
  }

  // ── Action buttons (edit / cancel / delete) ──────────────────────────
  Widget _buildActionButtons(bool isDark, bool isUrdu) {
    final canEdit   = _jobStatus == 'open';
    final canDelete = _jobStatus == 'open';
    final canCancel = _jobStatus == 'open' || _jobStatus == 'in-progress' || _jobStatus == 'pending_start_agreement';

    if (!canEdit && !canDelete && !canCancel) return const SizedBox.shrink();

    return Column(
      children: [
        if (canEdit) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openEditScreen,
              icon:  Icon(Icons.edit_outlined, color: CColors.primary),
              label: Text('Edit Job',
                  style: TextStyle(color: CColors.primary)),
              style: OutlinedButton.styleFrom(
                side:    BorderSide(color: CColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape:   RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(CSizes.borderRadiusLg)),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(children: [
          if (canDelete)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isDeleting ? null : _deleteJob,
                icon:  const Icon(Icons.delete_outline, color: CColors.error),
                label: _isDeleting
                    ? const SizedBox(
                    width:  16,
                    height: 16,
                    child:  CircularProgressIndicator(
                        color: CColors.error, strokeWidth: 2))
                    : const Text('Delete Job',
                    style: TextStyle(color: CColors.error)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: CColors.error),
                  padding:
                  const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          CSizes.borderRadiusLg)),
                ),
              ),
            ),
          if (canDelete && canCancel) const SizedBox(width: 12),
          if (canCancel)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isCancelling ? null : _cancelJob,
                icon:  const Icon(Icons.cancel_outlined,
                    color: CColors.warning),
                label: _isCancelling
                    ? const SizedBox(
                    width:  16,
                    height: 16,
                    child:  CircularProgressIndicator(
                        color: CColors.warning, strokeWidth: 2))
                    : const Text('Cancel Job',
                    style: TextStyle(color: CColors.warning)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: CColors.warning),
                  padding:
                  const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          CSizes.borderRadiusLg)),
                ),
              ),
            ),
        ]),
      ],
    );
  }

  // ── Raise dispute button (unchanged) ────────────────────────────────
  Widget _buildRaiseDisputeButton(bool isDark, bool isUrdu) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => RaiseDisputeDialog.show(
          context,
          jobId:           widget.job.id!,
          jobTitle:        widget.job.title,
          clientId:        _clientId,
          clientName:      '',
          workerId:        _acceptedWorkerId ?? '',
          workerName:      _workerName,
          currentUserId:   _clientId,
          currentUserRole: 'client',
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
          shape:   RoundedRectangleBorder(
              borderRadius:
              BorderRadius.circular(CSizes.borderRadiusLg)),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────
  Widget _badge(String label, Color color,
      {IconData? icon, bool small = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: small ? 12 : 14),
          const SizedBox(width: 4),
        ],
        Text(label,
            style: TextStyle(
                color:      color,
                fontWeight: FontWeight.w600,
                fontSize:   small ? 10 : 11)),
      ]),
    );
  }

  Color  _statusColor(String s) {
    switch (s) {
      case 'open': return CColors.success;
      case 'pending_start_agreement': return CColors.success;
      case 'in-progress': return CColors.warning;
      case 'completed':   return CColors.info;
      case 'cancelled':
      case 'deleted':     return CColors.error;
      default:            return CColors.grey;
    }
  }

  String _statusText(String s) {
    switch (s) {
      case 'open':        return 'Open';
      case 'pending_start_agreement': return 'Agreement Pending';
      case 'in-progress': return 'In Progress';
      case 'completed':   return 'Completed';
      case 'cancelled':   return 'Cancelled';
      case 'deleted':     return 'Deleted';
      default:            return s;
    }
  }

  Future<void> _openReviewDialog() async {
    if (_acceptedWorkerId == null) return;
    final workerName = await _getWorkerName(_acceptedWorkerId!);
    if (!mounted) return;
    await SubmitReviewDialog.show(
      context,
      workerName: workerName,
      onSubmit: (rating, comment) async {
        try {
          await _reviewService.submitReview(
            jobId:      widget.job.id!,
            clientId:   _clientId,
            clientName: await _getClientName(_clientId),
            workerId:   _acceptedWorkerId!,
            rating:     rating,
            comment:    comment,
          );
          if (mounted) {
            setState(() => _reviewSubmitted = true);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:         Text('Review submitted!'),
              backgroundColor: CColors.success,
              behavior:        SnackBarBehavior.floating,
            ));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:         Text('Failed: $e'),
              backgroundColor: CColors.error,
              behavior:        SnackBarBehavior.floating,
            ));
          }
        }
      },
    );
  }

  void _openPaymentScreen(BidModel bid) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          jobId:    widget.job.id!,
          jobTitle: widget.job.title,
          clientId: _clientId,
          workerId: bid.workerId,
          amount:   bid.amount,
        ),
      ),
    ).then((_) => _checkPaymentStatus());
  }

  void _openChat(BidModel bid) async {
    final chatId     = _chatService.getChatId(widget.job.id!, bid.workerId);
    final workerName = await _getWorkerName(bid.workerId);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId:        chatId,
          jobTitle:      widget.job.title,
          otherName:     workerName,
          currentUserId: _clientId,
          otherUserId:   bid.workerId,
          otherRole:     'worker',
        ),
      ),
    );
  }

  Future<String> _getWorkerName(String id) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers').doc(id).get();
      final info = doc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
      return info['name'] ?? info['fullName'] ?? 'Worker';
    } catch (_) {
      return 'Worker';
    }
  }

  Future<String> _getClientName(String id) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('clients').doc(id).get();
      final info = doc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
      return info['fullName'] ?? info['name'] ?? 'Client';
    } catch (_) {
      return 'Client';
    }
  }
}