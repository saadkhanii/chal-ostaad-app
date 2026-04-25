// lib/features/payment/payment_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/job_model.dart';
import '../../core/services/payment_service.dart';
import '../../shared/widgets/common_header.dart';
import 'payment_success_screen.dart';

class PaymentScreen extends StatefulWidget {
  final String jobId;
  final String jobTitle;
  final String clientId;
  final String workerId;
  final double amount; // base bid amount

  const PaymentScreen({
    super.key,
    required this.jobId,
    required this.jobTitle,
    required this.clientId,
    required this.workerId,
    required this.amount,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _paymentService = PaymentService();
  bool _isProcessing = false;

  // Selected payment method: 'stripe' | 'cash'
  String _selectedMethod = 'stripe';

  // ── FIX: stream-based approved extra charges ──────────────────────
  // Instead of a one-time get() in initState(), we watch the job doc
  // in real time so the total updates the moment a charge is approved.
  late final Stream<List<Map<String, dynamic>>> _extrasStream;

  // Snapshot of latest approved charges — kept in state so _pay() can
  // read the current value without needing to re-await the stream.
  List<Map<String, dynamic>> _approvedExtraCharges = [];

  @override
  void initState() {
    super.initState();
    _extrasStream = FirebaseFirestore.instance
        .collection('jobs')
        .doc(widget.jobId)
        .snapshots()
        .map((snap) {
      final raw = snap.data()?['extraCharges'] as List<dynamic>? ?? [];
      return raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((c) => c['status'] == 'approved')
          .toList();
    });
  }

  // ── Derived totals (computed from latest stream data) ─────────────
  double get _extrasTotal => _approvedExtraCharges.fold<double>(
      0, (s, c) => s + ((c['amount'] as num?)?.toDouble() ?? 0));

  double get _grandTotal   => widget.amount + _extrasTotal;
  double get _platformFee  => PaymentService.calcPlatformFee(_grandTotal);

  Future<void> _pay() async {
    setState(() => _isProcessing = true);

    try {
      String paymentId;

      if (_selectedMethod == 'stripe') {
        paymentId = await _paymentService.processStripePayment(
          amount:   _grandTotal,
          jobId:    widget.jobId,
          clientId: widget.clientId,
          workerId: widget.workerId,
          jobTitle: widget.jobTitle,
        );
      } else {
        // Cash — record intent; worker will confirm receipt
        paymentId = await _paymentService.recordCashPaymentIntent(
          amount:   _grandTotal,
          jobId:    widget.jobId,
          jobTitle: widget.jobTitle,
          clientId: widget.clientId,
          workerId: widget.workerId,
        );
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentSuccessScreen(
            jobTitle:  widget.jobTitle,
            amount:    _grandTotal,
            paymentId: paymentId,
            isCash:    _selectedMethod == 'cash',
          ),
        ),
      );
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        setState(() => _isProcessing = false);
        return;
      }
      _showError(e.error.localizedMessage ?? 'Payment failed');
      setState(() => _isProcessing = false);
    } catch (e) {
      _showError(e.toString());
      setState(() => _isProcessing = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg),
      backgroundColor: CColors.error,
      behavior:        SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title:          'Payment',
            showBackButton: true,
            onBackPressed:  () => Navigator.pop(context),
          ),

          // ── FIX: StreamBuilder replaces the old _loadingExtras flag ──
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _extrasStream,
              builder: (context, snapshot) {
                // Keep state in sync so _pay() can read current totals
                if (snapshot.hasData &&
                    snapshot.data != _approvedExtraCharges) {
                  // Schedule a micro-task so we don't setState during build
                  Future.microtask(() {
                    if (mounted) {
                      setState(() =>
                      _approvedExtraCharges = snapshot.data!);
                    }
                  });
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Use the snapshot data directly for this build frame
                final charges   = snapshot.data!;
                final extrasTot = charges.fold<double>(
                    0, (s, c) => s + ((c['amount'] as num?)?.toDouble() ?? 0));
                final grandTot  = widget.amount + extrasTot;
                final platFee   = PaymentService.calcPlatformFee(grandTot);

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(CSizes.defaultSpace),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Order Summary ────────────────────────────
                      _buildCard(isDark,
                          child: _buildSummarySection(
                              isDark, charges, extrasTot, grandTot, platFee)),

                      const SizedBox(height: CSizes.spaceBtwItems),

                      // ── Approved Extra Charges ───────────────────
                      if (charges.isNotEmpty) ...[
                        _buildCard(isDark,
                            child: _buildExtrasSection(isDark, charges)),
                        const SizedBox(height: CSizes.spaceBtwItems),
                      ],

                      // ── Payment Method ───────────────────────────
                      _buildCard(isDark,
                          child: _buildMethodSelector(isDark)),

                      const SizedBox(height: CSizes.spaceBtwItems),

                      // ── Stripe test hint ─────────────────────────
                      if (_selectedMethod == 'stripe') _buildStripeHint(),

                      if (_selectedMethod == 'cash')
                        _buildCashInfo(isDark),

                      const SizedBox(height: CSizes.spaceBtwItems),

                      // ── Security note ────────────────────────────
                      if (_selectedMethod == 'stripe') _buildSecurityNote(),

                      const SizedBox(height: CSizes.spaceBtwSections),

                      // ── Pay button ───────────────────────────────
                      _buildPayButton(isDark, grandTot),

                      const SizedBox(height: CSizes.md),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Order summary ──────────────────────────────────────────────────
  Widget _buildSummarySection(
      bool isDark,
      List<Map<String, dynamic>> charges,
      double extrasTot,
      double grandTot,
      double platFee,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding:    const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color:        CColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.receipt_long_rounded,
                color: CColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment Summary',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize:   15,
                          color: isDark ? CColors.textWhite : CColors.textPrimary)),
                  Text(widget.jobTitle,
                      style:    const TextStyle(
                          fontSize: 12, color: CColors.darkGrey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              )),
        ]),
        const SizedBox(height: CSizes.md),
        Divider(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
        const SizedBox(height: CSizes.sm),
        _row('Base Bid', 'Rs. ${widget.amount.toStringAsFixed(0)}', isDark),
        // ── FIX: show approved extras total in the summary ────────────
        if (extrasTot > 0) ...[
          const SizedBox(height: 6),
          _row('Approved Extras',
              'Rs. ${extrasTot.toStringAsFixed(0)}', isDark,
              valueColor: CColors.warning),
        ],
        const SizedBox(height: 6),
        _row(
          'Platform Fee (${PaymentService.platformFeePercent.toStringAsFixed(0)}%)',
          'Rs. ${platFee.toStringAsFixed(0)}',
          isDark,
          valueColor: CColors.error,
        ),
        const SizedBox(height: CSizes.sm),
        Divider(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
        const SizedBox(height: CSizes.sm),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Total',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? CColors.textWhite : CColors.textPrimary)),
          Text('Rs. ${grandTot.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize:   20,
                  color:      CColors.primary)),
        ]),
      ],
    );
  }

  // ── Approved extra charges list ────────────────────────────────────
  Widget _buildExtrasSection(
      bool isDark, List<Map<String, dynamic>> charges) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.add_circle_outline,
              color: CColors.warning, size: 18),
          const SizedBox(width: 8),
          Text('Approved Extra Charges',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize:   14,
                  color: isDark ? CColors.textWhite : CColors.textPrimary)),
        ]),
        const SizedBox(height: CSizes.sm),
        ...charges.map((c) {
          final amt  = (c['amount']     as num?)?.toDouble() ?? 0;
          final desc = c['description'] as String? ?? '';
          final by   = c['requestedBy'] as String? ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(desc,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 2),
                        Text('Requested by $by',
                            style: const TextStyle(
                                fontSize: 11, color: CColors.darkGrey)),
                      ]),
                ),
                Text('Rs. ${amt.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color:      CColors.warning)),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ── Payment method selector ────────────────────────────────────────
  Widget _buildMethodSelector(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment Method',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize:   14,
                color: isDark ? CColors.textWhite : CColors.textPrimary)),
        const SizedBox(height: CSizes.sm),
        Row(children: [
          Expanded(
              child: _methodTile(
                isDark:  isDark,
                method:  'stripe',
                icon:    Icons.credit_card_rounded,
                label:   'Online (Stripe)',
                caption: 'Visa / MasterCard',
              )),
          const SizedBox(width: 12),
          Expanded(
              child: _methodTile(
                isDark:  isDark,
                method:  'cash',
                icon:    Icons.payments_outlined,
                label:   'Cash',
                caption: 'Pay in person',
              )),
        ]),
      ],
    );
  }

  Widget _methodTile({
    required bool   isDark,
    required String method,
    required IconData icon,
    required String label,
    required String caption,
  }) {
    final selected = _selectedMethod == method;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method),
      child: AnimatedContainer(
        duration:    const Duration(milliseconds: 200),
        padding:     const EdgeInsets.all(14),
        decoration:  BoxDecoration(
          color:        selected
              ? CColors.primary.withOpacity(0.08)
              : isDark
              ? CColors.darkContainer.withOpacity(0.4)
              : Colors.grey.withOpacity(0.06),
          borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
          border:       Border.all(
            color: selected
                ? CColors.primary
                : (isDark ? CColors.darkerGrey : CColors.borderPrimary),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(children: [
          Icon(icon,
              color: selected ? CColors.primary : CColors.darkGrey, size: 28),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize:   13,
                  color:      selected
                      ? CColors.primary
                      : (isDark ? CColors.textWhite : CColors.textPrimary))),
          Text(caption,
              style:     const TextStyle(
                  fontSize: 10, color: CColors.darkGrey),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  // ── Stripe test hint ───────────────────────────────────────────────
  Widget _buildStripeHint() {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color:        Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        border:       Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
            SizedBox(width: 8),
            Text('Test Mode — Use these details:',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color:      Colors.amber,
                    fontSize:   13)),
          ]),
          const SizedBox(height: CSizes.sm),
          _hint('Card',   '4242 4242 4242 4242'),
          _hint('Expiry', 'Any future date'),
          _hint('CVC',    'Any 3 digits'),
          _hint('ZIP',    'Any 5 digits'),
        ],
      ),
    );
  }

  // ── Cash info banner ───────────────────────────────────────────────
  Widget _buildCashInfo(bool isDark) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color:        CColors.info.withOpacity(0.08),
        borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        border:       Border.all(color: CColors.info.withOpacity(0.3)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.payments_outlined, color: CColors.info, size: 18),
            SizedBox(width: 8),
            Text('How Cash Payment Works',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color:      CColors.info,
                    fontSize:   13)),
          ]),
          SizedBox(height: 10),
          _CashStep(num: '1', text: 'Tap "Pay Now" — this records your intent to pay cash.'),
          _CashStep(num: '2', text: 'Hand the cash to the worker after the job is done.'),
          _CashStep(
              num:  '3',
              text: 'The worker confirms receipt in their app, and the job is marked complete.'),
        ],
      ),
    );
  }

  // ── Security note ──────────────────────────────────────────────────
  Widget _buildSecurityNote() {
    return Container(
      padding:    const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color:        CColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        border:       Border.all(color: CColors.success.withOpacity(0.3)),
      ),
      child: const Row(children: [
        Icon(Icons.lock_rounded, color: CColors.success, size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Powered by Stripe. Card details are encrypted and never stored.',
            style: TextStyle(fontSize: 12, color: CColors.success),
          ),
        ),
      ]),
    );
  }

  // ── Pay button ─────────────────────────────────────────────────────
  Widget _buildPayButton(bool isDark, double grandTot) {
    final label = _selectedMethod == 'cash'
        ? 'Confirm Cash Payment — Rs. ${grandTot.toStringAsFixed(0)}'
        : 'Pay Now — Rs. ${grandTot.toStringAsFixed(0)}';

    return SizedBox(
      width:  double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isProcessing ? null : _pay,
        style: ElevatedButton.styleFrom(
          backgroundColor:         CColors.primary,
          foregroundColor:         Colors.white,
          disabledBackgroundColor: CColors.primary.withOpacity(0.6),
          shape: RoundedRectangleBorder(
              borderRadius:
              BorderRadius.circular(CSizes.borderRadiusLg)),
          elevation: 3,
        ),
        child: _isProcessing
            ? const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
                width:  20,
                height: 20,
                child:  CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5)),
            SizedBox(width: 12),
            Text('Processing...',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        )
            : Text(label,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────
  Widget _buildCard(bool isDark, {required Widget child}) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        boxShadow: isDark
            ? []
            : [
          BoxShadow(
              color:      Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset:     const Offset(0, 4))
        ],
      ),
      child: child,
    );
  }

  Widget _row(String label, String value, bool isDark,
      {Color? valueColor, String? note}) {
    return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    color: isDark
                        ? CColors.textWhite.withOpacity(0.7)
                        : CColors.darkGrey)),
            if (note != null)
              Text(note,
                  style: const TextStyle(
                      fontSize: 10, color: CColors.darkGrey)),
          ]),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w500, color: valueColor)),
        ]);
  }

  Widget _hint(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: CColors.darkGrey))),
        Text(value,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Cash step helper ───────────────────────────────────────────────────
class _CashStep extends StatelessWidget {
  final String num;
  final String text;
  const _CashStep({required this.num, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width:      22,
            height:     22,
            margin:     const EdgeInsets.only(right: 8, top: 1),
            decoration: const BoxDecoration(
                color:  CColors.info, shape: BoxShape.circle),
            child: Center(
              child: Text(num,
                  style: const TextStyle(
                      color:      Colors.white,
                      fontSize:   11,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12, color: CColors.darkGrey))),
        ],
      ),
    );
  }
}