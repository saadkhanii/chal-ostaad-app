// lib/features/worker/screens/worker_job_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/models/job_model.dart';
import '../../../core/models/bid_model.dart';
import '../../../core/services/bid_service.dart';
import '../../../shared/widgets/common_header.dart';

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
  ConsumerState<WorkerJobDetailsScreen> createState() => _WorkerJobDetailsScreenState();
}

class _WorkerJobDetailsScreenState extends ConsumerState<WorkerJobDetailsScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final BidService _bidService = BidService();
  bool _isLoading = false;
  bool _hasExistingBid = false;
  String _clientName = 'common.loading'.tr();

  @override
  void initState() {
    super.initState();
    _checkExistingBid();
    _loadClientName();
  }

  Future<void> _checkExistingBid() async {
    try {
      final hasBid = await _bidService.hasWorkerBidOnJob(widget.workerId, widget.job.id!);
      if (mounted) {
        setState(() {
          _hasExistingBid = hasBid;
        });
      }
    } catch (e) {
      debugPrint('Error checking existing bid: $e');
    }
  }

  Future<void> _loadClientName() async {
    try {
      final clientDoc = await FirebaseFirestore.instance.collection('clients').doc(widget.job.clientId).get();

      if (clientDoc.exists) {
        final clientData = clientDoc.data()!;
        final personalInfo = clientData['personalInfo'];
        if (personalInfo is Map<String, dynamic>) {
          final fullName = personalInfo['fullName'];
          if (fullName is String && fullName.isNotEmpty) {
            if (mounted) {
              setState(() {
                _clientName = fullName;
              });
            }
            return;
          }
        }
      }

      if (mounted) {
        setState(() {
          _clientName = 'dashboard.client'.tr();
        });
      }
    } catch (e) {
      debugPrint('Error loading client name: $e');
      if (mounted) {
        setState(() {
          _clientName = 'dashboard.client'.tr();
        });
      }
    }
  }

  Future<void> _placeBid() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('bid.valid_amount_required'.tr()),
          backgroundColor: CColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final bid = BidModel(
        jobId: widget.job.id!,
        workerId: widget.workerId,
        clientId: widget.job.clientId,
        amount: amount,
        message: _messageController.text.isNotEmpty ? _messageController.text : null,
        createdAt: Timestamp.now(),
      );

      await _bidService.createBid(bid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('bid.bid_placed'.tr()),
            backgroundColor: CColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onBidPlaced();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('bid.place_failed'.tr(args: [e.toString()])),
            backgroundColor: CColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'open':
        return 'job.status_open'.tr();
      case 'in-progress':
        return 'job.status_in_progress'.tr();
      case 'completed':
        return 'job.status_completed'.tr();
      case 'cancelled':
        return 'job.status_cancelled'.tr();
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return CColors.success;
      case 'in-progress':
        return CColors.warning;
      case 'completed':
        return CColors.info;
      case 'cancelled':
        return CColors.error;
      default:
        return CColors.grey;
    }
  }

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
              title: 'job.job'.tr(), // Changed to just "Job"
              showBackButton: true,
              onBackPressed: () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildJobDetailsCard(context, isDark, isUrdu),
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildBidForm(context, isDark, isUrdu),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobDetailsCard(BuildContext context, bool isDark, bool isUrdu) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        color: isDark ? CColors.darkContainer : CColors.white,
        border: Border.all(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(widget.job.status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getStatusText(widget.job.status),
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: _getStatusColor(widget.job.status),
                    fontWeight: FontWeight.w600,
                    fontSize: isUrdu ? 12 : 10,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: CColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.job.category,
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: CColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: isUrdu ? 12 : 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            widget.job.title,
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? CColors.textWhite : CColors.textPrimary,
              fontSize: isUrdu ? 24 : 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.job.description,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: isDark ? CColors.textWhite.withOpacity(0.8) : CColors.darkerGrey,
              height: 1.5,
              fontSize: isUrdu ? 16 : 14,
            ),
          ),
          const SizedBox(height: 16),
          // Fixed overflow issue with Wrap instead of Row
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_outline, size: 16, color: CColors.darkGrey),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${'job.posted_by'.tr()}: $_clientName',
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: CColors.darkGrey,
                        fontSize: isUrdu ? 14 : 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time_outlined, size: 16, color: CColors.darkGrey),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      timeago.format(widget.job.createdAt.toDate()),
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: CColors.darkGrey,
                        fontSize: isUrdu ? 14 : 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBidForm(BuildContext context, bool isDark, bool isUrdu) {
    if (_hasExistingBid) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(CSizes.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          color: CColors.success.withOpacity(0.1),
          border: Border.all(color: CColors.success.withOpacity(0.3)),
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
              'bid.already_placed_message'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: isDark ? CColors.textWhite.withOpacity(0.8) : CColors.darkerGrey,
                fontSize: isUrdu ? 16 : 14,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.job.status != 'open') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(CSizes.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          color: CColors.warning.withOpacity(0.1),
          border: Border.all(color: CColors.warning.withOpacity(0.3)),
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
                color: isDark ? CColors.textWhite.withOpacity(0.8) : CColors.darkerGrey,
                fontSize: isUrdu ? 16 : 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'bid.place_your_bid'.tr(),
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark ? CColors.textWhite : CColors.textPrimary,
            fontSize: isUrdu ? 22 : 20,
          ),
        ),
        const SizedBox(height: CSizes.spaceBtwItems),
        Container(
          padding: const EdgeInsets.all(CSizes.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
            color: isDark ? CColors.darkContainer : CColors.white,
            border: Border.all(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                    borderSide: BorderSide(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
                  ),
                  labelStyle: TextStyle(fontSize: isUrdu ? 16 : 14),
                  hintStyle: TextStyle(fontSize: isUrdu ? 14 : 12),
                ),
                style: TextStyle(fontSize: isUrdu ? 16 : 14),
              ),
              const SizedBox(height: CSizes.spaceBtwInputFields),
              TextField(
                controller: _messageController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'bid.message_label'.tr(),
                  hintText: 'bid.message_hint'.tr(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                    borderSide: BorderSide(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
                  ),
                  labelStyle: TextStyle(fontSize: isUrdu ? 16 : 14),
                  hintStyle: TextStyle(fontSize: isUrdu ? 14 : 12),
                ),
                style: TextStyle(fontSize: isUrdu ? 16 : 14),
              ),
              const SizedBox(height: CSizes.spaceBtwSections),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _placeBid,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: CSizes.md),
                    backgroundColor: CColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
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
}