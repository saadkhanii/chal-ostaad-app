// lib/features/dispute/raise_dispute_dialog.dart
//
// Bottom sheet dialog for raising a dispute.
// Used by both client and worker from their job details screens.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/dispute_model.dart';
import '../../core/services/dispute_service.dart';

class RaiseDisputeDialog extends StatefulWidget {
  final String jobId;
  final String jobTitle;
  final String clientId;
  final String clientName;
  final String workerId;
  final String workerName;
  final String currentUserId;
  final String currentUserRole; // 'client' | 'worker'
  final VoidCallback? onDisputeRaised;

  const RaiseDisputeDialog({
    super.key,
    required this.jobId,
    required this.jobTitle,
    required this.clientId,
    required this.clientName,
    required this.workerId,
    required this.workerName,
    required this.currentUserId,
    required this.currentUserRole,
    this.onDisputeRaised,
  });

  // ── Convenience show method ────────────────────────────────────
  static Future<void> show(
      BuildContext context, {
        required String jobId,
        required String jobTitle,
        required String clientId,
        required String clientName,
        required String workerId,
        required String workerName,
        required String currentUserId,
        required String currentUserRole,
        VoidCallback? onDisputeRaised,
      }) {
    return showModalBottomSheet(
      context:           context,
      isScrollControlled: true,
      backgroundColor:   Colors.transparent,
      builder: (_) => RaiseDisputeDialog(
        jobId:           jobId,
        jobTitle:        jobTitle,
        clientId:        clientId,
        clientName:      clientName,
        workerId:        workerId,
        workerName:      workerName,
        currentUserId:   currentUserId,
        currentUserRole: currentUserRole,
        onDisputeRaised: onDisputeRaised,
      ),
    );
  }

  @override
  State<RaiseDisputeDialog> createState() => _RaiseDisputeDialogState();
}

class _RaiseDisputeDialogState extends State<RaiseDisputeDialog> {
  final _formKey        = GlobalKey<FormState>();
  final _descCtrl       = TextEditingController();
  final _disputeService = DisputeService();
  final _picker         = ImagePicker();

  String? _selectedReason;
  String? _evidenceBase64;
  bool    _isSubmitting = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  // ── Pick evidence image ────────────────────────────────────────
  Future<void> _pickEvidence() async {
    final picked = await _picker.pickImage(
      source:    ImageSource.gallery,
      imageQuality: 60,
      maxWidth:  1024,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted) setState(() => _evidenceBase64 = base64Encode(bytes));
  }

  void _removeEvidence() => setState(() => _evidenceBase64 = null);

  // ── Submit ─────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedReason == null) {
      _showSnack('Please select a reason.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    final error = await _disputeService.raiseDispute(
      jobId:          widget.jobId,
      jobTitle:       widget.jobTitle,
      clientId:       widget.clientId,
      clientName:     widget.clientName,
      workerId:       widget.workerId,
      workerName:     widget.workerName,
      raisedBy:       widget.currentUserRole,
      raisedById:     widget.currentUserId,
      reason:         _selectedReason!,
      description:    _descCtrl.text.trim(),
      evidenceBase64: _evidenceBase64,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (error != null) {
      _showSnack(error, isError: true);
      return;
    }

    Navigator.pop(context);
    widget.onDisputeRaised?.call();
    _showSnack('Dispute raised. Admin will review it shortly.', isError: false);
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg),
      backgroundColor: isError ? CColors.error : CColors.success,
      behavior:        SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final isUrdu    = Localizations.localeOf(context).languageCode == 'ur';
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left:   CSizes.defaultSpace,
        right:  CSizes.defaultSpace,
        top:    CSizes.defaultSpace,
        bottom: bottomPad + CSizes.defaultSpace,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Handle bar ─────────────────────────────────────
              Center(
                child: Container(
                  width:  40,
                  height: 4,
                  decoration: BoxDecoration(
                    color:        CColors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: CSizes.lg),

              // ── Title ──────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:        CColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.flag_rounded,
                        color: CColors.error, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Raise a Dispute',
                          style: TextStyle(
                            fontSize:   isUrdu ? 20 : 18,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? CColors.textWhite
                                : CColors.textPrimary,
                          ),
                        ),
                        Text(
                          widget.jobTitle,
                          style: TextStyle(
                            fontSize: isUrdu ? 13 : 12,
                            color:    CColors.darkGrey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CSizes.spaceBtwItems),

              // ── Info note ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(CSizes.md),
                decoration: BoxDecoration(
                  color:        CColors.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                  border: Border.all(
                      color: CColors.warning.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: CColors.warning, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your dispute will be reviewed by an admin. '
                            'You can continue working on the job while it is under review.',
                        style: TextStyle(
                          fontSize: isUrdu ? 13 : 11.5,
                          color:    CColors.darkGrey,
                          height:   1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CSizes.spaceBtwItems),

              // ── Reason dropdown ────────────────────────────────
              Text(
                'Reason *',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize:   isUrdu ? 15 : 14,
                  color: isDark ? CColors.textWhite : CColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color:        isDark ? CColors.dark : CColors.lightGrey,
                  borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                  border: Border.all(
                    color: _selectedReason == null
                        ? CColors.borderPrimary
                        : CColors.primary.withOpacity(0.5),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value:       _selectedReason,
                    isExpanded:  true,
                    hint: Text(
                      'Select a reason',
                      style: TextStyle(
                        color:    CColors.darkGrey,
                        fontSize: isUrdu ? 15 : 14,
                      ),
                    ),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: CColors.darkGrey),
                    dropdownColor:
                    isDark ? CColors.darkContainer : Colors.white,
                    items: DisputeReasons.all
                        .map((r) => DropdownMenuItem(
                      value: r,
                      child: Text(r,
                          style: TextStyle(
                            fontSize: isUrdu ? 15 : 14,
                            color: isDark
                                ? CColors.textWhite
                                : CColors.textPrimary,
                          )),
                    ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedReason = v),
                  ),
                ),
              ),
              const SizedBox(height: CSizes.spaceBtwItems),

              // ── Description ────────────────────────────────────
              Text(
                'Description *',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize:   isUrdu ? 15 : 14,
                  color: isDark ? CColors.textWhite : CColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller:         _descCtrl,
                maxLines:           4,
                maxLength:          500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Describe the issue in detail...',
                  hintStyle: TextStyle(
                      color: CColors.darkGrey, fontSize: isUrdu ? 15 : 14),
                  filled:      true,
                  fillColor:   isDark ? CColors.dark : CColors.lightGrey,
                  border: OutlineInputBorder(
                    borderRadius:
                    BorderRadius.circular(CSizes.borderRadiusMd),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                    BorderRadius.circular(CSizes.borderRadiusMd),
                    borderSide:
                    BorderSide(color: CColors.primary.withOpacity(0.6)),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please describe the issue.';
                  }
                  if (v.trim().length < 20) {
                    return 'Please provide more detail (at least 20 characters).';
                  }
                  return null;
                },
              ),
              const SizedBox(height: CSizes.spaceBtwItems),

              // ── Evidence (optional) ────────────────────────────
              Text(
                'Evidence (Optional)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize:   isUrdu ? 15 : 14,
                  color: isDark ? CColors.textWhite : CColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              if (_evidenceBase64 == null)
                GestureDetector(
                  onTap: _pickEvidence,
                  child: Container(
                    width:   double.infinity,
                    height:  100,
                    decoration: BoxDecoration(
                      color:        isDark ? CColors.dark : CColors.lightGrey,
                      borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                      border: Border.all(
                        color:     CColors.borderPrimary,
                        style:     BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: CColors.darkGrey, size: 28),
                        const SizedBox(height: 6),
                        Text(
                          'Tap to attach a photo',
                          style: TextStyle(
                            color:    CColors.darkGrey,
                            fontSize: isUrdu ? 13 : 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius:
                      BorderRadius.circular(CSizes.borderRadiusMd),
                      child: Image.memory(
                        base64Decode(_evidenceBase64!),
                        width:  double.infinity,
                        height: 160,
                        fit:    BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top:   8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _removeEvidence,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: CColors.error,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: CSizes.spaceBtwSections),

              // ── Submit button ──────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                      width:  18,
                      height: 18,
                      child:  CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.flag_rounded, size: 18),
                  label: Text(
                    _isSubmitting ? 'Submitting...' : 'Submit Dispute',
                    style: TextStyle(
                      fontSize:   isUrdu ? 17 : 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(CSizes.borderRadiusLg)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}