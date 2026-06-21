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
import '../../shared/widgets/app_card.dart';
import '../client/post_job_screen.dart' show PostJobScreen;
import '../../core/models/job_model.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/job_service.dart';
import '../../core/services/map_service.dart';

import '../../shared/widgets/common_header.dart';
import '../../shared/widgets/confirmation_dialog.dart';
import '../chat/chat_screen.dart';
import '../../core/services/review_service.dart';
import '../review/submit_review_dialog.dart';
import '../dispute/raise_dispute_dialog.dart';
import '../dispute/dispute_status_banner.dart';
import '../payment/payment_screen.dart';
import '../payment/extra_charges_sheet.dart';
import '../../core/services/payment_service.dart';
import '../../shared/widgets/job_media_gallery.dart';
import 'client_live_bidding_screen.dart';
import '../maps/live_location_screen.dart';

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
  final _chatService = ChatService();
  final _paymentService = PaymentService();

  bool _jobPaid = false;
  late String _jobStatus;
  String _clientId = '';
  bool _isDeleting = false;
  bool _isCancelling = false;

  Map<String, dynamic>? _pendingProgressRequest;
  bool _isRespondingToProgress = false;

  String? _acceptedWorkerId;
  bool _reviewSubmitted = false;
  final ReviewService _reviewService = ReviewService();
  String _workerName = '';

  bool _hasPendingExtras = false;
  double _approvedExtrasTotal = 0.0;

  // Grace period timer
  Timer? _graceTimer;
  int _graceRemainingSeconds = 0;
  DateTime? _graceExpiry;

  // Worker start deadline (urgent)
  Timer? _workerStartTimer;
  int _workerStartRemainingSeconds = 0;
  DateTime? _workerStartDeadline;

  // Scheduled countdown
  Timer? _scheduledCountdownTimer;
  int _scheduledRemainingSeconds = 0;
  DateTime? _scheduledStartTime;

  bool _workerReachedLocation = false;
  bool _hasAnyBid = false; // for detecting bidding phase
  BidModel? _acceptedBidForPayment; // ✅ tracked for payment button

  // --- Time proposal from worker ---
  Map<String, dynamic>? _pendingTimeProposal; // from job doc
  bool _isRespondingToTimeProposal = false;

  StreamSubscription<DocumentSnapshot>? _jobSub;
  StreamSubscription<QuerySnapshot>? _bidsSub;

  @override
  void initState() {
    super.initState();
    _jobStatus = widget.job.status.trim().toLowerCase();
    _loadClientId();
    _loadAcceptedWorkerId();
    _subscribeToJob();
    _subscribeToBids();
    _checkPaymentStatus();
  }

  Future<void> _checkPaymentStatus() async {
    if (widget.job.id == null) return;
    final paid = await _paymentService.isJobPaid(widget.job.id!);
    if (mounted) setState(() => _jobPaid = paid);
  }

  void _subscribeToBids() {
    if (widget.job.id == null) return;
    _bidsSub = FirebaseFirestore.instance
        .collection('bids')
        .where('jobId', isEqualTo: widget.job.id)
        .snapshots()
        .listen((snapshot) {
      final hasAny = snapshot.docs.isNotEmpty;
      final acceptedDocs = snapshot.docs.where((d) => d.data()['status'] == 'accepted').toList();
      final acceptedBid = acceptedDocs.isNotEmpty
          ? BidModel.fromSnapshot(acceptedDocs.first as DocumentSnapshot<Map<String, dynamic>>)
          : null;
      if (mounted) {
        setState(() {
          _hasAnyBid = hasAny;
          _acceptedBidForPayment = acceptedBid;
        });
      }
    });
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

      final graceExpiry = (data['gracePeriodExpiry'] as Timestamp?)?.toDate();
      final workerDeadline = (data['workerStartDeadline'] as Timestamp?)?.toDate();
      final scheduledStart = (data['scheduledAt'] as Timestamp?)?.toDate();
      final reachedLocation = data['workerReachedLocation'] as bool? ?? false;
      final paymentStatus = data['paymentStatus'] as String? ?? '';
      final isPaid = paymentStatus == 'paid';

      // Time proposal
      final timeProposal = data['pendingTimeProposal'] as Map<String, dynamic>?;

      setState(() {
        _jobStatus = status;
        _pendingProgressRequest = request;
        _reviewSubmitted = reviewed;
        _hasPendingExtras = hasPending;
        _approvedExtrasTotal = approvedTotal;
        _workerReachedLocation = reachedLocation;
        _pendingTimeProposal = timeProposal;
        if (isPaid) _jobPaid = true;

        if (status == 'grace_period' && graceExpiry != null) {
          _graceExpiry = graceExpiry;
          _updateGraceTimer();
        } else {
          _graceTimer?.cancel();
          _graceRemainingSeconds = 0;
          _graceExpiry = null;
        }

        if ((status == 'active' || status == 'scheduled') && workerDeadline != null) {
          _workerStartDeadline = workerDeadline;
          _updateWorkerStartTimer();
        } else {
          _workerStartTimer?.cancel();
          _workerStartRemainingSeconds = 0;
          _workerStartDeadline = null;
        }

        if (status == 'scheduled' && scheduledStart != null && !widget.job.isUrgent) {
          _scheduledStartTime = scheduledStart;
          _updateScheduledCountdown();
        } else {
          _scheduledCountdownTimer?.cancel();
          _scheduledRemainingSeconds = 0;
          _scheduledStartTime = null;
        }
      });
    });
  }

  void _updateGraceTimer() {
    if (_graceExpiry == null) return;
    _graceTimer?.cancel();
    final now = DateTime.now();
    if (now.isAfter(_graceExpiry!)) {
      _graceRemainingSeconds = 0;
      _bidService.finaliseAcceptance(widget.job.id!);
    } else {
      final remaining = _graceExpiry!.difference(now).inSeconds;
      setState(() => _graceRemainingSeconds = remaining);
      _graceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final newRemaining = _graceExpiry!.difference(DateTime.now()).inSeconds;
        if (newRemaining <= 0) {
          timer.cancel();
          setState(() => _graceRemainingSeconds = 0);
          _bidService.finaliseAcceptance(widget.job.id!);
        } else {
          setState(() => _graceRemainingSeconds = newRemaining);
        }
      });
    }
  }

  void _updateWorkerStartTimer() {
    if (_workerStartDeadline == null) return;
    _workerStartTimer?.cancel();
    final now = DateTime.now();
    if (now.isAfter(_workerStartDeadline!)) {
      _workerStartRemainingSeconds = 0;
    } else {
      final remaining = _workerStartDeadline!.difference(now).inSeconds;
      setState(() => _workerStartRemainingSeconds = remaining);
      _workerStartTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final newRemaining = _workerStartDeadline!.difference(DateTime.now()).inSeconds;
        if (newRemaining <= 0) {
          timer.cancel();
          setState(() => _workerStartRemainingSeconds = 0);
        } else {
          setState(() => _workerStartRemainingSeconds = newRemaining);
        }
      });
    }
  }

  void _updateScheduledCountdown() {
    if (_scheduledStartTime == null) return;
    _scheduledCountdownTimer?.cancel();
    final now = DateTime.now();
    if (now.isAfter(_scheduledStartTime!)) {
      _scheduledRemainingSeconds = 0;
    } else {
      final remaining = _scheduledStartTime!.difference(now).inSeconds;
      setState(() => _scheduledRemainingSeconds = remaining);
      _scheduledCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final newRemaining = _scheduledStartTime!.difference(DateTime.now()).inSeconds;
        if (newRemaining <= 0) {
          timer.cancel();
          setState(() => _scheduledRemainingSeconds = 0);
        } else {
          setState(() => _scheduledRemainingSeconds = newRemaining);
        }
      });
    }
  }

  // Helper to format duration with days
  String _formatDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (days > 0) {
      return '${days}d : ${hours.toString().padLeft(2, '0')}h : ${minutes.toString().padLeft(2, '0')}m : ${seconds.toString().padLeft(2, '0')}s';
    } else if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _instantLockBid() async {
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Confirm Acceptance',
      content: 'Are you sure you want to accept this bid immediately without waiting for the grace period? This action cannot be undone.',
      confirmText: 'Confirm & Lock',
      cancelText: 'common.cancel'.tr(),
      isDestructive: false,
      onConfirm: () => Navigator.pop(context, true),
    );
    if (confirmed != true) return;
    try {
      await _bidService.finaliseAcceptance(widget.job.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bid locked in! Job is now active.'),
          backgroundColor: CColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: CColors.error,
        ));
      }
    }
  }

  Future<void> _cancelDuringGrace() async {
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Cancel Job?',
      content: 'You have 60 seconds to cancel the accepted bid. Are you sure?',
      confirmText: 'Yes, Cancel',
      cancelText: 'common.cancel'.tr(),
      isDestructive: true,
      onConfirm: () => Navigator.pop(context, true),
    );
    if (confirmed != true) return;
    try {
      await _bidService.cancelBidDuringGrace(widget.job.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Job cancelled and reopened for bids.'),
          backgroundColor: CColors.warning,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: CColors.error));
    }
  }

  Future<void> _markWorkerArrived() async {
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Worker Arrived?',
      content: 'Confirm that the worker has reached the job location. The job will move to In Progress.',
      confirmText: 'Yes, Arrived',
      cancelText: 'Not Yet',
      isDestructive: false,
      onConfirm: () => Navigator.pop(context, true),
    );
    if (confirmed != true || !mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.job.id)
          .update({
        'workerReachedLocation': true,
        'status': 'in-progress',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _workerReachedLocation = true;
          _jobStatus = 'in-progress';
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Worker marked as arrived. Job is now In Progress!'),
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

  @override
  void dispose() {
    _jobSub?.cancel();
    _bidsSub?.cancel();
    _graceTimer?.cancel();
    _workerStartTimer?.cancel();
    _scheduledCountdownTimer?.cancel();
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
          .where('jobId', isEqualTo: widget.job.id)
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

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(milliseconds: 500));
  }

  // ── Cancel job (client side, for non-grace states) ─────────────
  Future<void> _cancelJob() async {
    final reasonController = TextEditingController();

    final reasonEntered = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: IntrinsicHeight(
          child: AppCard(
            showTopBorder: false,
            margin: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
            headerGradient: LinearGradient(
              colors: [CColors.error, CColors.error.withValues(alpha: 0.8)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            headerPadding: const EdgeInsets.symmetric(horizontal: CSizes.md, vertical: 10),
            headerTitle: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Cancel Job?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            headerTrailing: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              onPressed: () => Navigator.pop(ctx, false),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            bodyPadding: const EdgeInsets.all(CSizes.md),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to cancel this job? This action cannot be undone.',
                  style: TextStyle(fontSize: 13, color: Theme.of(ctx).brightness == Brightness.dark ? CColors.lightGrey : CColors.textPrimary, height: 1.4),
                ),
                const SizedBox(height: CSizes.md),
                TextField(
                  controller: reasonController,
                  decoration: InputDecoration(
                    labelText: 'Reason (optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: CSizes.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(60, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        foregroundColor: CColors.error,
                        side: const BorderSide(color: CColors.error, width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
                      ),
                      child: Text('common.cancel'.tr(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(width: CSizes.xs),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CColors.error,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(70, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
                      ),
                      child: const Text('Cancel Job', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (reasonEntered != true || !mounted) return;
    setState(() => _isCancelling = true);
    try {
      await _bidService.cancelJob(
        jobId: widget.job.id!,
        cancelledBy: 'client',
        reason: reasonController.text.trim().isEmpty ? null : reasonController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _jobStatus = 'cancelled';
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

  // ── Delete job (client only, only when open) ────────────────────────
  Future<void> _deleteJob() async {
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'job.delete_job'.tr(),
      content: 'job.delete_job_confirm'.tr(),
      confirmText: 'common.delete'.tr(),
      cancelText: 'common.cancel'.tr(),
      isDestructive: true,
      onConfirm: () => Navigator.pop(context, true),
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
          content: Text('Failed to delete job: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

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

  Future<void> _respondToProgressRequest(bool accepted) async {
    if (_acceptedWorkerId == null) return;
    setState(() => _isRespondingToProgress = true);
    try {
      await _jobService.respondToProgressRequest(
        jobId: widget.job.id!,
        jobTitle: widget.job.title,
        workerId: _acceptedWorkerId!,
        accepted: accepted,
      );
      if (mounted) {
        setState(() {
          _jobStatus = accepted ? 'completed' : 'in-progress';
          _pendingProgressRequest = null;
          _isRespondingToProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accepted ? 'Job marked as completed!' : 'Progress request rejected. Job stays in progress.'),
          backgroundColor: accepted ? CColors.success : CColors.warning,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRespondingToProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _viewLiveLocation() {
    if (_acceptedWorkerId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkerLiveLocationScreen(
          jobId: widget.job.id!,
          workerId: _acceptedWorkerId!,
          workerName: _workerName,
        ),
      ),
    );
  }

  // ── Time proposal from worker ──────────────────────────────────────────
  Widget _buildWorkerTimeProposalBanner(bool isDark, bool isUrdu) {
    if (_pendingTimeProposal == null) return const SizedBox.shrink();
    final proposedBy = _pendingTimeProposal!['proposedBy'] as String?;
    final status = _pendingTimeProposal!['status'] as String?;
    if (proposedBy != 'worker' || status != 'pending') return const SizedBox.shrink();

    final proposedTime = (_pendingTimeProposal!['proposedTime'] as Timestamp?)?.toDate();
    if (proposedTime == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color: CColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(color: CColors.info.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available_rounded, color: CColors.info, size: 20),
              const SizedBox(width: 8),
              Text(
                'Worker proposes a new start time',
                style: const TextStyle(fontWeight: FontWeight.bold, color: CColors.info, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Proposed: ${DateFormat('d MMM yyyy, hh:mm a').format(proposedTime)}',
            style: TextStyle(fontSize: isUrdu ? 14 : 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isRespondingToTimeProposal ? null : () => _respondToWorkerTimeProposal(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CColors.error,
                    side: const BorderSide(color: CColors.error),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isRespondingToTimeProposal ? null : () => _respondToWorkerTimeProposal(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CColors.success,
                    foregroundColor: Colors.white,
                  ),
                  child: _isRespondingToTimeProposal
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _respondToWorkerTimeProposal(bool accept) async {
    setState(() => _isRespondingToTimeProposal = true);
    try {
      if (accept) {
        // The method expects: (String jobId, String clientId, DateTime newTime)
        await _bidService.acceptWorkerTimeProposal(
          widget.job.id!,
          _clientId,
          (_pendingTimeProposal!['proposedTime'] as Timestamp).toDate(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('New start time accepted. Schedule updated.'),
            backgroundColor: CColors.success,
            behavior: SnackBarBehavior.floating,
          ));
        }
      } else {
        // The method expects: (String jobId, String clientId)
        await _bidService.rejectWorkerTimeProposal(
          widget.job.id!,
          _clientId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Proposal rejected. Worker will be notified.'),
            backgroundColor: CColors.warning,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
      // Clear local proposal after response
      if (mounted) {
        setState(() {
          _pendingTimeProposal = null;
          _isRespondingToTimeProposal = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRespondingToTimeProposal = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Rich Status Card ──────────────────────────────────────────────
  List<Map<String, String>> _getStatusSteps() {
    if (widget.job.isUrgent) {
      return [
        {'key': 'open', 'label': 'Open'},
        {'key': 'bidding', 'label': 'Bidding'},
        {'key': 'grace_period', 'label': 'Grace Period'},
        {'key': 'waiting', 'label': 'Waiting'},
        {'key': 'started', 'label': 'Started'},
        {'key': 'in_progress', 'label': 'In Progress'},
        {'key': 'completed', 'label': 'Completed'},
      ];
    } else {
      return [
        {'key': 'open', 'label': 'Open'},
        {'key': 'bidding', 'label': 'Bidding'},
        {'key': 'grace_period', 'label': 'Grace Period'},
        {'key': 'scheduled', 'label': 'Scheduled'},
        {'key': 'waiting', 'label': 'Waiting'},
        {'key': 'started', 'label': 'Started'},
        {'key': 'in_progress', 'label': 'In Progress'},
        {'key': 'completed', 'label': 'Completed'},
      ];
    }
  }

  String _mapStatusToStepKey(String firestoreStatus) {
    switch (firestoreStatus) {
      case 'open':
        return _hasAnyBid ? 'bidding' : 'open';
      case 'grace_period':
        return 'grace_period';
      case 'active':
        return 'waiting';
      case 'scheduled':
        return 'scheduled';
      case 'in-progress':
        return _workerReachedLocation ? 'in_progress' : 'started';
      case 'completed':
        return 'completed';
      default:
        return 'bidding';
    }
  }

  int _getCurrentStepIndex() {
    final steps = _getStatusSteps();
    String currentKey = _mapStatusToStepKey(_jobStatus);
    for (int i = 0; i < steps.length; i++) {
      if (steps[i]['key'] == currentKey) return i;
    }
    return 0;
  }

  Widget _buildStatusCard(bool isDark, bool isUrdu) {
    final steps = _getStatusSteps();
    final currentIndex = _getCurrentStepIndex();

    return AppCard(
      margin: EdgeInsets.zero,
      showTopBorder: true,
      bodyPadding: const EdgeInsets.all(CSizes.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Job Progress',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isUrdu ? 16 : 14,
              color: isDark ? CColors.textWhite : CColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(steps.length, (i) {
                final step = steps[i];
                final isCompleted = i < currentIndex;
                final isActive = i == currentIndex;
                final isLast = i == steps.length - 1;
                return Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCompleted
                                ? CColors.success
                                : (isActive
                                ? CColors.primary
                                : (isDark ? CColors.darkerGrey : Colors.grey.shade300)),
                            border: isActive ? Border.all(color: CColors.primary, width: 2) : null,
                          ),
                          child: Icon(
                            isCompleted ? Icons.check : Icons.circle,
                            size: isCompleted ? 18 : 12,
                            color: (isCompleted || isActive)
                                ? Colors.white
                                : (isDark ? CColors.textWhite : CColors.darkGrey),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          step['label']!,
                          style: TextStyle(
                            fontSize: isUrdu ? 11 : 10,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            color: isActive
                                ? CColors.primary
                                : (isCompleted
                                ? CColors.success
                                : (isDark ? CColors.textWhite.withValues(alpha: 0.6) : CColors.darkGrey)),
                          ),
                        ),
                      ],
                    ),
                    if (!isLast)
                      Container(
                        width: 40,
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: i < currentIndex
                            ? CColors.success
                            : (isDark ? CColors.darkerGrey : Colors.grey.shade300),
                      ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          _buildStepAdditionalInfo(currentIndex, isDark, isUrdu),
        ],
      ),
    );
  }

  Widget _buildStepAdditionalInfo(int stepIndex, bool isDark, bool isUrdu) {
    final steps = _getStatusSteps();
    final stepKey = steps[stepIndex]['key'];
    switch (stepKey) {
      case 'bidding':
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: CColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.gavel_rounded, size: 16, color: CColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bids are coming in. You can accept one at any time.',
                  style: TextStyle(fontSize: isUrdu ? 13 : 12),
                ),
              ),
            ],
          ),
        );
      case 'grace_period':
        final minutes = (_graceRemainingSeconds / 60).floor();
        final seconds = _graceRemainingSeconds % 60;
        final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: CColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.timer_outlined, size: 16, color: CColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Grace period: $timeStr remaining (see options below)',
                  style: TextStyle(fontSize: isUrdu ? 13 : 12),
                ),
              ),
            ],
          ),
        );
      case 'scheduled':
        final duration = Duration(seconds: _scheduledRemainingSeconds);
        final timeStr = _formatDuration(duration);
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: CColors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.event_available_rounded, size: 16, color: CColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Job starts in $timeStr',
                  style: TextStyle(fontSize: isUrdu ? 13 : 12),
                ),
              ),
            ],
          ),
        );
      case 'waiting':
        final minutes = (_workerStartRemainingSeconds / 60).floor();
        final seconds = _workerStartRemainingSeconds % 60;
        final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: CColors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.hourglass_empty, size: 16, color: CColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Waiting for worker to start. Time left: $timeStr',
                  style: TextStyle(fontSize: isUrdu ? 13 : 12),
                ),
              ),
            ],
          ),
        );
      case 'started':
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: CColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.directions_car_rounded, size: 16, color: CColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Worker is on the way. Mark as arrived once they reach the location.',
                  style: TextStyle(fontSize: isUrdu ? 13 : 12),
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Job Info Card with gradient header ──────────────────────────
  LinearGradient _getHeaderGradient() {
    if (widget.job.isUrgent) {
      return LinearGradient(
        colors: [CColors.primary, CColors.primary.withValues(alpha: 0.75)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );
    } else if (widget.job.hasSchedule) {
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

  Widget _buildJobInfoCard(bool isDark, bool isUrdu) {
    final statusColor = _statusColor(_jobStatus);
    final statusText = _statusText(_jobStatus);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.cardRadiusLg)),
      clipBehavior: Clip.antiAlias,
      color: isDark ? CColors.darkContainer : CColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: CSizes.md, vertical: 12),
            decoration: BoxDecoration(gradient: _getHeaderGradient()),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.job.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
          Padding(
            padding: const EdgeInsets.all(CSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 8, children: [
                  if (widget.job.isUrgent) _badge('URGENT / ASAP', CColors.error, icon: Icons.flash_on),
                  if (_jobPaid) _badge('Paid', CColors.success, icon: Icons.check_circle_outline, small: true),
                  if (_hasPendingExtras) _badge('Extra Charges Pending', CColors.warning, icon: Icons.warning_amber_rounded, small: true),
                ]),
                const SizedBox(height: 16),
                Text(
                  widget.job.description,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: isDark ? CColors.textWhite.withValues(alpha: 0.8) : CColors.darkerGrey,
                    height: 1.5,
                    fontSize: isUrdu ? 16 : 14,
                  ),
                ),
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
                Row(children: [
                  Icon(Icons.access_time_outlined, size: 16, color: CColors.darkGrey),
                  const SizedBox(width: 6),
                  Text(timeago.format(widget.job.createdAt.toDate()), style: Theme.of(context).textTheme.bodySmall!.copyWith(color: CColors.darkGrey)),
                  if (widget.job.hasLocation) ...[
                    const SizedBox(width: 16),
                    Icon(Icons.location_on_outlined, size: 16, color: CColors.darkGrey),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        widget.job.displayLocation,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(color: CColors.darkGrey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
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
            Icon(Icons.account_balance_wallet_outlined, size: 16, color: CColors.primary),
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
            Icon(Icons.event_available_rounded, size: 16, color: CColors.primary),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Start By', style: labelStyle),
                Text(
                  DateFormat('d MMM yyyy, hh:mm a').format(widget.job.scheduledAt!.toDate()),
                  style: valueStyle,
                ),
              ],
            ),
          ]),
      ],
    );
  }

  // ── Standalone Grace Period Banner (with buttons) ───────────────
  Widget _buildGracePeriodBanner(bool isDark, bool isUrdu) {
    final minutes = (_graceRemainingSeconds / 60).floor();
    final seconds = _graceRemainingSeconds % 60;
    final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color: CColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(color: CColors.warning.withValues(alpha: 0.5)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.timer_outlined, color: CColors.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Grace period – you can cancel within 60 seconds',
            style: const TextStyle(fontWeight: FontWeight.bold, color: CColors.warning),
          )),
        ]),
        const SizedBox(height: 8),
        Text('Time remaining: $timeStr', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: CColors.warning)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _instantLockBid,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Lock Bid'),
              style: ElevatedButton.styleFrom(backgroundColor: CColors.success, foregroundColor: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _cancelDuringGrace,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel'),
              style: ElevatedButton.styleFrom(backgroundColor: CColors.error, foregroundColor: Colors.white),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildWorkerStartDeadlineBanner(bool isDark, bool isUrdu) {
    final minutes = (_workerStartRemainingSeconds / 60).floor();
    final seconds = _workerStartRemainingSeconds % 60;
    final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color: CColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(color: CColors.info.withValues(alpha: 0.5)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.hourglass_empty, color: CColors.info),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Waiting for worker to start the job',
            style: const TextStyle(fontWeight: FontWeight.bold, color: CColors.info),
          )),
        ]),
        const SizedBox(height: 8),
        Text('Worker has $timeStr to start', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: CColors.info)),
        const SizedBox(height: 8),
        Text(
          'If worker does not start within this time, the job will be reopened as urgent and the worker will be banned.',
          style: TextStyle(fontSize: 12, color: CColors.darkGrey),
        ),
      ]),
    );
  }

  Widget _buildScheduledCountdownBanner(bool isDark, bool isUrdu) {
    final duration = Duration(seconds: _scheduledRemainingSeconds);
    final timeStr = _formatDuration(duration);
    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color: CColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(color: CColors.primary.withValues(alpha: 0.5)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.event_available_rounded, color: CColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Job starts at scheduled time',
            style: const TextStyle(fontWeight: FontWeight.bold, color: CColors.primary),
          )),
        ]),
        const SizedBox(height: 8),
        Text(
          _scheduledStartTime != null ? DateFormat('d MMM yyyy, hh:mm a').format(_scheduledStartTime!) : 'Time not set',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text('Time until start: $timeStr', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: CColors.primary)),
        const SizedBox(height: 8),
        Text(
          'Worker can start the job exactly at the scheduled time.',
          style: TextStyle(fontSize: 12, color: CColors.darkGrey),
        ),
      ]),
    );
  }

  Widget _buildProgressRequestBanner(bool isDark, bool isUrdu) {
    final note = _pendingProgressRequest?['note'] as String?;
    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color: CColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(color: CColors.info.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.task_alt_rounded, color: CColors.info, size: 20),
            SizedBox(width: 8),
            Text('Worker Requests Completion', style: TextStyle(fontWeight: FontWeight.bold, color: CColors.info, fontSize: 15)),
          ]),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('"$note"', style: const TextStyle(fontStyle: FontStyle.italic, color: CColors.darkGrey, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isRespondingToProgress ? null : () => _respondToProgressRequest(false),
                style: OutlinedButton.styleFrom(foregroundColor: CColors.error, side: const BorderSide(color: CColors.error)),
                child: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isRespondingToProgress ? null : () => _respondToProgressRequest(true),
                style: ElevatedButton.styleFrom(backgroundColor: CColors.success, foregroundColor: Colors.white),
                child: _isRespondingToProgress
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Approve & Complete'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildExtraChargesButton(bool isDark, bool isUrdu) {
    return SizedBox(
      width: double.infinity,
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('jobs')
            .doc(widget.job.id)
            .snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() as Map<String, dynamic>?;
          final raw = data?['extraCharges'] as List<dynamic>? ?? [];
          final pendingCount = raw
              .where((e) => (e as Map)['status'] == 'pending' && (e as Map)['requestedBy'] == 'worker')
              .length;
          return OutlinedButton.icon(
            onPressed: () => ExtraChargesSheet.show(
              context,
              jobId: widget.job.id!,
              currentRole: 'client',
            ),
            icon: Badge(
              label: Text('$pendingCount'),
              isLabelVisible: pendingCount > 0,
              backgroundColor: CColors.warning,
              textColor: Colors.white,
              child: const Icon(Icons.add_circle_outline, size: 20, color: CColors.primary),
            ),
            label: Text(
              'Extra Charges${pendingCount > 0 ? ' ($pendingCount pending)' : ''}',
              style: TextStyle(fontSize: isUrdu ? 16 : 14, fontWeight: FontWeight.w500),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: CColors.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPendingChargeTile(Map<String, dynamic> charge, bool isDark, bool isUrdu) {
    final id = charge['id'] as String? ?? '';
    final amount = (charge['amount'] as num?)?.toDouble() ?? 0;
    final desc = charge['description'] as String? ?? '';
    final requestedBy = charge['requestedBy'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rs. ${amount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: CColors.primary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: CColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(
                    color: CColors.warning,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: TextStyle(
              fontSize: isUrdu ? 14 : 13,
              color: isDark ? CColors.textWhite.withValues(alpha: 0.8) : CColors.darkerGrey,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _respondToExtraCharge(id, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CColors.error,
                    side: const BorderSide(color: CColors.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: Text(
                    'Reject',
                    style: TextStyle(fontSize: isUrdu ? 14 : 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _respondToExtraCharge(id, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: Text(
                    'Approve',
                    style: TextStyle(fontSize: isUrdu ? 14 : 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _respondToExtraCharge(String chargeId, bool approved) async {
    try {
      await _paymentService.respondToExtraCharge(
        jobId: widget.job.id!,
        chargeId: chargeId,
        approved: approved,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approved ? 'Extra charge approved!' : 'Extra charge rejected.'),
          backgroundColor: approved ? CColors.success : CColors.error,
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

  Widget _buildMiniMap(bool isDark) {
    final ll = LatLng(widget.job.latitude!, widget.job.longitude!);
    LinearGradient headerGradient;
    if (widget.job.isUrgent) {
      headerGradient = LinearGradient(colors: [CColors.primary, CColors.primary.withValues(alpha: 0.75)], begin: Alignment.centerLeft, end: Alignment.centerRight);
    } else if (widget.job.hasSchedule) {
      headerGradient = LinearGradient(colors: [CColors.secondary, CColors.secondary.withValues(alpha: 0.75)], begin: Alignment.centerLeft, end: Alignment.centerRight);
    } else {
      headerGradient = LinearGradient(colors: [Colors.grey.shade700, Colors.grey.shade600], begin: Alignment.centerLeft, end: Alignment.centerRight);
    }
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.cardRadiusLg)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: CSizes.md, vertical: 12),
            decoration: BoxDecoration(gradient: headerGradient),
            child: Row(children: [Icon(Icons.map_rounded, size: 20, color: Colors.white), const SizedBox(width: 8), const Text('Job Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white))]),
          ),
          SizedBox(
            height: 200,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(initialCenter: ll, initialZoom: 15, interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag)),
                  children: [_mapService.osmTileLayer(), _mapService.selectedPinLayer(ll)],
                ),
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await _mapService.openDirections(from: widget.job.location!, to: widget.job.location!, destinationLabel: widget.job.title);
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open maps: $e')));
                      }
                    },
                    icon: const Icon(Icons.directions_rounded, size: 16),
                    label: Text('job.directions'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveBiddingButton(bool isDark, bool isUrdu) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ClientLiveBiddingScreen(job: widget.job, clientId: _clientId)),
          );
        },
        icon: const Icon(Icons.gavel_rounded, size: 18),
        label: Text('View Live Bidding', style: TextStyle(fontSize: isUrdu ? 16 : 14)),
        style: ElevatedButton.styleFrom(
          backgroundColor: CColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
        ),
      ),
    );
  }

  Widget _buildLiveLocationButton(bool isDark, bool isUrdu) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _viewLiveLocation,
        icon: const Icon(Icons.location_on_rounded, size: 18, color: CColors.primary),
        label: Text('View Worker Live Location', style: TextStyle(fontSize: isUrdu ? 16 : 14, color: CColors.primary)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: CColors.primary),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
        ),
      ),
    );
  }

  // NEW: Worker Arrived button — only shows when job is active/scheduled and not yet arrived
  Widget _buildWorkerArrivedButton(bool isDark, bool isUrdu) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _markWorkerArrived,
        icon: const Icon(Icons.where_to_vote_rounded, size: 18),
        label: Text(
          'Worker Has Arrived',
          style: TextStyle(fontSize: isUrdu ? 16 : 14, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: CColors.success,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
          elevation: 2,
        ),
      ),
    );
  }

  // Pay button — shows when job is in-progress and not yet paid
  Widget _buildPaymentButton(bool isDark, bool isUrdu) {
    final acceptedBid = _acceptedBidForPayment;
    if (acceptedBid == null) return const SizedBox.shrink();

    final baseAmount = acceptedBid.amount;
    final totalAmount = baseAmount + _approvedExtrasTotal; // ✅ includes approved extras

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(color: CColors.primary.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: CColors.primary.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(CSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payment_rounded, color: CColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Payment Due',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isUrdu ? 16 : 14,
                    color: isDark ? CColors.textWhite : CColors.textPrimary,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Rs. ${totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: CColors.primary,
                    ),
                  ),
                  if (_approvedExtrasTotal > 0)
                    Text(
                      'Base: Rs. ${baseAmount.toStringAsFixed(0)} + Extras: Rs. ${_approvedExtrasTotal.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 10, color: CColors.darkGrey),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openPaymentScreen(acceptedBid),
              icon: const Icon(Icons.credit_card_rounded, size: 18),
              label: Text(
                'Pay Now — Rs. ${totalAmount.toStringAsFixed(0)}',
                style: TextStyle(fontSize: isUrdu ? 16 : 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: CColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Mark complete button — shows when in-progress and job is paid
  Widget _buildMarkCompleteButton(bool isDark, bool isUrdu) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isRespondingToProgress ? null : () => _markJobComplete(),
        icon: _isRespondingToProgress
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.check_circle_rounded, size: 18),
        label: Text(
          'Mark Job as Complete',
          style: TextStyle(fontSize: isUrdu ? 16 : 14, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: CColors.info,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
          elevation: 2,
        ),
      ),
    );
  }

  Future<void> _markJobComplete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark Job as Complete?'),
        content: const Text('Confirm the job has been completed successfully. This will notify the worker.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not Yet')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: CColors.info),
            child: const Text('Yes, Complete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isRespondingToProgress = true);
    try {
      await FirebaseFirestore.instance.collection('jobs').doc(widget.job.id).update({
        'status': 'completed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _jobStatus = 'completed';
          _isRespondingToProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Job marked as completed!'),
          backgroundColor: CColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRespondingToProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Widget _buildActionButtons(bool isDark, bool isUrdu) {
    final canEdit = _jobStatus == 'open';
    final canDelete = _jobStatus == 'open';
    final canCancel = _jobStatus == 'open' || _jobStatus == 'in-progress';
    if (!canEdit && !canDelete && !canCancel) return const SizedBox.shrink();
    return Column(
      children: [
        if (canEdit) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openEditScreen,
              icon: Icon(Icons.edit_outlined, color: CColors.primary),
              label: Text('Edit Job', style: TextStyle(color: CColors.primary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: CColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
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
                icon: const Icon(Icons.delete_outline, color: CColors.error),
                label: _isDeleting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: CColors.error, strokeWidth: 2))
                    : const Text('Delete Job', style: TextStyle(color: CColors.error)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: CColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
                ),
              ),
            ),
          if (canDelete && canCancel) const SizedBox(width: 12),
          if (canCancel)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isCancelling ? null : _cancelJob,
                icon: const Icon(Icons.cancel_outlined, color: CColors.warning),
                label: _isCancelling
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: CColors.warning, strokeWidth: 2))
                    : const Text('Cancel Job', style: TextStyle(color: CColors.warning)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: CColors.warning),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
                ),
              ),
            ),
        ]),
      ],
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
          clientId: _clientId,
          clientName: '',
          workerId: _acceptedWorkerId ?? '',
          workerName: _workerName,
          currentUserId: _clientId,
          currentUserRole: 'client',
          onDisputeRaised: () => setState(() {}),
        ),
        icon: const Icon(Icons.flag_outlined, color: CColors.error, size: 18),
        label: Text('Raise a Dispute', style: TextStyle(color: CColors.error, fontWeight: FontWeight.w600, fontSize: isUrdu ? 15 : 13)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: CColors.error),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────
  Widget _badge(String label, Color color, {IconData? icon, bool small = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, color: color, size: small ? 12 : 14), const SizedBox(width: 4)],
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: small ? 10 : 11)),
      ]),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'open': return CColors.success;
      case 'grace_period': return CColors.warning;
      case 'active': return CColors.warning;
      case 'scheduled': return CColors.info;
      case 'in-progress': return CColors.warning;
      case 'completed': return CColors.info;
      case 'cancelled':
      case 'deleted': return CColors.error;
      default: return CColors.grey;
    }
  }

  String _statusText(String s) {
    switch (s) {
      case 'open': return 'Open';
      case 'grace_period': return 'Grace Period';
      case 'active': return 'Active';
      case 'scheduled': return 'Scheduled';
      case 'in-progress': return 'In Progress';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      case 'deleted': return 'Deleted';
      default: return s;
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
            jobId: widget.job.id!,
            clientId: _clientId,
            clientName: await _getClientName(_clientId),
            workerId: _acceptedWorkerId!,
            rating: rating,
            comment: comment,
          );
          if (mounted) {
            setState(() => _reviewSubmitted = true);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Review submitted!'),
              backgroundColor: CColors.success,
              behavior: SnackBarBehavior.floating,
            ));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed: $e'),
              backgroundColor: CColors.error,
              behavior: SnackBarBehavior.floating,
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
          jobId: widget.job.id!,
          jobTitle: widget.job.title,
          clientId: _clientId,
          workerId: bid.workerId,
          amount: bid.amount,
        ),
      ),
    ).then((_) => _checkPaymentStatus());
  }

  void _openChat(BidModel bid) async {
    final chatId = _chatService.getChatId(widget.job.id!, bid.workerId);
    final workerName = await _getWorkerName(bid.workerId);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          jobTitle: widget.job.title,
          otherName: workerName,
          currentUserId: _clientId,
          otherUserId: bid.workerId,
          otherRole: 'worker',
        ),
      ),
    );
  }

  Future<String> _getWorkerName(String id) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('workers').doc(id).get();
      final info = doc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
      return info['name'] ?? info['fullName'] ?? 'Worker';
    } catch (_) {
      return 'Worker';
    }
  }

  Future<String> _getClientName(String id) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('clients').doc(id).get();
      final info = doc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
      return info['fullName'] ?? info['name'] ?? 'Client';
    } catch (_) {
      return 'Client';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CommonHeader(title: 'job.job_details'.tr(), showBackButton: true, onBackPressed: () => Navigator.pop(context)),
              Padding(
                padding: const EdgeInsets.all(CSizes.defaultSpace),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildJobInfoCard(isDark, isUrdu),
                    const SizedBox(height: CSizes.spaceBtwItems),
                    _buildStatusCard(isDark, isUrdu),
                    if (_jobStatus == 'grace_period' && _graceExpiry != null) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildGracePeriodBanner(isDark, isUrdu),
                    ],
                    if ((_jobStatus == 'active' || _jobStatus == 'scheduled') && widget.job.isUrgent && _workerStartDeadline != null && _workerStartRemainingSeconds > 0) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildWorkerStartDeadlineBanner(isDark, isUrdu),
                    ],
                    if (_jobStatus == 'scheduled' && !widget.job.isUrgent && _scheduledStartTime != null && _scheduledRemainingSeconds > 0) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildScheduledCountdownBanner(isDark, isUrdu),
                    ],
                    // --- Worker time proposal banner (client side) ---
                    if (_jobStatus == 'scheduled' && !widget.job.isUrgent) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildWorkerTimeProposalBanner(isDark, isUrdu),
                    ],
                    if (_pendingProgressRequest != null && _pendingProgressRequest!['status'] == 'pending') ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildProgressRequestBanner(isDark, isUrdu),
                    ],
                    if (_jobStatus == 'in-progress' && _acceptedWorkerId != null) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildExtraChargesButton(isDark, isUrdu),
                    ],
                    if (widget.job.hasLocation) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildMiniMap(isDark),
                    ],
                    const SizedBox(height: CSizes.spaceBtwSections),
                    _buildLiveBiddingButton(isDark, isUrdu),
                    // Live location button: show when worker has started (in-progress)
                    if (_jobStatus == 'in-progress' && _acceptedWorkerId != null) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildLiveLocationButton(isDark, isUrdu),
                    ],
                    // Payment button: show when in-progress and NOT yet paid
                    if (_jobStatus == 'in-progress' && _workerReachedLocation && !_jobPaid && _acceptedWorkerId != null) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildPaymentButton(isDark, isUrdu),
                    ],
                    // Mark complete button: show when in-progress and paid
                    if (_jobStatus == 'in-progress' && _workerReachedLocation && _jobPaid) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildMarkCompleteButton(isDark, isUrdu),
                    ],
                    if (_acceptedWorkerId != null) ...[
                      const SizedBox(height: CSizes.spaceBtwSections),
                      DisputeStatusBanner(jobId: widget.job.id!, currentUserId: _clientId, currentUserRole: 'client'),
                    ],
                    if (_acceptedWorkerId != null && (_jobStatus == 'in-progress' || _jobStatus == 'completed')) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildRaiseDisputeButton(isDark, isUrdu),
                    ],
                    const SizedBox(height: CSizes.spaceBtwSections),
                    _buildActionButtons(isDark, isUrdu),
                    const SizedBox(height: CSizes.spaceBtwSections * 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}