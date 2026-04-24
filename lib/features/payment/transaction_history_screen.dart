// lib/features/payment/transaction_history_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../shared/widgets/common_header.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  String _userId = '';
  String _role   = '';
  bool   _isLoading = true;
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid   = prefs.getString('user_uid')  ?? '';
      final role  = prefs.getString('user_role') ?? 'client';

      if (uid.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Query jobs where this user was client OR worker and payment is settled
      final field = role == 'worker' ? 'acceptedWorkerId' : 'clientId';
      final snapshot = await FirebaseFirestore.instance
          .collection('jobs')
          .where(field, isEqualTo: uid)
          .where('paymentStatus', isEqualTo: 'paid')
          .orderBy('createdAt', descending: true)
          .get();

      final txns = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id':            doc.id,
          'title':         data['title']         ?? 'Job',
          'amount':        data['agreedAmount']   ?? data['bidAmount'] ?? 0.0,
          'paymentMethod': data['paymentMethod']  ?? 'N/A',
          'createdAt':     data['createdAt']      as Timestamp?,
          'status':        data['paymentStatus']  ?? 'paid',
          'role':          role, // whether current user was client or worker
        };
      }).toList();

      if (mounted) {
        setState(() {
          _userId       = uid;
          _role         = role;
          _transactions = txns;
          _isLoading    = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading transactions: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          const CommonHeader(
            title:          'Transaction History',
            showBackButton: true,
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _transactions.isEmpty
                ? _buildEmpty(isDark)
                : _buildList(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 64,
              color: isDark ? CColors.darkGrey : CColors.lightGrey),
          const SizedBox(height: 16),
          Text('No transactions yet',
              style: TextStyle(
                fontSize:   16,
                fontWeight: FontWeight.w600,
                color: isDark ? CColors.lightGrey : CColors.darkGrey,
              )),
          const SizedBox(height: 6),
          Text('Completed payments will appear here.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? CColors.darkGrey : CColors.lightGrey,
              )),
        ],
      ),
    );
  }

  Widget _buildList(bool isDark) {
    // Summary totals
    final total = _transactions.fold<double>(
        0, (sum, t) => sum + (t['amount'] as num).toDouble());

    return ListView(
      padding: const EdgeInsets.all(CSizes.defaultSpace),
      children: [

        // ── Summary card ──────────────────────────────────────────
        Container(
          width:   double.infinity,
          padding: const EdgeInsets.all(CSizes.lg),
          decoration: BoxDecoration(
            gradient:     LinearGradient(
                colors: [CColors.primary, CColors.secondary]),
            borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Total Transacted',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text('Rs. ${total.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color:      Colors.white,
                      fontSize:   24,
                      fontWeight: FontWeight.bold,
                    )),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text('Transactions',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text('${_transactions.length}',
                    style: const TextStyle(
                      color:      Colors.white,
                      fontSize:   24,
                      fontWeight: FontWeight.bold,
                    )),
              ]),
            ],
          ),
        ),

        const SizedBox(height: CSizes.spaceBtwItems),

        // ── Transaction list ──────────────────────────────────────
        ..._transactions.map((txn) => _buildTxnCard(txn, isDark)),
      ],
    );
  }

  Widget _buildTxnCard(Map<String, dynamic> txn, bool isDark) {
    final isWorker  = txn['role'] == 'worker';
    final amount    = (txn['amount'] as num).toDouble();
    final timestamp = txn['createdAt'] as Timestamp?;
    final method    = txn['paymentMethod'] as String;
    final isCash    = method == 'cash';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
      ),
      child: Row(children: [
        // Icon
        Container(
          padding:    const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isWorker ? CColors.success : CColors.primary)
                .withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isCash
                ? Icons.payments_outlined
                : Icons.credit_card_outlined,
            color: isWorker ? CColors.success : CColors.primary,
            size:  22,
          ),
        ),
        const SizedBox(width: 12),

        // Details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(txn['title'] as String,
                  style: TextStyle(
                    fontSize:   14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? CColors.white : CColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                '${isCash ? "Cash" : "Card"} · '
                    '${timestamp != null ? timeago.format(timestamp.toDate()) : ""}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? CColors.lightGrey : CColors.darkGrey,
                ),
              ),
            ],
          ),
        ),

        // Amount
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${isWorker ? "+" : "-"} Rs. ${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize:   15,
              fontWeight: FontWeight.bold,
              color:      isWorker ? CColors.success : CColors.error,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color:        CColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('Paid',
                style: TextStyle(
                  fontSize:   10,
                  color:      CColors.success,
                  fontWeight: FontWeight.w600,
                )),
          ),
        ]),
      ]),
    );
  }
}