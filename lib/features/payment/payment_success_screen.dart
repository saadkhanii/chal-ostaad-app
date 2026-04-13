// lib/features/payment/payment_success_screen.dart
import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/routes/app_routes.dart';

class PaymentSuccessScreen extends StatefulWidget {
  final String jobTitle;
  final double amount;
  final String paymentId;

  const PaymentSuccessScreen({
    super.key,
    required this.jobTitle,
    required this.amount,
    required this.paymentId,
  });

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scaleAnim;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fadeAnim  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final usdAmount  = widget.amount / 280;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CSizes.defaultSpace),
          child: Column(
            children: [
              const Spacer(),

              // ── Success icon ────────────────────────────────
              FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width:  120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape:  BoxShape.circle,
                      color:  CColors.success.withOpacity(0.12),
                      border: Border.all(
                          color: CColors.success.withOpacity(0.4), width: 3),
                    ),
                    child: const Icon(Icons.check_circle_rounded,
                        color: CColors.success, size: 70),
                  ),
                ),
              ),

              const SizedBox(height: CSizes.lg),

              FadeTransition(
                opacity: _fadeAnim,
                child: Column(children: [
                  Text('Payment Successful!',
                      style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                        fontWeight: FontWeight.bold,
                        color:      CColors.success,
                      )),
                  const SizedBox(height: CSizes.sm),
                  Text('Your payment has been processed via Stripe.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? CColors.textWhite.withOpacity(0.7)
                              : CColors.darkGrey)),
                ]),
              ),

              const SizedBox(height: CSizes.spaceBtwSections),

              // ── Receipt ─────────────────────────────────────
              FadeTransition(
                opacity: _fadeAnim,
                child: Container(
                  width:   double.infinity,
                  padding: const EdgeInsets.all(CSizes.lg),
                  decoration: BoxDecoration(
                    color:        isDark ? CColors.darkContainer : CColors.white,
                    borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
                    boxShadow: isDark ? [] : [
                      BoxShadow(color: Colors.black.withOpacity(0.06),
                          blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(children: [
                    // Stripe badge
                    Container(
                      padding:    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color:        CColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border:       Border.all(color: CColors.primary.withOpacity(0.3)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.credit_card_rounded, color: CColors.primary, size: 16),
                        SizedBox(width: 6),
                        Text('Stripe', style: TextStyle(
                            color: CColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                      ]),
                    ),
                    const SizedBox(height: CSizes.md),

                    // Amount
                    Text('Rs. ${widget.amount.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                            fontWeight: FontWeight.bold, color: CColors.primary)),
                    Text('(\$${usdAmount.toStringAsFixed(2)} USD)',
                        style: const TextStyle(fontSize: 12, color: CColors.darkGrey)),

                    const SizedBox(height: CSizes.md),
                    Divider(color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
                    const SizedBox(height: CSizes.sm),

                    _receiptRow('Job',           widget.jobTitle,  isDark),
                    const SizedBox(height: CSizes.sm),
                    _receiptRow('Payment ID',    widget.paymentId.substring(0, 12) + '...', isDark, isSmall: true),
                    const SizedBox(height: CSizes.sm),
                    _receiptRow('Status',        'Paid via Stripe ✓', isDark,
                        valueColor: CColors.success),
                  ]),
                ),
              ),

              const Spacer(),

              // ── Buttons ──────────────────────────────────────
              FadeTransition(
                opacity: _fadeAnim,
                child: Column(children: [
                  SizedBox(
                    width:  double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(
                          context, AppRoutes.clientDashboard, (r) => false),
                      icon:  const Icon(Icons.home_rounded),
                      label: const Text('Go to Dashboard'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
                      ),
                    ),
                  ),
                  const SizedBox(height: CSizes.sm),
                  SizedBox(
                    width:  double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(
                          context, AppRoutes.wallet, (r) => false),
                      icon:  const Icon(Icons.account_balance_wallet_rounded),
                      label: const Text('View Payment History'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CColors.primary,
                        side:  const BorderSide(color: CColors.primary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: CSizes.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value, bool isDark,
      {Color? valueColor, bool isSmall = false}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 2,
          child: Text(label, style: TextStyle(fontSize: 13,
              color: isDark ? CColors.textWhite.withOpacity(0.6) : CColors.darkGrey))),
      Expanded(flex: 3,
          child: Text(value, textAlign: TextAlign.end,
              style: TextStyle(
                  fontSize:   isSmall ? 11 : 13,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? (isDark ? CColors.textWhite : CColors.textPrimary)))),
    ]);
  }
}