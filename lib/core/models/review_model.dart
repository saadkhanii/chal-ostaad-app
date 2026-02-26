// lib/core/models/review_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewModel {
  final String?    id;
  final String     jobId;
  final String     clientId;
  final String     clientName;
  final String     workerId;
  final double     rating;       // 1.0 – 5.0
  final String     comment;      // optional, may be empty
  final Timestamp  createdAt;

  const ReviewModel({
    this.id,
    required this.jobId,
    required this.clientId,
    required this.clientName,
    required this.workerId,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  // ── Firestore → model ──────────────────────────────────────────
  factory ReviewModel.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ReviewModel(
      id:         doc.id,
      jobId:      d['jobId']      as String? ?? '',
      clientId:   d['clientId']   as String? ?? '',
      clientName: d['clientName'] as String? ?? 'Client',
      workerId:   d['workerId']   as String? ?? '',
      rating:     (d['rating']    as num?)?.toDouble() ?? 0.0,
      comment:    d['comment']    as String? ?? '',
      createdAt:  d['createdAt']  as Timestamp? ?? Timestamp.now(),
    );
  }

  // ── model → Firestore ──────────────────────────────────────────
  Map<String, dynamic> toJson() => {
    'jobId':      jobId,
    'clientId':   clientId,
    'clientName': clientName,
    'workerId':   workerId,
    'rating':     rating,
    'comment':    comment,
    'createdAt':  createdAt,
  };
}