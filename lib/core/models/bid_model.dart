// lib/core/models/bid_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class BidModel {
  final String? id;
  final String jobId;
  final String workerId;
  final String clientId;
  final double amount;
  final String? message;
  final String status; // 'pending', 'accepted', 'rejected'
  final Timestamp createdAt;
  final Timestamp? updatedAt;

  BidModel({
    this.id,
    required this.jobId,
    required this.workerId,
    required this.clientId,
    required this.amount,
    this.message,
    this.status = 'pending',
    required this.createdAt,
    this.updatedAt,
  });

  factory BidModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data()!;
    return BidModel(
      id: document.id,
      jobId: data['jobId'] ?? '',
      workerId: data['workerId'] ?? '',
      clientId: data['clientId'] ?? '',
      amount: (data['amount'] as num).toDouble(),
      message: data['message'],
      status: data['status'] ?? 'pending',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      updatedAt: data['updatedAt'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'jobId': jobId,
      'workerId': workerId,
      'clientId': clientId,
      'amount': amount,
      if (message != null) 'message': message,
      'status': status,
      'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }
}