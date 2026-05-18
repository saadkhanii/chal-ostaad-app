// lib/core/models/bid_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class BidModel {
  final String? id;
  final String jobId;
  final String workerId;
  final String clientId;
  final double amount;
  final String? message;
  final String status;
  final Timestamp createdAt;
  final Timestamp? updatedAt;
  final DateTime? availableTime;
  final DateTime? workerProposedStartTime;
  final DateTime? clientProposedStartTime;
  final String? timeProposalStatus;

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
    this.availableTime,
    this.workerProposedStartTime,
    this.clientProposedStartTime,
    this.timeProposalStatus,
  });

  factory BidModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data()!;
    double parsedAmount = 0.0;
    final amountValue = data['amount'];
    if (amountValue is int) parsedAmount = amountValue.toDouble();
    else if (amountValue is double) parsedAmount = amountValue;
    else if (amountValue is String) {
      try {
        final cleaned = amountValue.replaceAll(RegExp(r'[^0-9\.]'), '');
        parsedAmount = double.parse(cleaned);
      } catch (_) {}
    } else if (amountValue is num) parsedAmount = amountValue.toDouble();

    DateTime? availableTime;
    final avTime = data['availableTime'];
    if (avTime is Timestamp) availableTime = avTime.toDate();

    DateTime? workerProposed;
    final wp = data['workerProposedStartTime'];
    if (wp is Timestamp) workerProposed = wp.toDate();

    DateTime? clientProposed;
    final cp = data['clientProposedStartTime'];
    if (cp is Timestamp) clientProposed = cp.toDate();

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
      availableTime: availableTime,
      workerProposedStartTime: workerProposed,
      clientProposedStartTime: clientProposed,
      timeProposalStatus: data['timeProposalStatus'] as String?,
    );
  }

  factory BidModel.fromMap(Map<String, dynamic> data, String id) {
    double parsedAmount = 0.0;
    final amountValue = data['amount'];
    if (amountValue is int) parsedAmount = amountValue.toDouble();
    else if (amountValue is double) parsedAmount = amountValue;
    else if (amountValue is String) {
      try {
        final cleaned = amountValue.replaceAll(RegExp(r'[^0-9\.]'), '');
        parsedAmount = double.parse(cleaned);
      } catch (_) {}
    } else if (amountValue is num) parsedAmount = amountValue.toDouble();

    DateTime? availableTime;
    final avTime = data['availableTime'];
    if (avTime is Timestamp) availableTime = avTime.toDate();

    DateTime? workerProposed;
    final wp = data['workerProposedStartTime'];
    if (wp is Timestamp) workerProposed = wp.toDate();

    DateTime? clientProposed;
    final cp = data['clientProposedStartTime'];
    if (cp is Timestamp) clientProposed = cp.toDate();

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
      availableTime: availableTime,
      workerProposedStartTime: workerProposed,
      clientProposedStartTime: clientProposed,
      timeProposalStatus: data['timeProposalStatus'] as String?,
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
      if (availableTime != null) 'availableTime': Timestamp.fromDate(availableTime!),
      if (workerProposedStartTime != null) 'workerProposedStartTime': Timestamp.fromDate(workerProposedStartTime!),
      if (clientProposedStartTime != null) 'clientProposedStartTime': Timestamp.fromDate(clientProposedStartTime!),
      if (timeProposalStatus != null) 'timeProposalStatus': timeProposalStatus,
    };
  }
}