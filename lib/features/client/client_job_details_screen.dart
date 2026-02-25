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

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/bid_model.dart';
import '../../core/models/job_model.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/job_service.dart';
import '../../core/services/map_service.dart';
import '../../shared/widgets/common_header.dart';
import '../chat/chat_screen.dart';

class ClientJobDetailsScreen extends ConsumerStatefulWidget {
  final JobModel job;

  const ClientJobDetailsScreen({super.key, required this.job});

  @override
  ConsumerState<ClientJobDetailsScreen> createState() =>
      _ClientJobDetailsScreenState();
}

class _ClientJobDetailsScreenState
    extends ConsumerState<ClientJobDetailsScreen> {
  final _mapService  = MapService();
  final _bidService  = BidService();
  final _jobService  = JobService();
  final _chatService = ChatService();

  String? _acceptingBidId;
  late String _jobStatus;
  String _clientId   = '';
  bool   _isDeleting = false;

  // Progress request state — kept in sync via StreamSubscription
  Map<String, dynamic>? _pendingProgressRequest;
  bool _isRespondingToProgress = false;
  bool _isAlteringProgress     = false;

  // The worker ID whose bid was accepted (needed for progress flow)
  String? _acceptedWorkerId;

  // Live Firestore subscription — updates _jobStatus and _pendingProgressRequest
  // in real-time so every widget that reads them (including the header) is current.
  StreamSubscription<DocumentSnapshot>? _jobSub;

  @override
  void initState() {
    super.initState();
    // Seed from widget first so buttons render immediately on first frame.
    // FIX: normalize to lowercase so 'Open', 'OPEN', 'open' all match consistently.
    _jobStatus = widget.job.status.trim().toLowerCase();
    _loadClientId();
    _loadAcceptedWorkerId();
    _subscribeToJob();
  }

  void _subscribeToJob() {
    _jobSub = FirebaseFirestore.instance
        .collection('jobs')
        .doc(widget.job.id)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final data    = snap.data() as Map<String, dynamic>;
      // FIX: normalize to lowercase to guard against casing mismatches in Firestore.
      final status  = (data['status'] as String?)?.trim().toLowerCase() ?? _jobStatus;
      final request = data['progressRequest'] as Map<String, dynamic>?;
      setState(() {
        _jobStatus              = status;
        _pendingProgressRequest = request;
      });
    });
  }

  @override
  void dispose() {
    _jobSub?.cancel();
    super.dispose();
  }

  Future<void> _loadClientId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _clientId = prefs.getString('user_uid') ?? '');
  }

  /// Find the accepted worker for this job so we know who to notify
  /// when the client responds to a progress request.
  Future<void> _loadAcceptedWorkerId() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bids')
          .where('jobId',  isEqualTo: widget.job.id)
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty && mounted) {
        setState(() =>
        _acceptedWorkerId = snapshot.docs.first.data()['workerId'] as String?);
      }
    } catch (_) {}
  }

  // ── Accept bid ────────────────────────────────────────────────────
  Future<void> _acceptBid(BidModel bid) async {
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
      await _bidService.updateBidStatus(bid.id!, 'accepted');

      final allBids = await _bidService.getBidsByJob(widget.job.id!);
      for (final other in allBids) {
        if (other.id != bid.id && other.status == 'pending') {
          await _bidService.updateBidStatus(other.id!, 'rejected');
        }
      }

      await _jobService.updateJobStatus(widget.job.id!, 'in-progress');

      await _chatService.createOrGetChat(
        jobId:      widget.job.id!,
        jobTitle:   widget.job.title,
        clientId:   bid.clientId,
        workerId:   bid.workerId,
        workerName: await _getWorkerName(bid.workerId),
        clientName: await _getClientName(bid.clientId),
      );

      if (mounted) {
        setState(() {
          _jobStatus        = 'in-progress';
          _acceptedWorkerId = bid.workerId;
          _acceptingBidId   = null;
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

  // ── Delete job ───────────────────────────────────────────────────
  Future<void> _deleteJob() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('job.delete_job'.tr()),
        content: Text('job.delete_job_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
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

  // ── Respond to worker's progress request ────────────────────────
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
          _jobStatus               = accepted ? 'completed' : 'in-progress';
          _pendingProgressRequest  = null;
          _isRespondingToProgress  = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accepted
              ? 'Job marked as completed!'
              : 'Progress request rejected. Job stays in progress.'),
          backgroundColor: accepted ? CColors.success : CColors.warning,
          behavior: SnackBarBehavior.floating,
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

  // ── Alter job progress (client-initiated status change) ──────────
  Future<void> _alterJobProgress() async {
    // Show options: back to in-progress, or cancel job
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alter Job Progress'),
        content: const Text(
            'Choose what you would like to do with this job:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('common.cancel'.tr()),
          ),
          if (_jobStatus == 'completed')
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'in-progress'),
              child: const Text('Reopen (set In Progress)',
                  style: TextStyle(color: CColors.warning)),
            ),
          if (_jobStatus == 'in-progress')
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancelled'),
              child: const Text('Cancel Job',
                  style: TextStyle(color: CColors.error)),
            ),
          if (_jobStatus == 'in-progress')
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'completed'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: CColors.success),
              child: const Text('Mark Complete',
                  style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    // Extra confirmation for irreversible actions
    if (choice == 'cancelled' || choice == 'completed') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(choice == 'cancelled'
              ? 'Cancel Job?'
              : 'Mark Job as Complete?'),
          content: Text(choice == 'cancelled'
              ? 'This will cancel the job. The worker will be notified.'
              : 'This will mark the job as completed.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                choice == 'cancelled' ? CColors.error : CColors.success,
              ),
              child: Text('Confirm',
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _isAlteringProgress = true);
    try {
      await _jobService.alterJobProgress(
        jobId:     widget.job.id!,
        newStatus: choice,
      );
      if (mounted) {
        setState(() {
          _jobStatus              = choice;
          _pendingProgressRequest = null;
          _isAlteringProgress     = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Job status updated to "$choice".'),
          backgroundColor: CColors.success,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAlteringProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Error: $e'),
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
          // ── Header + action button ──────────────────────────────
          // _jobStatus is kept live by _subscribeToJob(), so the correct
          // button (delete / alter-progress) is always shown immediately.
          CommonHeader(
            title:          'job.job_details'.tr(),
            showBackButton: true,
            onBackPressed:  () => Navigator.pop(context),
          ),
          // ── Scrollable body ─────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildJobDetails(context, isDark, isUrdu),

                  // ── Action buttons — always visible, no hunting required ──
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildActionButtons(context, isDark, isUrdu),

                  if (widget.job.hasLocation) ...[
                    const SizedBox(height: CSizes.spaceBtwItems),
                    _buildMiniMap(isDark),
                  ],

                  // ── Pending progress-request banner ──────────────
                  if (_pendingProgressRequest != null &&
                      _pendingProgressRequest!['status'] == 'pending') ...[
                    const SizedBox(height: CSizes.spaceBtwSections),
                    _buildProgressRequestBanner(context, isDark, isUrdu),
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

  // ── Progress request banner ──────────────────────────────────────
  Widget _buildProgressRequestBanner(
      BuildContext context, bool isDark, bool isUrdu) {
    final note =
    _pendingProgressRequest!['note'] as String?;

    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
          colors: [
            CColors.warning.withOpacity(0.15),
            CColors.primary.withOpacity(0.08),
          ],
        ),
        border: Border.all(color: CColors.warning.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:        CColors.warning.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.update_rounded,
                    color: CColors.warning, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Progress Update Requested',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize:   isUrdu ? 16 : 14,
                        color:      isDark
                            ? CColors.textWhite
                            : CColors.textPrimary,
                      ),
                    ),
                    Text(
                      'The worker has requested to mark this job as complete.',
                      style: TextStyle(
                        fontSize: isUrdu ? 13 : 11,
                        color:    CColors.darkGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: CSizes.md),
            Container(
              width:   double.infinity,
              padding: const EdgeInsets.all(CSizes.md),
              decoration: BoxDecoration(
                color:        isDark
                    ? CColors.darkContainer
                    : CColors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
              ),
              child: Text(
                '"$note"',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize:  isUrdu ? 15 : 13,
                  color:     isDark
                      ? CColors.textWhite.withOpacity(0.8)
                      : CColors.darkerGrey,
                ),
              ),
            ),
          ],

          const SizedBox(height: CSizes.md),

          Row(
            children: [
              // Reject button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isRespondingToProgress
                      ? null
                      : () => _respondToProgressRequest(false),
                  icon:  const Icon(Icons.close_rounded,
                      size: 18, color: CColors.error),
                  label: Text(
                    _isRespondingToProgress ? 'common.loading'.tr() : 'Decline',
                    style: TextStyle(
                        color:    CColors.error,
                        fontSize: isUrdu ? 15 : 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    side:    const BorderSide(color: CColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape:   RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(CSizes.borderRadiusMd)),
                  ),
                ),
              ),
              const SizedBox(width: CSizes.md),
              // Accept button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isRespondingToProgress
                      ? null
                      : () => _respondToProgressRequest(true),
                  icon: _isRespondingToProgress
                      ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    _isRespondingToProgress
                        ? 'common.loading'.tr()
                        : 'Accept & Complete',
                    style: TextStyle(fontSize: isUrdu ? 16 : 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CColors.success,
                    foregroundColor: Colors.white,
                    padding:
                    const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            CSizes.borderRadiusMd)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Action buttons ──────────────────────────────────────────────
  // Prominent buttons shown right below the job card.
  // Client can delete (open jobs), mark complete / cancel (in-progress),
  // or reopen (completed).  No need to hunt for a tiny header icon.
  Widget _buildActionButtons(
      BuildContext context, bool isDark, bool isUrdu) {
    debugPrint('[ClientJobDetails] _buildActionButtons: _jobStatus="$_jobStatus"');

    if (_isDeleting || _isAlteringProgress) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(),
        ),
      );
    }

    // ── OPEN (or empty/unknown) → Delete button ──────────────────
    // FIX: status is now always lowercase so this comparison is reliable.
    // Treat empty string same as 'open' — if status failed to parse,
    // the safest action is still to allow deletion.
    if (_jobStatus == 'open' || _jobStatus.isEmpty) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _deleteJob,
          icon:  const Icon(Icons.delete_outline_rounded,
              color: CColors.error),
          label: Text('job.delete_job'.tr(),
              style: const TextStyle(
                  color: CColors.error, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            side:    const BorderSide(color: CColors.error),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:   RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(CSizes.borderRadiusLg)),
          ),
        ),
      );
    }

    // ── CANCELLED → show delete button so client can clean it up ──
    if (_jobStatus == 'cancelled') {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _deleteJob,
          icon:  const Icon(Icons.delete_outline_rounded,
              color: CColors.error),
          label: Text('job.delete_job'.tr(),
              style: const TextStyle(
                  color: CColors.error, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            side:    const BorderSide(color: CColors.error),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:   RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(CSizes.borderRadiusLg)),
          ),
        ),
      );
    }

    // ── IN-PROGRESS → Mark Complete + Cancel ─────────────────────
    if (_jobStatus == 'in-progress') {
      return Column(
        children: [
          // Mark Complete
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Mark Job as Complete?'),
                    content: const Text(
                        'This will mark the job as completed.'),
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
                if (ok == true) {
                  setState(() => _isAlteringProgress = true);
                  try {
                    await _jobService.alterJobProgress(
                        jobId: widget.job.id!, newStatus: 'completed');
                  } finally {
                    if (mounted) setState(() => _isAlteringProgress = false);
                  }
                }
              },
              icon:  const Icon(Icons.check_circle_outline_rounded,
                  size: 20),
              label: Text('Mark as Complete',
                  style: TextStyle(
                      fontSize:   isUrdu ? 16 : 14,
                      fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: CColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(CSizes.borderRadiusLg)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Cancel Job
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Cancel Job?'),
                    content: const Text(
                        'This will cancel the job. '
                            'The worker will be notified.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('common.cancel'.tr())),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: CColors.error),
                        child: const Text('Confirm',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  setState(() => _isAlteringProgress = true);
                  try {
                    await _jobService.alterJobProgress(
                        jobId: widget.job.id!, newStatus: 'cancelled');
                  } finally {
                    if (mounted) setState(() => _isAlteringProgress = false);
                  }
                }
              },
              icon:  const Icon(Icons.cancel_outlined,
                  color: CColors.error, size: 20),
              label: Text('Cancel Job',
                  style: const TextStyle(
                      color:      CColors.error,
                      fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side:    const BorderSide(color: CColors.error),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape:   RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(CSizes.borderRadiusLg)),
              ),
            ),
          ),
        ],
      );
    }

    // ── COMPLETED → Reopen ────────────────────────────────────────
    if (_jobStatus == 'completed') {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Reopen Job?'),
                content: const Text(
                    'This will set the job back to In Progress.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('common.cancel'.tr())),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: CColors.warning),
                    child: const Text('Reopen',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
            if (ok == true) {
              setState(() => _isAlteringProgress = true);
              try {
                await _jobService.alterJobProgress(
                    jobId: widget.job.id!, newStatus: 'in-progress');
              } finally {
                if (mounted) setState(() => _isAlteringProgress = false);
              }
            }
          },
          icon:  const Icon(Icons.refresh_rounded,
              color: CColors.warning, size: 20),
          label: const Text('Reopen Job',
              style: TextStyle(
                  color:      CColors.warning,
                  fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            side:    const BorderSide(color: CColors.warning),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:   RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(CSizes.borderRadiusLg)),
          ),
        ),
      );
    }

    // Unknown status — show delete as a safe fallback
    // This should never be reached but prevents invisible screens.
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _deleteJob,
        icon:  const Icon(Icons.delete_outline_rounded, color: CColors.error),
        label: Text('job.delete_job'.tr(),
            style: const TextStyle(color: CColors.error, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          side:    const BorderSide(color: CColors.error),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:   RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
        ),
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
            color:
            isDark ? CColors.darkerGrey : CColors.borderPrimary),
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

            if (isAccepted) ...[
              const SizedBox(height: CSizes.md),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openChat(bid),
                  icon:  const Icon(Icons.chat_outlined, size: 18),
                  label: Text('chat.open_chat'.tr(),
                      style: const TextStyle(fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CColors.secondary,
                    foregroundColor: CColors.primary,
                    padding:
                    const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            CSizes.borderRadiusMd)),
                  ),
                ),
              ),
            ],

            if (canAccept) ...[
              const SizedBox(height: CSizes.md),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                  isAccepting ? null : () => _acceptBid(bid),
                  icon: isAccepting
                      ? const SizedBox(
                      width:  16, height: 16,
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
                    padding:
                    const EdgeInsets.symmetric(vertical: 12),
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

  Future<String> _getWorkerName(String workerId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers').doc(workerId).get();
      final info =
          doc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
      return info['name'] ?? info['fullName'] ?? 'Worker';
    } catch (_) {
      return 'Worker';
    }
  }

  Future<String> _getClientName(String clientId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('clients').doc(clientId).get();
      final info =
          doc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
      return info['fullName'] ?? info['name'] ?? 'Client';
    } catch (_) {
      return 'Client';
    }
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