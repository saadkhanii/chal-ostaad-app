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
import '../../../core/services/worker_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../chat/chat_screen.dart';
import '../dispute/raise_dispute_dialog.dart';
import '../dispute/dispute_status_banner.dart';
import '../payment/extra_charges_sheet.dart';
import '../../../shared/widgets/job_media_gallery.dart';
import 'worker_live_bidding_screen.dart';
import '../../shared/widgets/propose_new_time_dialog.dart';

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
  final _workerService = WorkerService();

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
  StreamSubscription<QuerySnapshot>? _bidsSub;

  String _clientFullName = '';
  String _workerName = '';

  bool _acceptClientTime = true;
  DateTime? _workerProposedStartTime;
  Map<String, dynamic>? _pendingTimeProposal;

  bool _workerReachedLocation = false;
  bool _hasAnyBid = false;

  // For urgent jobs: 10‑minute deadline
  DateTime? _workerStartDeadline;
  int _workerStartRemainingSeconds = 0;
  Timer? _workerStartTimer;

  // For scheduled jobs:
  DateTime? _scheduledStartTime;
  int _scheduledRemainingSeconds = 0;
  Timer? _scheduledTimer;
  DateTime? _scheduledWorkerDeadline;
  int _scheduledWorkerRemainingSeconds = 0;
  Timer? _scheduledWorkerTimer;

  // ── Live location sharing ────────────────────────────────────────
  bool _locationSharingEnabled = false;
  Timer? _locationUpdateTimer;
  bool _isSharingActive = false;

  // ── Time proposal rejection handling ─────────────────────────────
  bool _showRejectedProposalOptions = false;
  bool _isRespondingToRejectedProposal = false;

  // ── Worker bid status ────────────────────────────────────────────
  String? _workerBidStatus; // 'pending', 'accepted', 'rejected', or null

  // ── BAN STATUS ────────────────────────────────────────────────────
  bool _isBanned = false;

  @override
  void initState() {
    super.initState();
    _liveJobStatus = widget.job.status;
    _checkExistingBid();
    _loadClientName();
    _loadWorkerData(); // now loads both name and ban status
    _loadDistanceToJob();
    _subscribeToJob();
    _listenToBids();
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
      final reachedLocation = data['workerReachedLocation'] as bool? ?? false;
      final deadline = (data['workerStartDeadline'] as Timestamp?)?.toDate();
      final graceExpiry = (data['gracePeriodExpiry'] as Timestamp?)?.toDate();
      final scheduledAt = (data['scheduledAt'] as Timestamp?)?.toDate();
      final sharingEnabled = data['locationSharingEnabled'] as bool? ?? false;

      final charges = rawExtras
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final hasPending = charges
          .any((c) => c['status'] == 'pending' && c['requestedBy'] != 'worker');

      final approvedTotal = charges
          .where((c) => c['status'] == 'approved')
          .fold<double>(0, (s, c) => s + ((c['amount'] as num?)?.toDouble() ?? 0));

      final timeProposal = data['pendingTimeProposal'] as Map<String, dynamic>?;

      setState(() {
        _liveJobStatus = status;
        _pendingProgressRequest = request;
        _hasPendingExtras = hasPending;
        _approvedExtrasTotal = approvedTotal;
        _pendingTimeProposal = timeProposal;
        _workerReachedLocation = reachedLocation;
        _workerStartDeadline = deadline;
        _scheduledStartTime = scheduledAt;
        _scheduledWorkerDeadline = deadline;
        _locationSharingEnabled = sharingEnabled;

        // If the worker's proposal was rejected, show the decision banner
        if (timeProposal != null &&
            timeProposal['proposedBy'] == 'worker' &&
            timeProposal['status'] == 'rejected') {
          _showRejectedProposalOptions = true;
        } else {
          _showRejectedProposalOptions = false;
        }
      });

      // Grace period expiry fallback
      if (status == 'grace_period' && graceExpiry != null) {
        final now = DateTime.now();
        if (now.isAfter(graceExpiry)) {
          _bidService.finaliseAcceptance(widget.job.id!).catchError((e) {
            debugPrint('Error finalising from worker side: $e');
          });
        }
        return;
      }

      // Re‑check accepted bid when status becomes active/scheduled
      if ((status == 'active' || status == 'scheduled') && _acceptedBid == null) {
        _checkExistingBid();
      }

      // Deadlines
      if (status == 'active' && deadline != null && widget.job.isUrgent) {
        _updateWorkerStartCountdown();
      } else if (status == 'scheduled' && !widget.job.isUrgent && scheduledAt != null) {
        _updateScheduledCountdown();
        final now = DateTime.now();
        if (now.isAfter(scheduledAt) && deadline != null) {
          _updateScheduledWorkerDeadlineCountdown();
        }
      } else {
        _workerStartTimer?.cancel();
        _workerStartRemainingSeconds = 0;
        _scheduledTimer?.cancel();
        _scheduledRemainingSeconds = 0;
        _scheduledWorkerTimer?.cancel();
        _scheduledWorkerRemainingSeconds = 0;
      }

      // ── Start / stop live location updates ────────────────────
      if (status == 'in-progress' && sharingEnabled && !_isSharingActive) {
        _startLocationUpdates();
      } else if ((status != 'in-progress' || !sharingEnabled) && _isSharingActive) {
        _stopLocationUpdates();
      }
    });
  }

  void _listenToBids() {
    _bidsSub = FirebaseFirestore.instance
        .collection('bids')
        .where('jobId', isEqualTo: widget.job.id)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _hasAnyBid = snapshot.docs.isNotEmpty;
        });
      }
    });
  }

  @override
  void dispose() {
    _jobSub?.cancel();
    _bidsSub?.cancel();
    _workerStartTimer?.cancel();
    _scheduledTimer?.cancel();
    _scheduledWorkerTimer?.cancel();
    _stopLocationUpdates();
    _amountController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  // ── Live location sharing methods ─────────────────────────────────
  Future<void> _startLocationUpdates() async {
    if (_isSharingActive) return;
    final granted = await _locationService.requestLocationPermission();
    if (!granted) {
      debugPrint('[LocationSharing] permission denied — sharing disabled');
      return;
    }
    _isSharingActive = true;
    await _workerService.disableLiveSharing(widget.workerId); // clear false first
    await _updateWorkerLiveLocation(); // this will set isLiveSharing = true
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateWorkerLiveLocation();
    });
    debugPrint('Started live location updates for job ${widget.job.id}');
  }

  Future<void> _updateWorkerLiveLocation() async {
    if (!_isSharingActive) return;
    try {
      final pos = await _locationService.getCurrentPosition();
      final heading = pos.heading;
      final accuracy = pos.accuracy;
      await _workerService.updateLiveLocation(
        widget.workerId,
        pos.latitude,
        pos.longitude,
        heading: heading >= 0 ? heading : null,
        accuracy: accuracy,
      );
      debugPrint('Live location updated: ${pos.latitude}, ${pos.longitude}');
    } catch (e) {
      debugPrint('Failed to update live location: $e');
    }
  }

  void _stopLocationUpdates() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;
    _isSharingActive = false;
    _workerService.disableLiveSharing(widget.workerId);
    debugPrint('Stopped live location updates');
  }

  // ── Helper methods ──────────────────────────────────────────────────

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
      final querySnapshot = await FirebaseFirestore.instance
          .collection('bids')
          .where('jobId', isEqualTo: widget.job.id)
          .where('workerId', isEqualTo: widget.workerId)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final status = doc.data()['status'] as String?;
        setState(() {
          _hasExistingBid = true;
          _workerBidStatus = status;
        });
        if (status == 'accepted') {
          setState(() {
            _acceptedBid = BidModel.fromSnapshot(
              doc as DocumentSnapshot<Map<String, dynamic>>,
            );
          });
        }
      } else {
        setState(() {
          _hasExistingBid = false;
          _workerBidStatus = null;
          _acceptedBid = null;
        });
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

  // ── UPDATED: Load worker data including ban status ──────────────
  Future<void> _loadWorkerData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(widget.workerId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        final info = data['personalInfo'] as Map<String, dynamic>? ?? {};
        final name = info['fullName'] as String? ?? '';
        if (name.isNotEmpty && mounted) setState(() => _workerName = name);

        // Check verification status for ban
        final verification = data['verification'] as Map<String, dynamic>?;
        final status = verification?['status'] as String?;
        if (status == 'banned' && mounted) {
          setState(() => _isBanned = true);
        } else {
          setState(() => _isBanned = false);
        }
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

  void _updateWorkerStartCountdown() {
    if (_workerStartDeadline == null) return;
    _workerStartTimer?.cancel();
    final now = DateTime.now();
    if (now.isAfter(_workerStartDeadline!)) {
      _workerStartRemainingSeconds = 0;
      _handleWorkerStartTimeout();
      return;
    }
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
        _handleWorkerStartTimeout();
      } else {
        setState(() => _workerStartRemainingSeconds = newRemaining);
      }
    });
  }

  Future<void> _handleWorkerStartTimeout() async {
    if (_acceptedBid == null) return;
    try {
      await _bidService.workerNoActionTimeout(widget.job.id!, widget.workerId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('You did not start the job in time. It has been reopened.'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('Error handling worker start timeout: $e');
    }
  }

  void _updateScheduledCountdown() {
    if (_scheduledStartTime == null) return;
    _scheduledTimer?.cancel();
    final now = DateTime.now();
    if (now.isAfter(_scheduledStartTime!)) {
      setState(() => _scheduledRemainingSeconds = 0);
      if (_scheduledWorkerDeadline != null) {
        _updateScheduledWorkerDeadlineCountdown();
      }
      return;
    }
    final remaining = _scheduledStartTime!.difference(now).inSeconds;
    setState(() => _scheduledRemainingSeconds = remaining);
    _scheduledTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final newRemaining = _scheduledStartTime!.difference(DateTime.now()).inSeconds;
      if (newRemaining <= 0) {
        timer.cancel();
        setState(() => _scheduledRemainingSeconds = 0);
        if (_scheduledWorkerDeadline != null) {
          _updateScheduledWorkerDeadlineCountdown();
        }
      } else {
        setState(() => _scheduledRemainingSeconds = newRemaining);
      }
    });
  }

  void _updateScheduledWorkerDeadlineCountdown() {
    if (_scheduledWorkerDeadline == null) return;
    _scheduledWorkerTimer?.cancel();
    final now = DateTime.now();
    if (now.isAfter(_scheduledWorkerDeadline!)) {
      _scheduledWorkerRemainingSeconds = 0;
      _handleWorkerStartTimeout();
      return;
    }
    final remaining = _scheduledWorkerDeadline!.difference(now).inSeconds;
    setState(() => _scheduledWorkerRemainingSeconds = remaining);
    _scheduledWorkerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final newRemaining = _scheduledWorkerDeadline!.difference(DateTime.now()).inSeconds;
      if (newRemaining <= 0) {
        timer.cancel();
        setState(() => _scheduledWorkerRemainingSeconds = 0);
        _handleWorkerStartTimeout();
      } else {
        setState(() => _scheduledWorkerRemainingSeconds = newRemaining);
      }
    });
  }

  Future<void> _startJob() async {
    if (!widget.job.isUrgent && widget.job.scheduledAt != null) {
      final now = DateTime.now();
      if (now.isBefore(widget.job.scheduledAt!.toDate())) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Job cannot start before scheduled time.'),
          backgroundColor: CColors.warning,
        ));
        return;
      }
    }

    final shareLocation = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share Live Location?'),
        content: const Text('The client will be able to see your live location while you work. Do you agree?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    if (shareLocation == null) return;

    setState(() => _isLoading = true);
    try {
      await _bidService.startJob(widget.job.id!, widget.workerId, shareLocation: shareLocation);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Job started! Client can now see your location.'),
          backgroundColor: CColors.success,
        ));
        setState(() => _liveJobStatus = 'in-progress');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: CColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelJobAsWorker() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Job?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('If you cancel, the job will be reopened as urgent and you will be banned from rebidding.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: CColors.error), child: const Text('Yes, Cancel')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      await _bidService.workerCancelJob(widget.job.id!, widget.workerId, reason: reasonController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Job cancelled. You cannot rebid on this job.'),
          backgroundColor: CColors.warning,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: CColors.error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _proposeNewTime() async {
    await ProposeNewTimeDialog.show(
      context,
      title: 'Propose New Start Time',
      hint: 'Suggest a new date and time for this job.',
      onPropose: (newTime) async {
        await _bidService.proposeNewTime(widget.job.id!, widget.workerId, newTime);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Proposal sent to client.'),
            backgroundColor: CColors.success,
          ));
        }
      },
    );
  }

  Future<void> _respondToClientTimeProposal(bool accept) async {
    if (_pendingTimeProposal == null) return;
    setState(() => _isLoading = true);
    try {
      await _bidService.respondToTimeProposal(widget.job.id!, widget.workerId, accept);
      if (mounted) {
        if (accept) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('You accepted the proposal. New start time set.'),
            backgroundColor: CColors.success,
          ));
          // Refresh the job data
          setState(() {
            _pendingTimeProposal = null;
            _isLoading = false;
          });
        } else {
          // Worker rejected client's proposal – banned and job reopened
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('You rejected the proposal. You have been banned from this job and it is reopened for other workers.'),
            backgroundColor: CColors.warning,
          ));
          // Navigate back to the previous screen
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: CColors.error,
        ));
      }
    }
  }

  // ── Handling rejected proposal: continue or cancel ──────────────────
  Future<void> _continueWithOriginalTime() async {
    setState(() => _isRespondingToRejectedProposal = true);
    try {
      await _bidService.clearTimeProposal(widget.job.id!);
      if (mounted) {
        setState(() {
          _pendingTimeProposal = null;
          _showRejectedProposalOptions = false;
          _isRespondingToRejectedProposal = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('You will continue with the original scheduled time.'),
          backgroundColor: CColors.info,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRespondingToRejectedProposal = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: CColors.error,
        ));
      }
    }
  }

  Future<void> _cancelJobAfterRejectedProposal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Job?'),
        content: const Text(
          'If you cancel now, the job will be reopened as urgent (if less than 2 hours remain) and you will be banned from rebidding. Do you want to proceed?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: CColors.error), child: const Text('Yes, Cancel')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isRespondingToRejectedProposal = true);
    try {
      final now = DateTime.now();
      final originalStart = widget.job.scheduledAt!.toDate();
      final remaining = originalStart.difference(now);
      final makeUrgent = remaining.inHours < 2;

      await _bidService.workerCancelJob(
        widget.job.id!,
        widget.workerId,
        reason: 'Cancelled after rejected time proposal',
        makeUrgent: makeUrgent,
      );
      if (mounted) {
        setState(() {
          _showRejectedProposalOptions = false;
          _pendingTimeProposal = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(makeUrgent ? 'Job reopened as urgent.' : 'Job cancelled.'),
          backgroundColor: CColors.warning,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _showRejectedProposalOptions = false;
          _pendingTimeProposal = null;
          _isRespondingToRejectedProposal = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: CColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isRespondingToRejectedProposal = false);
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('common.cancel'.tr())),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: CColors.success), child: const Text('Confirm', style: TextStyle(color: Colors.white))),
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

  // ── UPDATED: placeBid with ban check (redundant but safe) ──────
  Future<void> _placeBid() async {
    if (_isBanned) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Your account is banned. You cannot place bids.'),
        backgroundColor: CColors.error,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

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

  // ── UPDATED: openPreBidChat uses _loadWorkerData ────────────────
  Future<void> _openPreBidChat() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      if (_workerName.isEmpty) await _loadWorkerData();
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

  // ── UPDATED: openChat uses _loadWorkerData ──────────────────────
  Future<void> _openChat() async {
    if (_acceptedBid == null || !mounted) return;
    setState(() => _isLoading = true);
    try {
      if (_workerName.isEmpty) await _loadWorkerData();
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

  // ── Status card, job card, etc. ──

  Color _getStatusColor(String s) {
    switch (s) {
      case 'open': return CColors.success;
      case 'grace_period': return CColors.warning;
      case 'active': return CColors.warning;
      case 'scheduled': return CColors.info;
      case 'in-progress': return CColors.warning;
      case 'completed': return CColors.info;
      case 'cancelled': return CColors.error;
      default: return CColors.grey;
    }
  }

  String _getStatusText(String s) {
    switch (s) {
      case 'open': return 'Open';
      case 'grace_period': return 'Grace Period';
      case 'active': return 'Active';
      case 'scheduled': return 'Scheduled';
      case 'in-progress': return 'In Progress';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default: return s;
    }
  }

  Widget _badge(String label, Color color, {IconData? icon, bool small = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: small ? 12 : 14),
          const SizedBox(width: 4),
        ],
        Text(label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: small ? 10 : 11)),
      ]),
    );
  }

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
    if (firestoreStatus == 'open' && _hasAnyBid) return 'bidding';
    switch (firestoreStatus) {
      case 'open': return 'open';
      case 'grace_period': return 'grace_period';
      case 'active': return 'waiting';
      case 'scheduled': return 'scheduled';
      case 'in-progress':
        return _workerReachedLocation ? 'in_progress' : 'started';
      case 'completed': return 'completed';
      default: return 'bidding';
    }
  }

  int _getCurrentStepIndex() {
    final steps = _getStatusSteps();
    String currentKey = _mapStatusToStepKey(_liveJobStatus);
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
      headerGradient: widget.job.isUrgent ? AppCardGradients.urgent() : AppCardGradients.scheduled(),
      headerTitle: Text(
        'Job Progress',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: isUrdu ? 16 : 14,
          color: Colors.white,
        ),
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(steps.length, (i) {
            final step = steps[i];
            final isCompleted = i < currentIndex;
            final isActive = i == currentIndex;
            final isLast = i == steps.length - 1;
            return Row(
              mainAxisSize: MainAxisSize.min,
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
    );
  }

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

  Widget _buildJobDetailsCard(bool isDark, bool isUrdu) {
    final statusColor = _getStatusColor(_liveJobStatus);
    final statusText = _getStatusText(_liveJobStatus);
    return AppCard(
      margin: EdgeInsets.zero,
      elevation: 2,
      headerGradient: _getHeaderGradient(),
      headerTitle: Text(
        widget.job.title,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      headerTrailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, children: [
            if (widget.job.isUrgent) _badge('URGENT / ASAP', CColors.error, icon: Icons.flash_on),
            if (_hasPendingExtras) _badge('Extras Pending', CColors.warning, icon: Icons.warning_amber_rounded, small: true),
          ]),
          const SizedBox(height: 16),
          Text(widget.job.description,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: isDark ? CColors.textWhite.withValues(alpha: 0.8) : CColors.darkerGrey,
                  height: 1.5,
                  fontSize: isUrdu ? 16 : 14)),
          if (widget.job.hasBudget || widget.job.hasSchedule) ...[
            const SizedBox(height: 12),
            _buildBudgetScheduleRow(isDark, isUrdu),
          ],
          // 👇 SCHEDULED COUNTDOWN – visible to all workers when job is scheduled and time not yet passed
          if (!widget.job.isUrgent &&
              _liveJobStatus == 'scheduled' &&
              _scheduledStartTime != null &&
              _scheduledRemainingSeconds > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: CColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 16, color: CColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Scheduled start in ${_formatDuration(Duration(seconds: _scheduledRemainingSeconds))}',
                      style: TextStyle(
                        fontSize: isUrdu ? 14 : 12,
                        fontWeight: FontWeight.w500,
                        color: CColors.info,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

  Widget _buildMiniMap(bool isDark, bool isUrdu) {
    final jobLatLng = LatLng(widget.job.latitude!, widget.job.longitude!);
    return AppCard(
      margin: EdgeInsets.zero,
      bodyPadding: EdgeInsets.zero,
      headerGradient: widget.job.isUrgent ? AppCardGradients.urgent() : AppCardGradients.scheduled(),
      headerTitle: const Text('Job Location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      body: SizedBox(
        height: 200,
        width: double.infinity,
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
      ),
    );
  }

  Widget _buildExtraChargesCard(bool isDark, bool isUrdu) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.job.id)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final raw = data?['extraCharges'] as List<dynamic>? ?? [];
        final charges = raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final approvedTotal = charges
            .where((c) => c['status'] == 'approved')
            .fold<double>(0, (s, c) => s + ((c['amount'] as num?)?.toDouble() ?? 0));

        final pendingCount = charges
            .where((c) => c['status'] == 'pending')
            .length;

        return AppCard(
          margin: EdgeInsets.zero,
          headerGradient: AppCardGradients.scheduled(),
          headerTitle: Row(
            children: [
              const Icon(Icons.add_circle_outline, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                'Extra Charges',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              if (pendingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$pendingCount pending',
                    style: const TextStyle(color: CColors.warning, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Approved extras total',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isDark ? CColors.textWhite.withValues(alpha: 0.7) : CColors.darkGrey,
                      fontSize: isUrdu ? 15 : 13,
                    ),
                  ),
                  Text(
                    'Rs. ${approvedTotal.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isUrdu ? 18 : 16,
                      color: CColors.primary,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              if (charges.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No extra charges have been proposed yet.'),
                )
              else
                Column(
                  children: charges.map((c) => _buildChargeListItem(c, isDark, isUrdu)).toList(),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => ExtraChargesSheet.show(
                    context,
                    jobId: widget.job.id!,
                    currentRole: 'worker',
                  ),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  label: Text(
                    'Request Extra Charge',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: isUrdu ? 16 : 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChargeListItem(Map<String, dynamic> charge, bool isDark, bool isUrdu) {
    final amount = (charge['amount'] as num?)?.toDouble() ?? 0;
    final desc = charge['description'] as String? ?? '';
    final status = charge['status'] as String? ?? 'pending';
    final requestedBy = charge['requestedBy'] as String? ?? '';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'approved':
        statusColor = CColors.success;
        statusLabel = 'Approved';
        break;
      case 'rejected':
        statusColor = CColors.error;
        statusLabel = 'Rejected';
        break;
      default:
        statusColor = CColors.warning;
        statusLabel = 'Pending';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? CColors.darkContainer.withValues(alpha: 0.5) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: isUrdu ? 14 : 13,
                    color: isDark ? CColors.textWhite : CColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      'Rs. ${amount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: CColors.primary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• $requestedBy',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? CColors.textWhite.withValues(alpha: 0.5) : CColors.darkGrey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashConfirmBanner(bool isDark, bool isUrdu) {
    final baseAmount = _acceptedBid?.amount ?? 0;
    final totalAmount = baseAmount + _approvedExtrasTotal;
    return AppCard(
      margin: EdgeInsets.zero,
      headerGradient: widget.job.isUrgent ? AppCardGradients.urgent() : AppCardGradients.scheduled(),
      headerTitle: const Row(children: [
        Icon(Icons.payments_outlined, color: Colors.white, size: 20),
        SizedBox(width: 8),
        Text('Cash Payment Pending',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 15)),
      ]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
        ],
      ),
    );
  }

  Widget _buildTimeProposalBanner(bool isDark, bool isUrdu) {
    final proposal = _pendingTimeProposal!;
    final proposedBy = proposal['proposedBy'] as String;
    if (proposedBy != 'client') return const SizedBox.shrink();
    final status = proposal['status'] as String;
    final proposedTime = (proposal['proposedTime'] as Timestamp).toDate();

    if (status == 'rejected_by_worker') {
      // Worker already rejected; waiting for client decision
      return Container(
        padding: const EdgeInsets.all(CSizes.md),
        decoration: BoxDecoration(
          color: CColors.info.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
          border: Border.all(color: CColors.info.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: CColors.info, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You rejected the client\'s proposed time. Waiting for client\'s decision.',
                style: TextStyle(
                  fontSize: isUrdu ? 13 : 12,
                  color: isDark ? CColors.textWhite.withValues(alpha: 0.8) : CColors.darkerGrey,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (status != 'pending') return const SizedBox.shrink();    return AppCard(
      margin: EdgeInsets.zero,
      headerGradient: widget.job.isUrgent ? AppCardGradients.urgent() : AppCardGradients.scheduled(),
      headerTitle: Row(children: [
        Icon(Icons.event_available_rounded, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(child: Text('Client proposed a new start time',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
      ]),
      body: Column(children: [
        const SizedBox(height: 8),
        Text(DateFormat('d MMM yyyy, hh:mm a').format(proposedTime),
            style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _respondToClientTimeProposal(false),
              style: OutlinedButton.styleFrom(foregroundColor: CColors.error),
              child: const Text('Reject'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _respondToClientTimeProposal(true),
              style: ElevatedButton.styleFrom(backgroundColor: CColors.success),
              child: const Text('Accept'),
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Rejected proposal banner ─────────────────────────────────────
  Widget _buildRejectedProposalBanner(bool isDark, bool isUrdu) {
    if (!_showRejectedProposalOptions) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color: CColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(color: CColors.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: CColors.error, size: 22),
              const SizedBox(width: 8),
              Text(
                'Your proposed time was rejected',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: CColors.error,
                  fontSize: isUrdu ? 16 : 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'The client did not accept your new start time. You can either continue with the original scheduled time or cancel the job.',
            style: TextStyle(
              fontSize: isUrdu ? 13 : 12,
              color: isDark ? CColors.textWhite.withValues(alpha: 0.8) : CColors.darkerGrey,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isRespondingToRejectedProposal ? null : _continueWithOriginalTime,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: CColors.primary),
                  ),
                  child: _isRespondingToRejectedProposal
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Continue with original time'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isRespondingToRejectedProposal ? null : _cancelJobAfterRejectedProposal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CColors.error,
                    foregroundColor: Colors.white,
                  ),
                  child: _isRespondingToRejectedProposal
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Cancel Job'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── STYLED SCHEDULED START CARD ──────────────────────────────────
  Widget _buildScheduledStartCard(bool isDark, bool isUrdu) {
    final bool isScheduledTimePast = _scheduledRemainingSeconds <= 0;
    final bool hasDeadline = _scheduledWorkerDeadline != null;
    final bool isDeadlineRunning = hasDeadline && _scheduledWorkerRemainingSeconds > 0;
    final bool isDeadlineExpired = hasDeadline && _scheduledWorkerRemainingSeconds <= 0 && isScheduledTimePast;

    String title;
    String countdownText;
    bool enableStart;
    Color primaryColor;
    String? scheduledDisplay;

    if (_scheduledStartTime != null) {
      scheduledDisplay = DateFormat('d MMM yyyy, hh:mm a').format(_scheduledStartTime!);
    }

    if (!isScheduledTimePast) {
      title = 'Scheduled start time';
      countdownText = _formatDuration(Duration(seconds: _scheduledRemainingSeconds));
      enableStart = false;
      primaryColor = CColors.primary;
    } else if (isDeadlineRunning) {
      title = '⚠️ You must start within 2 hours ⚠️';
      countdownText = _formatDuration(Duration(seconds: _scheduledWorkerRemainingSeconds));
      enableStart = true;
      primaryColor = CColors.warning;
    } else if (isDeadlineExpired) {
      title = 'Deadline expired';
      countdownText = 'Job will be cancelled';
      enableStart = false;
      primaryColor = CColors.error;
    } else {
      title = 'Job is ready to start';
      countdownText = 'Ready to start';
      enableStart = true;
      primaryColor = CColors.success;
    }

    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(color: primaryColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDeadlineRunning ? Icons.warning_amber_rounded : Icons.event_available_rounded,
                color: primaryColor,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                    fontSize: isUrdu ? 16 : 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_scheduledStartTime != null) ...[
            Text(
              scheduledDisplay!,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: isUrdu ? 15 : 13,
                color: isDark ? CColors.textWhite : CColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            countdownText,
            style: TextStyle(
              fontSize: isUrdu ? 22 : 20,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          if (isDeadlineRunning) ...[
            const SizedBox(height: 6),
            Text(
              'You have only 2 hours after the scheduled time to start the job. Otherwise it will be cancelled automatically and you will be banned.',
              style: TextStyle(
                fontSize: isUrdu ? 12 : 11,
                color: CColors.darkGrey,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: enableStart && !_isLoading ? _startJob : null,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(
                    'Start Job',
                    style: TextStyle(fontSize: isUrdu ? 15 : 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: enableStart ? CColors.success : CColors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _cancelJobAsWorker,
                  icon: const Icon(Icons.cancel_outlined, size: 20),
                  label: Text(
                    'Cancel Job',
                    style: TextStyle(fontSize: isUrdu ? 15 : 13, color: CColors.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: CColors.error),
                    foregroundColor: CColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUrgentStartCard(bool isDark, bool isUrdu) {
    final minutes = (_workerStartRemainingSeconds / 60).floor();
    final seconds = _workerStartRemainingSeconds % 60;
    final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    final isUrgentTime = _workerStartRemainingSeconds <= 120;
    final timerColor = isUrgentTime ? CColors.error : CColors.primary;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(CSizes.md),
          decoration: BoxDecoration(
            color: isDark ? CColors.darkContainer : CColors.white,
            borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
            border: Border.all(color: timerColor.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: timerColor.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined, color: timerColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Action Required — Start or Cancel',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isUrdu ? 16 : 14,
                        color: timerColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: timerColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: timerColor, width: 1.5),
                  ),
                  child: Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: isUrdu ? 32 : 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: timerColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _startJob,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text(
                        'Start Job',
                        style: TextStyle(fontSize: isUrdu ? 15 : 13, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _cancelJobAsWorker,
                      icon: const Icon(Icons.cancel_outlined, size: 20),
                      label: Text(
                        'Cancel Job',
                        style: TextStyle(fontSize: isUrdu ? 15 : 13, color: CColors.error),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: CColors.error),
                        foregroundColor: CColors.error,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: CSizes.spaceBtwItems),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(CSizes.md),
          decoration: BoxDecoration(
            color: CColors.error.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
            border: Border.all(color: CColors.error.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: CColors.error, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Important Warning',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: CColors.error,
                      fontSize: isUrdu ? 15 : 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'If you do not start or cancel within 10 minutes, this job will be automatically cancelled and reopened for other workers. You will also be permanently banned from bidding on this job again.',
                style: TextStyle(
                  fontSize: isUrdu ? 13 : 12,
                  color: isDark ? CColors.textWhite.withValues(alpha: 0.75) : CColors.darkerGrey,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

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

  // ── UPDATED: Build bid form with ban check at top ────────────────
  Widget _buildBidForm(bool isDark, bool isUrdu) {
    // 🔒 Banned check – always show banned message if true
    if (_isBanned) {
      return _buildBannedMessage(isDark, isUrdu);
    }

    // If no bid placed yet and job is open → show place bid form
    if (_workerBidStatus == null && widget.job.status == 'open') {
      return _buildPlaceBidForm(isDark, isUrdu);
    }

    // If bid rejected → show red banner
    if (_workerBidStatus == 'rejected') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(CSizes.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          color: CColors.error.withValues(alpha: 0.1),
          border: Border.all(color: CColors.error.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            const Icon(Icons.cancel_outlined, size: 40, color: CColors.error),
            const SizedBox(height: 12),
            Text(
              'Your bid was rejected',
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                fontWeight: FontWeight.w700,
                color: CColors.error,
                fontSize: isUrdu ? 20 : 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The client has selected another worker. You may not bid again on this job.',
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

    // If bid pending → show "already placed" message
    if (_workerBidStatus == 'pending') {
      return _buildAlreadyPlacedMessage(isDark, isUrdu);
    }

    // If bid accepted → show accepted panel
    if (_workerBidStatus == 'accepted' && _acceptedBid != null) {
      return _buildAcceptedPanel(isDark, isUrdu);
    }

    // Fallback: if job not open and no bid, show job closed message
    return _buildJobClosedMessage(isDark, isUrdu);
  }

  // ── NEW: Banned message widget ────────────────────────────────────
  Widget _buildBannedMessage(bool isDark, bool isUrdu) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: CColors.error.withValues(alpha: 0.1),
        border: Border.all(color: CColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.block_rounded, size: 40, color: CColors.error),
          const SizedBox(height: 12),
          Text(
            'You are Banned',
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              fontWeight: FontWeight.w700,
              color: CColors.error,
              fontSize: isUrdu ? 20 : 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You cannot place bids because your account has been banned. Please contact admin to resolve the status.',
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

  Widget _buildWorkerStartTimeChoice(bool isDark, bool isUrdu) {
    if (widget.job.isUrgent) return const SizedBox.shrink();
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
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openPreBidChat,
              icon: const Icon(Icons.chat_rounded, size: 20, color: Colors.white),
              label: Text(
                'Chat with Client',
                style: TextStyle(
                  fontSize: isUrdu ? 16 : 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: CColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
                ),
                elevation: 2,
              ),
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
          workerName: _workerName,
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    // Show scheduled card only if not urgent, status is scheduled, start time exists,
    // worker is accepted, and proposal is NOT rejected.
    bool showScheduledCard = !widget.job.isUrgent &&
        _liveJobStatus == 'scheduled' &&
        _scheduledStartTime != null &&
        _acceptedBid != null &&
        !_showRejectedProposalOptions;

    bool showUrgentCard = widget.job.isUrgent &&
        _liveJobStatus == 'active' &&
        _acceptedBid != null &&
        _workerStartDeadline != null &&
        DateTime.now().isBefore(_workerStartDeadline!);

    bool showCashConfirm = _pendingPaymentId != null && _liveJobStatus == 'in-progress';

    // Show propose button only if scheduled, accepted, NOT urgent, and proposal NOT rejected.
    bool showProposeTimeButton = _liveJobStatus == 'scheduled' &&
        _acceptedBid != null &&
        !widget.job.isUrgent &&
        !_showRejectedProposalOptions;

    // Check if worker already has a pending proposal (so we can show an info message)
    bool hasWorkerPendingProposal = _pendingTimeProposal != null &&
        _pendingTimeProposal!['proposedBy'] == 'worker' &&
        _pendingTimeProposal!['status'] == 'pending';

    // Check if client has a pending proposal
    bool hasClientPendingProposal = _pendingTimeProposal != null &&
        _pendingTimeProposal!['proposedBy'] == 'client' &&
        _pendingTimeProposal!['status'] == 'pending';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: RefreshIndicator(
        onRefresh: () async => Future.delayed(const Duration(milliseconds: 500)),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    const SizedBox(height: CSizes.spaceBtwItems),
                    _buildStatusCard(isDark, isUrdu),

                    // --- Rejected proposal banner (worker side) ---
                    if (_showRejectedProposalOptions) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildRejectedProposalBanner(isDark, isUrdu),
                    ],

                    // --- Scheduled timer card (only if not rejected) ---
                    if (showScheduledCard) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildScheduledStartCard(isDark, isUrdu),

                      // --- Propose New Time button directly under timer ---
                      if (showProposeTimeButton && !hasWorkerPendingProposal) ...[
                        const SizedBox(height: CSizes.spaceBtwItems),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _proposeNewTime,
                            icon: const Icon(Icons.event_available_rounded, size: 20),
                            label: Text(
                              'Propose New Time',
                              style: TextStyle(
                                fontSize: isUrdu ? 16 : 14,
                                fontWeight: FontWeight.bold,
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
                            ),
                          ),
                        ),
                      ],

                      // --- Info message when worker proposal is pending ---
                      if (hasWorkerPendingProposal) ...[
                        const SizedBox(height: CSizes.spaceBtwItems),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: CColors.info.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: CColors.info.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: CColors.info, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'You have already proposed a new time. Waiting for client response.',
                                  style: TextStyle(
                                    fontSize: isUrdu ? 13 : 12,
                                    color: isDark ? CColors.textWhite.withValues(alpha: 0.8) : CColors.darkerGrey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // --- Client proposal banner (right under scheduled card) ---
                      if (hasClientPendingProposal) ...[
                        const SizedBox(height: CSizes.spaceBtwItems),
                        _buildTimeProposalBanner(isDark, isUrdu),
                      ],
                    ],

                    if (showUrgentCard) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildUrgentStartCard(isDark, isUrdu),
                    ],

                    if (widget.job.hasLocation) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildMiniMap(isDark, isUrdu),
                    ],

                    if (_acceptedBid != null && _liveJobStatus == 'in-progress') ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildExtraChargesCard(isDark, isUrdu),
                    ],

                    if (showCashConfirm) ...[
                      const SizedBox(height: CSizes.spaceBtwItems),
                      _buildCashConfirmBanner(isDark, isUrdu),
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