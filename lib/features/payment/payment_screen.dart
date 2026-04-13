// lib/features/payment/payment_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/services/payment_service.dart';
import '../../shared/widgets/common_header.dart';
import 'payment_success_screen.dart';

class PaymentScreen extends StatefulWidget {
  final String jobId;
  final String jobTitle;
  final String clientId;
  final String workerId;
  final double amount;

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

  Future<void> _pay() async {
    setState(() => _isProcessing = true);

    try {
      final paymentId = await _paymentService.processStripePayment(
        amount:   widget.amount,
        jobId:    widget.jobId,
        clientId: widget.clientId,
        workerId: widget.workerId,
        jobTitle: widget.jobTitle,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentSuccessScreen(
            jobTitle:  widget.jobTitle,
            amount:    widget.amount,
            paymentId: paymentId,
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
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final usdAmount  = widget.amount / 280;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title:          'Payment',
            showBackButton: true,
            onBackPressed:  () => Navigator.pop(context),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Column(
                children: [
                  // Order summary
                  _buildCard(isDark, child: Column(
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
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Payment Summary',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15,
                                  color: isDark ? CColors.textWhite : CColors.textPrimary,
                                )),
                            Text(widget.jobTitle,
                                style: const TextStyle(fontSize: 12, color: CColors.darkGrey),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        )),
                      ]),
                      const SizedBox(height: CSizes.md),
                      Divider(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
                      const SizedBox(height: CSizes.sm),
                      _row('Service Amount', 'Rs. ${widget.amount.toStringAsFixed(0)}', isDark),
                      const SizedBox(height: 6),
                      _row('Stripe charges (USD)', '\$${usdAmount.toStringAsFixed(2)}', isDark,
                          note: '1 USD ≈ 280 PKR'),
                      const SizedBox(height: 6),
                      _row('Platform Fee', 'Free', isDark, valueColor: CColors.success),
                      const SizedBox(height: CSizes.sm),
                      Divider(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
                      const SizedBox(height: CSizes.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total', style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16,
                              color: isDark ? CColors.textWhite : CColors.textPrimary)),
                          Text('\$${usdAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20, color: CColors.primary)),
                        ],
                      ),
                    ],
                  )),

                  const SizedBox(height: CSizes.spaceBtwItems),

                  // Test card hint
                  Container(
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
                              style: TextStyle(fontWeight: FontWeight.bold,
                                  color: Colors.amber, fontSize: 13)),
                        ]),
                        const SizedBox(height: CSizes.sm),
                        _hint('Card Number', '4242 4242 4242 4242'),
                        _hint('Expiry',      'Any future date  e.g. 12/26'),
                        _hint('CVC',         'Any 3 digits  e.g. 123'),
                        _hint('ZIP',         'Any 5 digits  e.g. 12345'),
                      ],
                    ),
                  ),

                  const SizedBox(height: CSizes.spaceBtwItems),

                  // Security note
                  Container(
                    padding: const EdgeInsets.all(CSizes.md),
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
                  ),

                  const SizedBox(height: CSizes.spaceBtwSections),

                  // Pay button
                  SizedBox(
                    width:  double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _pay,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:         CColors.primary,
                        foregroundColor:         Colors.white,
                        disabledBackgroundColor: CColors.primary.withOpacity(0.6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
                        elevation: 3,
                      ),
                      child: _isProcessing
                          ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5)),
                        SizedBox(width: 12),
                        Text('Processing...', style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                      ])
                          : Text(
                        'Pay Now — Rs. ${widget.amount.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: CSizes.md),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(bool isDark, {required Widget child}) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        boxShadow: isDark ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.06),
              blurRadius: 12, offset: const Offset(0, 4))
        ],
      ),
      child: child,
    );
  }

  Widget _row(String label, String value, bool isDark,
      {Color? valueColor, String? note}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(
            color: isDark ? CColors.textWhite.withOpacity(0.7) : CColors.darkGrey)),
        if (note != null)
          Text(note, style: const TextStyle(fontSize: 10, color: CColors.darkGrey)),
      ]),
      Text(value, style: TextStyle(fontWeight: FontWeight.w500, color: valueColor)),
    ]);
  }

  Widget _hint(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        SizedBox(width: 100,
            child: Text(label, style: const TextStyle(fontSize: 12, color: CColors.darkGrey))),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}