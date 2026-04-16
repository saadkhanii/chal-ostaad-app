// lib/core/models/payment_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentModel {
  final String? id;
  final String jobId;
  final String jobTitle;
  final String clientId;
  final String workerId;
  final double amount;
  final String method;  // 'stripe' | 'cash'
  final String status;  // 'pending' | 'completed' | 'failed'
  final Timestamp? createdAt;
  final Timestamp? completedAt;
  // For cash payments: confirmed by worker
  final bool? cashConfirmedByWorker;
  final Timestamp? cashConfirmedAt;

  PaymentModel({
    this.id,
    required this.jobId,
    required this.jobTitle,
    required this.clientId,
    required this.workerId,
    required this.amount,
    required this.method,
    this.status = 'pending',
    this.createdAt,
    this.completedAt,
    this.cashConfirmedByWorker,
    this.cashConfirmedAt,
  });

  factory PaymentModel.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return PaymentModel(
      id:                    doc.id,
      jobId:                 data['jobId']     ?? '',
      jobTitle:              data['jobTitle']  ?? '',
      clientId:              data['clientId']  ?? '',
      workerId:              data['workerId']  ?? '',
      amount:                (data['amount']   as num?)?.toDouble() ?? 0.0,
      method:                data['method']    ?? 'stripe',
      status:                data['status']    ?? 'pending',
      createdAt:             data['createdAt']            as Timestamp?,
      completedAt:           data['completedAt']          as Timestamp?,
      cashConfirmedByWorker: data['cashConfirmedByWorker'] as bool?,
      cashConfirmedAt:       data['cashConfirmedAt']      as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {
    'jobId':       jobId,
    'jobTitle':    jobTitle,
    'clientId':    clientId,
    'workerId':    workerId,
    'amount':      amount,
    'method':      method,
    'status':      status,
    if (createdAt             != null) 'createdAt':             createdAt,
    if (completedAt           != null) 'completedAt':           completedAt,
    if (cashConfirmedByWorker != null) 'cashConfirmedByWorker': cashConfirmedByWorker,
    if (cashConfirmedAt       != null) 'cashConfirmedAt':       cashConfirmedAt,
  };

  String get methodDisplayName => method == 'cash' ? 'Cash' : 'Stripe';
  bool   get isCash            => method == 'cash';
  bool   get isStripe          => method == 'stripe';

  String get statusDisplayName {
    switch (status) {
      case 'completed': return 'Paid';
      case 'failed':    return 'Failed';
      case 'pending':   return isCash ? 'Awaiting Confirmation' : 'Pending';
      default:          return 'Pending';
    }
  }
}