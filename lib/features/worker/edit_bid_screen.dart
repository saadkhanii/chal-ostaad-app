// lib/features/worker/edit_bid_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/models/bid_model.dart';
import '../../../core/models/job_model.dart';
import '../../../core/services/bid_service.dart';
import '../../../shared/widgets/common_header.dart';

class EditBidScreen extends StatefulWidget {
  final BidModel bid;
  final String jobTitle;

  const EditBidScreen({
    super.key,
    required this.bid,
    required this.jobTitle,
  });

  @override
  State<EditBidScreen> createState() => _EditBidScreenState();
}

class _EditBidScreenState extends State<EditBidScreen> {
  final _amountController = TextEditingController();
  final _messageController = TextEditingController();
  final _bidService = BidService();

  bool _isLoading = false;
  bool _isLoadingJob = true;
  JobModel? _job;

  bool _acceptClientTime = true;
  DateTime? _workerProposedStartTime;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.bid.amount.toStringAsFixed(0);
    _messageController.text = widget.bid.message ?? '';
    _loadJob();
  }

  Future<void> _loadJob() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.bid.jobId)
          .get();
      if (doc.exists && mounted) {
        final job = JobModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
        setState(() {
          _job = job;
          _isLoadingJob = false;
          if (widget.bid.workerProposedStartTime != null) {
            _acceptClientTime = false;
            _workerProposedStartTime = widget.bid.workerProposedStartTime;
          } else {
            _acceptClientTime = true;
            _workerProposedStartTime = null;
          }
        });
      } else {
        setState(() => _isLoadingJob = false);
      }
    } catch (e) {
      debugPrint('Error loading job: $e');
      setState(() => _isLoadingJob = false);
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

  Future<void> _saveChanges() async {
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter a valid amount'),
        backgroundColor: CColors.warning,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final updatedBid = BidModel(
        id: widget.bid.id,
        jobId: widget.bid.jobId,
        workerId: widget.bid.workerId,
        clientId: widget.bid.clientId,
        amount: amount,
        message: _messageController.text.trim().isNotEmpty
            ? _messageController.text.trim()
            : null,
        status: widget.bid.status,
        createdAt: widget.bid.createdAt,
        updatedAt: Timestamp.now(),
        availableTime: null,
        workerProposedStartTime: (_job?.isUrgent ?? false) ? null : (_acceptClientTime ? null : _workerProposedStartTime),
      );

      await _bidService.updateBid(widget.bid.id!, updatedBid);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to update bid: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildClientStartTimeInfo() {
    if (_isLoadingJob) return const SizedBox.shrink();
    if (_job == null) return const SizedBox.shrink();

    if (_job!.isUrgent) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: CColors.warning.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.flash_on, color: CColors.warning, size: 20),
              const SizedBox(width: 8),
              Text(
                'URGENT / ASAP JOB',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: CColors.warning,
                  fontSize: 14,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              'This is an urgent job. No start time editing is available.',
              style: TextStyle(fontSize: 12, color: CColors.darkGrey),
            ),
          ],
        ),
      );
    }

    if (_job!.scheduledAt == null) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: CColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, size: 16, color: CColors.primary),
          SizedBox(width: 8),
          Expanded(child: Text('Client did not specify a preferred start time.')),
        ]),
      );
    }

    final clientTime = _job!.scheduledAt!.toDate();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Client\'s preferred start time',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: CColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE, d MMM yyyy, hh:mm a').format(clientTime),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerStartTimeChoice(bool isDark, bool isUrdu) {
    if (_isLoadingJob || _job == null) return const SizedBox.shrink();

    // For urgent jobs, no time editing.
    if (_job!.isUrgent) {
      return const SizedBox.shrink();
    }

    // If job has no scheduled time, only allow proposing a time.
    if (_job!.scheduledAt == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your proposed start time',
            style: TextStyle(fontSize: isUrdu ? 14 : 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          if (_workerProposedStartTime != null)
            Container(
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
          if (_workerProposedStartTime == null)
            TextButton.icon(
              onPressed: _pickWorkerProposedTime,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text('Tap to pick your proposed start time', style: TextStyle(fontSize: isUrdu ? 13 : 12)),
              style: TextButton.styleFrom(foregroundColor: CColors.primary),
            ),
        ],
      );
    }

    // Normal case: job has scheduled time
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title: 'Edit Bid',
            showBackButton: true,
            onBackPressed: () => Navigator.pop(context, false),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Editing bid for: ${widget.jobTitle}',
                    style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: isUrdu ? 20 : 18,
                    ),
                  ),
                  const SizedBox(height: CSizes.spaceBtwSections),

                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
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
                  const SizedBox(height: CSizes.spaceBtwInputFields),

                  if (_isLoadingJob)
                    const Center(child: CircularProgressIndicator())
                  else
                    _buildClientStartTimeInfo(),
                  const SizedBox(height: CSizes.spaceBtwInputFields),

                  if (!_isLoadingJob)
                    _buildWorkerStartTimeChoice(isDark, isUrdu),
                  const SizedBox(height: CSizes.spaceBtwSections),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveChanges,
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
                        'Save Changes',
                        style: TextStyle(fontSize: isUrdu ? 18 : 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}