// lib/features/payment/wallet_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/payment_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/payment_service.dart';
import '../../shared/widgets/common_header.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  final _paymentService = PaymentService();

  String _userId   = '';
  String _userRole = 'client';
  bool   _loading  = true;

  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadUser();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userId   = prefs.getString('user_uid')  ?? '';
        _userRole = prefs.getString('user_role') ?? 'client';
        _loading  = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title:          'Wallet',
            showBackButton: true,
            onBackPressed:  () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushReplacementNamed(context, AppRoutes.clientDashboard);
              }
            },
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_userId.isEmpty)
            const Expanded(
                child: Center(child: Text('Please log in to view wallet')))
          else
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(CSizes.defaultSpace),
                    child: _buildSummaryCard(isDark),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: CSizes.defaultSpace),
                    decoration: BoxDecoration(
                      color: isDark ? CColors.darkContainer : CColors.white,
                      borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                    ),
                    child: TabBar(
                      controller:          _tabCtrl,
                      indicatorSize:       TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color:        CColors.primary,
                        borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                      ),
                      labelColor:          Colors.white,
                      unselectedLabelColor: CColors.darkGrey,
                      tabs: const [
                        Tab(text: 'Payments'),
                        Tab(text: 'Transactions'),
                      ],
                    ),
                  ),
                  const SizedBox(height: CSizes.sm),
                  Expanded(
                    child: TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _buildPaymentsList(isDark),
                        _buildTransactionsList(isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(bool isDark) {
    final stream = _userRole == 'client'
        ? _paymentService.streamPaymentsByClient(_userId)
        : _paymentService.streamPaymentsByWorker(_userId);

    return StreamBuilder<List<PaymentModel>>(
      stream: stream,
      builder: (context, snapshot) {
        final payments = snapshot.data ?? [];
        final total    = payments.fold<double>(
            0, (sum, p) => sum + (p.status == 'completed' ? p.amount : 0));
        final count    = payments.where((p) => p.status == 'completed').length;

        return Container(
          width:   double.infinity,
          padding: const EdgeInsets.all(CSizes.lg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin:  Alignment.topLeft,
              end:    Alignment.bottomRight,
              colors: [CColors.primary, CColors.primary.withOpacity(0.75)],
            ),
            borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
            boxShadow: [
              BoxShadow(
                color:      CColors.primary.withOpacity(0.3),
                blurRadius: 12,
                offset:     const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Text(
                  _userRole == 'client' ? 'Total Payments Made' : 'Total Earnings',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ]),
              const SizedBox(height: CSizes.sm),
              Text('Rs. ${total.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:        Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(children: [
                    Icon(Icons.credit_card_rounded, color: Colors.white70, size: 12),
                    SizedBox(width: 4),
                    Text('Stripe',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(
                  '$count ${_userRole == 'client' ? 'payments' : 'jobs paid'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaymentsList(bool isDark) {
    final stream = _userRole == 'client'
        ? _paymentService.streamPaymentsByClient(_userId)
        : _paymentService.streamPaymentsByWorker(_userId);

    return StreamBuilder<List<PaymentModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final payments = snapshot.data ?? [];
        if (payments.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 64,
                    color: isDark ? CColors.darkerGrey : CColors.grey),
                const SizedBox(height: CSizes.md),
                Text('No payments yet',
                    style: TextStyle(
                        fontSize: 16,
                        color: isDark ? CColors.darkGrey : CColors.darkerGrey)),
                const SizedBox(height: CSizes.sm),
                Text(
                  _userRole == 'client'
                      ? 'Accept a bid and make your first payment'
                      : 'Payments will appear here once clients pay you',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: CColors.darkGrey),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding:     const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
          itemCount:   payments.length,
          itemBuilder: (context, i) => _buildPaymentCard(payments[i], isDark),
        );
      },
    );
  }

  Widget _buildTransactionsList(bool isDark) {
    final stream = _userRole == 'client'
        ? _paymentService.streamPaymentsByClient(_userId)
        : _paymentService.streamPaymentsByWorker(_userId);

    return StreamBuilder<List<PaymentModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final payments = snapshot.data ?? [];
        if (payments.isEmpty) {
          return const Center(child: Text('No transactions found'));
        }
        return ListView.builder(
          padding:     const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
          itemCount:   payments.length,
          itemBuilder: (context, i) => _buildTransactionTile(payments[i], isDark),
        );
      },
    );
  }

  Widget _buildPaymentCard(PaymentModel payment, bool isDark) {
    final dateStr = payment.createdAt != null
        ? DateFormat('dd MMM yyyy').format(payment.createdAt!.toDate())
        : '—';

    Color  statusColor;
    String statusLabel;
    switch (payment.status) {
      case 'completed':
        statusColor = CColors.success; statusLabel = 'Paid'; break;
      case 'failed':
        statusColor = CColors.error;   statusLabel = 'Failed'; break;
      default:
        statusColor = CColors.warning; statusLabel = 'Pending';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: CSizes.sm),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusMd)),
      color: isDark ? CColors.darkContainer : CColors.white,
      child: Padding(
        padding: const EdgeInsets.all(CSizes.md),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color:        CColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Icon(Icons.credit_card_rounded,
                  color: CColors.primary, size: 22),
            ),
          ),
          const SizedBox(width: CSizes.md),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(payment.jobTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('Stripe · $dateStr',
                  style: const TextStyle(fontSize: 12, color: CColors.darkGrey)),
            ],
          )),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Rs. ${payment.amount.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: CColors.primary, fontSize: 15)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color:        statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(statusLabel,
                  style: TextStyle(
                      color: statusColor, fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildTransactionTile(PaymentModel payment, bool isDark) {
    final dateStr = payment.createdAt != null
        ? DateFormat('dd MMM yy, hh:mm a').format(payment.createdAt!.toDate())
        : '—';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: CColors.primary.withOpacity(0.1),
        child: const Icon(Icons.payment_rounded, color: CColors.primary, size: 20),
      ),
      title: Text(payment.jobTitle,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Via Stripe',
            style: TextStyle(fontSize: 11, color: CColors.darkGrey)),
        Text(dateStr,
            style: const TextStyle(fontSize: 11, color: CColors.darkGrey)),
      ]),
      trailing: Text('Rs. ${payment.amount.toStringAsFixed(0)}',
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: CColors.primary)),
    );
  }
}