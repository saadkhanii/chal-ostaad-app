// lib/features/dispute/dispute_status_banner.dart
//
// Shown on both client and worker job details screens.
// Streams the dispute in real-time so status updates instantly.
// Also lets the non-raiser submit their evidence from here.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/dispute_model.dart';
import '../../core/services/dispute_service.dart';

class DisputeStatusBanner extends StatefulWidget {
  final String jobId;
  final String currentUserId;
  final String currentUserRole; // 'client' | 'worker'

  const DisputeStatusBanner({
    super.key,
    required this.jobId,
    required this.currentUserId,
    required this.currentUserRole,
  });

  @override
  State<DisputeStatusBanner> createState() => _DisputeStatusBannerState();
}

class _DisputeStatusBannerState extends State<DisputeStatusBanner> {
  final _disputeService = DisputeService();
  final _picker         = ImagePicker();
  bool  _isUploading    = false;

  // ── Pick and upload evidence for the other party ──────────────
  Future<void> _addMyEvidence(String disputeId) async {
    final picked = await _picker.pickImage(
      source:       ImageSource.gallery,
      imageQuality: 60,
      maxWidth:     1024,
    );
    if (picked == null || !mounted) return;

    setState(() => _isUploading = true);
    try {
      final bytes = await picked.readAsBytes();
      await _disputeService.addEvidence(
        disputeId:      disputeId,
        role:           widget.currentUserRole,
        evidenceBase64: base64Encode(bytes),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:         Text('Evidence submitted successfully.'),
          backgroundColor: CColors.success,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Failed to submit evidence: $e'),
          backgroundColor: CColors.error,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── Show full evidence image ───────────────────────────────────
  void _viewEvidence(BuildContext context, String base64, String label) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(base64Decode(base64)),
            ),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = Localizations.localeOf(context).languageCode == 'ur';

    return StreamBuilder<DisputeModel?>(
      stream: _disputeService.jobDisputeStream(widget.jobId),
      builder: (context, snap) {
        // No dispute — render nothing
        if (!snap.hasData || snap.data == null) return const SizedBox.shrink();

        final dispute = snap.data!;

        // Closed disputes — don't show banner
        if (dispute.isClosed) return const SizedBox.shrink();

        return _buildBanner(context, dispute, isDark, isUrdu);
      },
    );
  }

  Widget _buildBanner(
      BuildContext context,
      DisputeModel dispute,
      bool isDark,
      bool isUrdu,
      ) {
    final config = _statusConfig(dispute.status);

    // Has this user already submitted their evidence?
    final myEvidence = widget.currentUserRole == 'client'
        ? dispute.clientEvidence
        : dispute.workerEvidence;

    final otherEvidence = widget.currentUserRole == 'client'
        ? dispute.workerEvidence
        : dispute.clientEvidence;

    final iRaised = dispute.raisedById == widget.currentUserId;

    return Container(
      width:   double.infinity,
      margin:  const EdgeInsets.only(bottom: CSizes.spaceBtwItems),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        gradient: LinearGradient(
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
          colors: [
            config.color.withOpacity(0.12),
            config.color.withOpacity(0.05),
          ],
        ),
        border: Border.all(color: config.color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(CSizes.md),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:        config.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(config.icon, color: config.color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize:   isUrdu ? 15 : 13,
                          color: isDark
                              ? CColors.textWhite
                              : CColors.textPrimary,
                        ),
                      ),
                      Text(
                        config.subtitle,
                        style: TextStyle(
                          fontSize: isUrdu ? 12 : 11,
                          color:    CColors.darkGrey,
                          height:   1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:        config.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: config.color.withOpacity(0.4)),
                  ),
                  child: Text(
                    config.badge,
                    style: TextStyle(
                      color:      config.color,
                      fontWeight: FontWeight.bold,
                      fontSize:   isUrdu ? 11 : 9,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 0.5),

          // ── Dispute details ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: CSizes.md, vertical: CSizes.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reason chip
                Row(
                  children: [
                    Icon(Icons.label_outline_rounded,
                        size: 14, color: CColors.darkGrey),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        dispute.reason,
                        style: TextStyle(
                          fontSize:   isUrdu ? 13 : 12,
                          color:      CColors.darkGrey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Raised by + time
                Row(
                  children: [
                    Icon(Icons.person_outline_rounded,
                        size: 14, color: CColors.darkGrey),
                    const SizedBox(width: 6),
                    Text(
                      'Raised by ${dispute.raisedByLabel} · '
                          '${timeago.format(dispute.createdAt.toDate())}',
                      style: TextStyle(
                        fontSize: isUrdu ? 12 : 11,
                        color:    CColors.darkGrey,
                      ),
                    ),
                  ],
                ),

                // ── Resolution block (resolved only) ─────────────
                if (dispute.isResolved) ...[
                  const SizedBox(height: CSizes.md),
                  Container(
                    width:   double.infinity,
                    padding: const EdgeInsets.all(CSizes.md),
                    decoration: BoxDecoration(
                      color: CColors.success.withOpacity(0.08),
                      borderRadius:
                      BorderRadius.circular(CSizes.borderRadiusMd),
                      border: Border.all(
                          color: CColors.success.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.gavel_rounded,
                                color: CColors.success, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Resolution: ${dispute.resolutionLabel}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize:   isUrdu ? 14 : 12,
                                color:      CColors.success,
                              ),
                            ),
                          ],
                        ),
                        if (dispute.adminNote != null &&
                            dispute.adminNote!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            dispute.adminNote!,
                            style: TextStyle(
                              fontSize: isUrdu ? 13 : 11.5,
                              color:    isDark
                                  ? CColors.textWhite.withOpacity(0.8)
                                  : CColors.darkerGrey,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Evidence section ───────────────────────────────────
          // Only show when dispute is active (open or reviewing)
          if (dispute.isActive) ...[
            const Divider(height: 1, thickness: 0.5),
            Padding(
              padding: const EdgeInsets.all(CSizes.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Evidence',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize:   isUrdu ? 13 : 12,
                      color: isDark
                          ? CColors.textWhite
                          : CColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // My evidence
                      Expanded(
                        child: _buildEvidenceBox(
                          context:   context,
                          isDark:    isDark,
                          isUrdu:    isUrdu,
                          label:     'Your Evidence',
                          base64:    myEvidence,
                          canUpload: true,
                          disputeId: dispute.id!,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Other party's evidence
                      Expanded(
                        child: _buildEvidenceBox(
                          context:   context,
                          isDark:    isDark,
                          isUrdu:    isUrdu,
                          label: widget.currentUserRole == 'client'
                              ? 'Worker\'s Evidence'
                              : 'Client\'s Evidence',
                          base64:    otherEvidence,
                          canUpload: false,
                          disputeId: dispute.id!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Evidence box ───────────────────────────────────────────────
  Widget _buildEvidenceBox({
    required BuildContext context,
    required bool         isDark,
    required bool         isUrdu,
    required String       label,
    required String?      base64,
    required bool         canUpload,
    required String       disputeId,
  }) {
    if (base64 != null && base64.isNotEmpty) {
      // Show thumbnail
      return GestureDetector(
        onTap: () => _viewEvidence(context, base64, label),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: isUrdu ? 12 : 11, color: CColors.darkGrey)),
            const SizedBox(height: 4),
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                  BorderRadius.circular(CSizes.borderRadiusMd),
                  child: Image.memory(
                    base64Decode(base64),
                    height: 70,
                    width:  double.infinity,
                    fit:    BoxFit.cover,
                  ),
                ),
                // View icon overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius:
                      BorderRadius.circular(CSizes.borderRadiusMd),
                      color: Colors.black.withOpacity(0.2),
                    ),
                    child: const Center(
                      child: Icon(Icons.zoom_in_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // No evidence yet
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: isUrdu ? 12 : 11, color: CColors.darkGrey)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: canUpload && !_isUploading
              ? () => _addMyEvidence(disputeId)
              : null,
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: isDark ? CColors.dark : CColors.lightGrey,
              borderRadius:
              BorderRadius.circular(CSizes.borderRadiusMd),
              border: Border.all(
                color: canUpload
                    ? CColors.primary.withOpacity(0.4)
                    : CColors.borderPrimary,
              ),
            ),
            child: Center(
              child: _isUploading && canUpload
                  ? const SizedBox(
                width:  20,
                height: 20,
                child:  CircularProgressIndicator(
                    strokeWidth: 2, color: CColors.primary),
              )
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    canUpload
                        ? Icons.add_photo_alternate_outlined
                        : Icons.hourglass_empty_rounded,
                    color: canUpload
                        ? CColors.primary
                        : CColors.grey,
                    size: 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    canUpload ? 'Add Photo' : 'Not submitted',
                    style: TextStyle(
                      fontSize: isUrdu ? 11 : 10,
                      color: canUpload
                          ? CColors.primary
                          : CColors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Status config ──────────────────────────────────────────────
  _StatusConfig _statusConfig(String status) {
    switch (status) {
      case 'reviewing':
        return _StatusConfig(
          color:    CColors.warning,
          icon:     Icons.manage_search_rounded,
          title:    'Dispute Under Review',
          subtitle: 'An admin is reviewing your dispute.',
          badge:    'REVIEWING',
        );
      case 'resolved':
        return _StatusConfig(
          color:    CColors.success,
          icon:     Icons.gavel_rounded,
          title:    'Dispute Resolved',
          subtitle: 'Admin has made a decision on this dispute.',
          badge:    'RESOLVED',
        );
      default: // open
        return _StatusConfig(
          color:    CColors.error,
          icon:     Icons.flag_rounded,
          title:    'Dispute Raised',
          subtitle: 'Awaiting admin review. You can still continue working.',
          badge:    'OPEN',
        );
    }
  }
}

// ── Internal config model ──────────────────────────────────────────
class _StatusConfig {
  final Color  color;
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;

  const _StatusConfig({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
  });
}