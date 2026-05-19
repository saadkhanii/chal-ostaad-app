// lib/features/client/client_live_bidding_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/models/bid_model.dart';
import '../../../core/models/job_model.dart';
import '../../../core/services/bid_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../shared/widgets/common_header.dart';
import '../../../shared/widgets/app_card.dart';
import '../chat/chat_screen.dart';
import '../profile/worker_profile_preview_sheet.dart';

final clientLiveBidsProvider = StreamProvider.family<List<BidModel>, String>((ref, jobId) {
  return FirebaseFirestore.instance
      .collection('bids')
      .where('jobId', isEqualTo: jobId)
      .snapshots()
      .map((snapshot) {
    final bids = snapshot.docs
        .map((doc) => BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>))
        .toList();
    final filtered = bids.where((b) {
      final status = b.status.trim().toLowerCase();
      return status == 'pending' || status == 'accepted';
    }).toList();
    filtered.sort((a, b) => a.amount.compareTo(b.amount));
    return filtered;
  });
});

class ClientLiveBiddingScreen extends ConsumerStatefulWidget {
  final JobModel job;
  final String clientId;
  const ClientLiveBiddingScreen({super.key, required this.job, required this.clientId});

  @override
  ConsumerState<ClientLiveBiddingScreen> createState() => _ClientLiveBiddingScreenState();
}

class _ClientLiveBiddingScreenState extends ConsumerState<ClientLiveBiddingScreen> {
  final BidService _bidService = BidService();
  final ChatService _chatService = ChatService();
  final Map<String, String> _workerNames = {};
  String? _acceptingBidId;
  bool _isOpeningChat = false;   // ✅ loading state for chat button

  Future<String> _getWorkerName(String workerId) async {
    if (_workerNames.containsKey(workerId)) return _workerNames[workerId]!;
    try {
      final doc = await FirebaseFirestore.instance.collection('workers').doc(workerId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final personal = data['personalInfo'] as Map<String, dynamic>? ?? {};
        final name = personal['fullName'] ?? personal['name'] ?? 'Worker';
        _workerNames[workerId] = name;
        return name;
      }
      return 'Worker';
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

  DateTime? _getProposedStartTime(BidModel bid) {
    if (widget.job.isUrgent) return DateTime.now().add(const Duration(minutes: 1));
    if (bid.workerProposedStartTime != null) return bid.workerProposedStartTime;
    if (widget.job.scheduledAt != null) return widget.job.scheduledAt!.toDate();
    return null;
  }

  String _getStartTimeDisplayText(BidModel bid) {
    if (widget.job.isUrgent) return 'ASAP / Urgent';
    final proposed = _getProposedStartTime(bid);
    if (proposed != null) return DateFormat('d MMM yyyy, hh:mm a').format(proposed);
    return 'Not specified';
  }

  Future<void> _acceptBid(BidModel bid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept Bid?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accept this bid for Rs. ${bid.amount.toStringAsFixed(0)}?'),
            const SizedBox(height: 12),
            const Text('You will have 60 seconds to cancel if you change your mind.'),
            const SizedBox(height: 12),
            Text(
              widget.job.isUrgent
                  ? 'This is an urgent job. After 60 seconds, the worker can start immediately.'
                  : 'After 60 seconds, the job will be scheduled and you can negotiate the start time.',
              style: TextStyle(fontSize: 12, color: CColors.darkGrey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('common.cancel'.tr())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: CColors.primary),
            child: Text('bid.accept'.tr(), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _acceptingBidId = bid.id);
    try {
      await _bidService.acceptBidWithGrace(bid.id!);
      await _chatService.createOrGetChat(
        jobId: widget.job.id!,
        jobTitle: widget.job.title,
        clientId: widget.clientId,
        workerId: bid.workerId,
        workerName: await _getWorkerName(bid.workerId),
        clientName: await _getClientName(widget.clientId),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bid accepted! You have 60 seconds to cancel if needed.'),
          backgroundColor: CColors.success,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to accept bid: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _acceptingBidId = null);
    }
  }

  // ✅ FIXED: Always create/get the full chat document before opening
  void _openChat(String workerId, String workerName) async {
    if (_isOpeningChat) return;
    setState(() => _isOpeningChat = true);
    try {
      final chatId = await _chatService.createOrGetChat(
        jobId: widget.job.id!,
        jobTitle: widget.job.title,
        clientId: widget.clientId,
        workerId: workerId,
        workerName: workerName,
        clientName: await _getClientName(widget.clientId),
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            jobTitle: widget.job.title,
            otherName: workerName,
            currentUserId: widget.clientId,
            otherUserId: workerId,
            otherRole: 'worker',
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
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }

  void _showWorkerProfile(String workerId) {
    WorkerProfilePreviewSheet.show(context, workerId: workerId);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          const CommonHeader(title: 'Live Bidding', showBackButton: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(CSizes.defaultSpace, CSizes.defaultSpace, CSizes.defaultSpace, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: CColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.gavel_rounded, size: 14, color: CColors.primary),
                          const SizedBox(width: 6),
                          Text('Live Auction', style: TextStyle(fontSize: isUrdu ? 12 : 11, color: CColors.primary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? CColors.secondary : CColors.secondary,
                    borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
                    border: Border.all(
                      color: isDark ? CColors.borderPrimary : CColors.borderPrimary,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.job.title,
                    style: TextStyle(
                      fontSize: isUrdu ? 20 : 18,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: isDark ? Colors.white : CColors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
              child: Consumer(
                builder: (context, ref, _) {
                  final bidsAsync = ref.watch(clientLiveBidsProvider(widget.job.id!));
                  return bidsAsync.when(
                    data: (bids) {
                      if (bids.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [Icon(Icons.gavel_outlined, size: 48, color: Colors.grey.shade400), const SizedBox(height: 12), Text('No bids yet', style: TextStyle(fontSize: isUrdu ? 16 : 14, color: Colors.grey))],
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: bids.length,
                        itemBuilder: (context, index) {
                          final bid = bids[index];
                          final rank = index + 1;
                          return _buildBidCard(bid, rank, isDark, isUrdu);
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error loading bids: $e')),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBidCard(BidModel bid, int rank, bool isDark, bool isUrdu) {
    final isAccepted = bid.status.trim().toLowerCase() == 'accepted';
    final isJobOpen = widget.job.status.trim().toLowerCase() == 'open';
    final isAccepting = _acceptingBidId == bid.id;
    final hasValidStartTime = widget.job.isUrgent || _getProposedStartTime(bid) != null;
    final startTimeDisplay = _getStartTimeDisplayText(bid);

    return FutureBuilder<String>(
      future: _getWorkerName(bid.workerId),
      builder: (context, nameSnapshot) {
        final workerName = nameSnapshot.data ?? 'Worker';
        return AppCard(
          headerGradient: AppCardGradients.scheduled(),
          headerTitle: Row(
            children: [
              const Icon(Icons.person_outline_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  workerName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          headerTrailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                child: Text('Rank #$rank', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              if (isAccepted) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: CColors.success, borderRadius: BorderRadius.circular(20)),
                  child: const Text('Accepted ✓', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('Rs. ${bid.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: isUrdu ? 22 : 20, color: CColors.secondary)),
                  const SizedBox(width: 8),
                  Text('— quoted amount', style: TextStyle(fontSize: 11, color: CColors.darkGrey)),
                ],
              ),
              const SizedBox(height: CSizes.sm),
              Row(children: [
                Icon(widget.job.isUrgent ? Icons.flash_on : Icons.event_available_rounded, size: 14, color: CColors.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(widget.job.isUrgent ? 'Start: ASAP / Urgent' : 'Proposed start: $startTimeDisplay', style: TextStyle(fontSize: isUrdu ? 13 : 11, color: CColors.darkGrey))),
                if (!widget.job.isUrgent && bid.workerProposedStartTime == null && widget.job.scheduledAt != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: CColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text("Client's time", style: TextStyle(fontSize: 9, color: CColors.primary)),
                  ),
              ]),
              const SizedBox(height: CSizes.sm),
              if (bid.message != null && bid.message!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: CSizes.sm),
                  child: Text('"${bid.message}"', style: TextStyle(fontStyle: FontStyle.italic, fontSize: isUrdu ? 15 : 13, color: isDark ? CColors.textWhite.withValues(alpha: 0.7) : CColors.darkerGrey)),
                ),
              if (bid.availableTime != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: CSizes.sm),
                  child: Row(
                    children: [
                      Icon(Icons.access_time_outlined, size: 16, color: CColors.primary),
                      const SizedBox(width: 6),
                      Text('Available: ${DateFormat('d MMM yyyy, hh:mm a').format(bid.availableTime!)}', style: TextStyle(fontSize: isUrdu ? 13 : 11, color: CColors.darkGrey)),
                    ],
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _isOpeningChat ? null : () => _openChat(bid.workerId, workerName),
                    icon: _isOpeningChat
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chat_outlined, size: 16, color: CColors.primary),
                    label: Text('Chat', style: TextStyle(fontSize: isUrdu ? 12 : 11, color: CColors.primary)),
                  ),
                  TextButton.icon(
                    onPressed: () => _showWorkerProfile(bid.workerId),
                    icon: const Icon(Icons.person_rounded, size: 16, color: CColors.primary),
                    label: Text('View Profile', style: TextStyle(fontSize: isUrdu ? 12 : 11, color: CColors.primary)),
                  ),
                  if (isJobOpen && !isAccepted && hasValidStartTime)
                    ElevatedButton(
                      onPressed: isAccepting ? null : () => _acceptBid(bid),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
                      ),
                      child: isAccepting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Accept'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}