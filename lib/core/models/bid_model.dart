// lib/core/models/bid_model.dart - UPDATED
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

    // SAFE amount parsing
    double parsedAmount = 0.0;
    final amountValue = data['amount'];

    if (amountValue is int) {
      parsedAmount = amountValue.toDouble();
    } else if (amountValue is double) {
      parsedAmount = amountValue;
    } else if (amountValue is String) {
      // Handle string amounts (remove Rs symbol, commas, etc.)
      try {
        final cleaned = amountValue.replaceAll(RegExp(r'[^0-9\.]'), '');
        parsedAmount = double.parse(cleaned);
      } catch (e) {
        print('Error parsing amount string: $amountValue, error: $e');
        parsedAmount = 0.0;
      }
    } else if (amountValue is num) {
      parsedAmount = amountValue.toDouble();
    } else {
      print('Warning: Unknown amount type: ${amountValue.runtimeType}');
    }

    return BidModel(
      id: document.id,
      jobId: data['jobId'] ?? '',
      workerId: data['workerId'] ?? '',
      clientId: data['clientId'] ?? '',
      amount: parsedAmount,
      message: data['message'],
      status: data['status'] ?? 'pending',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      updatedAt: data['updatedAt'],
    );
  }

  factory BidModel.fromMap(Map<String, dynamic> data, String id) {
    double parsedAmount = 0.0;
    final amountValue = data['amount'];

    if (amountValue is int) {
      parsedAmount = amountValue.toDouble();
    } else if (amountValue is double) {
      parsedAmount = amountValue;
    } else if (amountValue is String) {
      try {
        final cleaned = amountValue.replaceAll(RegExp(r'[^0-9\.]'), '');
        parsedAmount = double.parse(cleaned);
      } catch (e) {
        parsedAmount = 0.0;
      }
    } else if (amountValue is num) {
      parsedAmount = amountValue.toDouble();
    }

    return BidModel(
      id: id,
      jobId: data['jobId'] ?? '',
      workerId: data['workerId'] ?? '',
      clientId: data['clientId'] ?? '',
      amount: parsedAmount,
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