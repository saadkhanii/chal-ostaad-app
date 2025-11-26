// lib/features/worker/screens/worker_job_details_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/models/job_model.dart';
import '../../../core/models/bid_model.dart';
import '../../../core/services/bid_service.dart';

class WorkerJobDetailsScreen extends StatefulWidget {
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
  State<WorkerJobDetailsScreen> createState() => _WorkerJobDetailsScreenState();
}

class _WorkerJobDetailsScreenState extends State<WorkerJobDetailsScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final BidService _bidService = BidService();
  bool _isLoading = false;
  bool _hasExistingBid = false;
  String _clientName = 'Loading...';

  @override
  void initState() {
    super.initState();
    _checkExistingBid();
    _loadClientName();
  }

  Future<void> _checkExistingBid() async {
    try {
      final hasBid = await _bidService.hasWorkerBidOnJob(widget.workerId, widget.job.id!);
      setState(() {
        _hasExistingBid = hasBid;
      });
    } catch (e) {
      debugPrint('Error checking existing bid: $e');
    }
  }

  // In worker_job_details_screen.dart, update the client name loading:

  Future<void> _loadClientName() async {
    try {
      final clientDoc = await FirebaseFirestore.instance.collection('clients').doc(widget.job.clientId).get();

      if (clientDoc.exists) {
        final clientData = clientDoc.data()!;
        final personalInfo = clientData['personalInfo'];
        if (personalInfo is Map<String, dynamic>) {
          final fullName = personalInfo['fullName'];
          if (fullName is String && fullName.isNotEmpty) {
            setState(() {
              _clientName = fullName;
            });
            return;
          }
        }
      }

      setState(() {
        _clientName = 'Client';
      });
    } catch (e) {
      debugPrint('Error loading client name: $e');
      setState(() {
        _clientName = 'Client';
      });
    }
  }

  Future<void> _placeBid() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid bid amount'),
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
          const SnackBar(
            content: Text('Bid placed successfully!'),
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
            content: Text('Failed to place bid: $e'),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Details'),
        backgroundColor: CColors.primary,
        foregroundColor: CColors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(CSizes.defaultSpace),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Job Details Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(CSizes.lg),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
                color: isDark ? CColors.darkContainer : CColors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(color: isDark ? CColors.darkerGrey : Colors.transparent),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status and Category Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getStatusColor(widget.job.status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: _getStatusColor(widget.job.status),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.job.status.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                                color: _getStatusColor(widget.job.status),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: CColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.category_rounded, size: 14, color: CColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              widget.job.category,
                              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                                color: CColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Job Title
                  Text(
                    widget.job.title,
                    style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isDark ? CColors.textWhite : CColors.textPrimary,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Job Description
                  Text(
                    widget.job.description,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: isDark ? CColors.textWhite.withOpacity(0.8) : CColors.darkerGrey,
                      height: 1.6,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Job Meta Information
                  Container(
                    padding: const EdgeInsets.all(CSizes.md),
                    decoration: BoxDecoration(
                      color: isDark ? CColors.darkerGrey.withOpacity(0.3) : CColors.lightContainer,
                      borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
                    ),
                    child: Column(
                      children: [
                        // Posted Time
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded, size: 18, color: CColors.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Posted ${timeago.format(widget.job.createdAt.toDate())}',
                              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                                color: CColors.darkGrey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Client Name
                        Row(
                          children: [
                            Icon(Icons.person_rounded, size: 18, color: CColors.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Posted by: $_clientName',
                              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                                color: CColors.darkGrey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: CSizes.spaceBtwSections),

            // Bid Form Section
            if (!_hasExistingBid && widget.job.status == 'open') ...[
              Text(
                'Place Your Bid',
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? CColors.textWhite : CColors.textPrimary,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: CSizes.spaceBtwItems),

              Container(
                padding: const EdgeInsets.all(CSizes.lg),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
                  color: isDark ? CColors.darkContainer : CColors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  border: Border.all(color: isDark ? CColors.darkerGrey : Colors.transparent),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _amountController,
                      decoration: InputDecoration(
                        labelText: 'Bid Amount (PKR)',
                        prefixText: 'Rs. ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                          borderSide: BorderSide(color: CColors.borderPrimary),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                          borderSide: BorderSide(color: CColors.primary),
                        ),
                        labelStyle: TextStyle(color: CColors.darkGrey),
                      ),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: CSizes.lg),
                    TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        labelText: 'Message to Client (Optional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                          borderSide: BorderSide(color: CColors.borderPrimary),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                          borderSide: BorderSide(color: CColors.primary),
                        ),
                        alignLabelWithHint: true,
                        labelStyle: TextStyle(color: CColors.darkGrey),
                      ),
                      maxLines: 3,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: CSizes.lg),
                    SizedBox(
                      width: double.infinity,
                      child: _isLoading
                          ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(CColors.primary),
                        ),
                      )
                          : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [CColors.primary, CColors.secondary],
                          ),
                          borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
                          boxShadow: [
                            BoxShadow(
                              color: CColors.primary.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _placeBid,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: CColors.white,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
                            ),
                          ),
                          child: const Text(
                            'Submit Bid',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_hasExistingBid) ...[
              Container(
                padding: const EdgeInsets.all(CSizes.lg),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
                  color: CColors.info.withOpacity(0.1),
                  border: Border.all(color: CColors.info),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: CColors.info),
                    const SizedBox(width: CSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bid Already Placed',
                            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                              color: CColors.info,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'You have already submitted a bid for this job.',
                            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              color: CColors.info.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (widget.job.status != 'open') ...[
              Container(
                padding: const EdgeInsets.all(CSizes.lg),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
                  color: CColors.warning.withOpacity(0.1),
                  border: Border.all(color: CColors.warning),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_clock_rounded, color: CColors.warning),
                    const SizedBox(width: CSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Job Not Accepting Bids',
                            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                              color: CColors.warning,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'This job is no longer accepting new bids.',
                            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              color: CColors.warning.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}