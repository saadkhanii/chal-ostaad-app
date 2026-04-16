// lib/features/payment/extra_charges_sheet.dart
//
// A bottom sheet that lets either the client or the worker:
//   • View all existing extra charges (with status badges)
//   • Propose a new extra charge
//   • Approve / reject charges proposed by the other party
//
// Usage:
//   ExtraChargesSheet.show(
//     context,
//     jobId:       job.id!,
//     currentRole: 'client',   // or 'worker'
//   );

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/services/payment_service.dart';

class ExtraChargesSheet extends StatefulWidget {
  final String jobId;
  final String currentRole; // 'client' | 'worker'

  const ExtraChargesSheet({
    super.key,
    required this.jobId,
    required this.currentRole,
  });

  static Future<void> show(
      BuildContext context, {
        required String jobId,
        required String currentRole,
      }) {
    return showModalBottomSheet(
      context:        context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExtraChargesSheet(
        jobId:       jobId,
        currentRole: currentRole,
      ),
    );
  }

  @override
  State<ExtraChargesSheet> createState() => _ExtraChargesSheetState();
}

class _ExtraChargesSheetState extends State<ExtraChargesSheet> {
  final _paymentService   = PaymentService();
  final _amountController = TextEditingController();
  final _descController   = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _addCharge() async {
    final amount = double.tryParse(_amountController.text);
    final desc   = _descController.text.trim();
    if (amount == null || amount <= 0 || desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a valid amount and description.'),
        backgroundColor: CColors.warning,
      ));
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _paymentService.addExtraCharge(
        jobId:       widget.jobId,
        amount:      amount,
        description: desc,
        requestedBy: widget.currentRole,
      );
      _amountController.clear();
      _descController.clear();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _respond(String chargeId, bool approved) async {
    await _paymentService.respondToExtraCharge(
      jobId:    widget.jobId,
      chargeId: chargeId,
      approved: approved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);

    return Container(
      height: mediaQuery.size.height * 0.82,
      decoration: BoxDecoration(
        color:        isDark ? CColors.dark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Handle ────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            width:      40,
            height:     4,
            decoration: BoxDecoration(
              color:        Colors.grey.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // ── Header ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: CSizes.defaultSpace),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Extra Charges',
                    style: TextStyle(
                        fontSize:   20,
                        fontWeight: FontWeight.bold)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(),

          // ── Body ──────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('jobs')
                  .doc(widget.jobId)
                  .snapshots(),
              builder: (context, snap) {
                final raw = (snap.data?.data()
                as Map<String, dynamic>?)?['extraCharges'];
                final charges = raw == null
                    ? <Map<String, dynamic>>[]
                    : (raw as List<dynamic>)
                    .map((e) =>
                Map<String, dynamic>.from(e as Map))
                    .toList();

                return ListView(
                  padding: const EdgeInsets.all(CSizes.defaultSpace),
                  children: [
                    // Existing charges
                    if (charges.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('No extra charges yet.',
                              style: TextStyle(color: CColors.darkGrey)),
                        ),
                      ),
                    ...charges.map((c) => _buildChargeCard(c, isDark)),

                    const SizedBox(height: CSizes.spaceBtwSections),

                    // Add new charge
                    Text('Request New Extra Charge',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize:   15,
                            color: isDark
                                ? CColors.textWhite
                                : CColors.textPrimary)),
                    const SizedBox(height: CSizes.sm),
                    Container(
                      padding:    const EdgeInsets.all(CSizes.md),
                      decoration: BoxDecoration(
                        color:        isDark
                            ? CColors.darkContainer
                            : CColors.lightGrey,
                        borderRadius:
                        BorderRadius.circular(CSizes.cardRadiusMd),
                        border: Border.all(
                            color: isDark
                                ? CColors.darkerGrey
                                : CColors.borderPrimary),
                      ),
                      child: Column(children: [
                        TextField(
                          controller:   _amountController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Amount (Rs.)',
                            prefixText: 'Rs. ',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: CSizes.sm),
                        TextField(
                          controller: _descController,
                          maxLines:   3,
                          decoration: InputDecoration(
                            labelText: 'Description',
                            hintText:  'e.g. Extra materials needed',
                            border:    OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: CSizes.sm),
                        SizedBox(
                          width:  double.infinity,
                          child:  ElevatedButton.icon(
                            onPressed: _isSaving ? null : _addCharge,
                            icon:  const Icon(Icons.add_circle_outline),
                            label: _isSaving
                                ? const SizedBox(
                                width:  16,
                                height: 16,
                                child:  CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                                : const Text('Add Charge'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChargeCard(Map<String, dynamic> charge, bool isDark) {
    final id          = charge['id']          as String? ?? '';
    final amount      = (charge['amount']     as num?)?.toDouble() ?? 0;
    final desc        = charge['description'] as String? ?? '';
    final requestedBy = charge['requestedBy'] as String? ?? '';
    final status      = charge['status']      as String? ?? 'pending';

    final isProposedByOther = requestedBy != widget.currentRole;
    final isPending         = status == 'pending';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'approved':
        statusColor  = CColors.success; statusLabel = 'Approved'; break;
      case 'rejected':
        statusColor  = CColors.error;   statusLabel = 'Rejected';  break;
      default:
        statusColor  = CColors.warning; statusLabel = 'Pending';
    }

    return Container(
      margin:     const EdgeInsets.only(bottom: CSizes.sm),
      padding:    const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border:       Border.all(
            color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Rs. ${amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize:   16,
                        color:      CColors.primary)),
                _statusBadge(statusLabel, statusColor),
              ]),
          const SizedBox(height: 4),
          Text(desc, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          Text('Requested by: $requestedBy',
              style: const TextStyle(
                  fontSize: 11, color: CColors.darkGrey)),

          // Approve / Reject — only shown to the OTHER party when pending
          if (isPending && isProposedByOther) ...[
            const SizedBox(height: CSizes.sm),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _respond(id, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CColors.error,
                    side: const BorderSide(color: CColors.error),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _respond(id, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Approve'),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding:    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color:      color,
              fontSize:   10,
              fontWeight: FontWeight.bold)),
    );
  }
}