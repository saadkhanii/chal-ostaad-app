// lib/core/services/review_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/review_model.dart';

class ReviewService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Submit a review ────────────────────────────────────────────
  //
  // 1. Writes the review doc to the top-level `reviews` collection.
  // 2. Atomically updates worker's ratings.average & ratings.totalReviews
  //    using a Firestore transaction to prevent race conditions.
  // 3. Marks the job doc with `reviewSubmitted: true` so the "Leave Review"
  //    button turns into "Review Submitted" on the client side.

  Future<void> submitReview({
    required String  jobId,
    required String  clientId,
    required String  clientName,
    required String  workerId,
    required double  rating,
    required String  comment,
  }) async {
    try {
      final reviewRef  = _firestore.collection('reviews').doc();
      final workerRef  = _firestore.collection('workers').doc(workerId);
      final jobRef     = _firestore.collection('jobs').doc(jobId);

      await _firestore.runTransaction((tx) async {
        // Read current worker ratings
        final workerSnap = await tx.get(workerRef);
        final data       = workerSnap.data() ?? {};
        final ratings    = data['ratings'] as Map<String, dynamic>? ?? {};

        final currentAvg   = (ratings['average']      as num?)?.toDouble() ?? 0.0;
        final totalReviews = (ratings['totalReviews'] as int?)  ?? 0;

        final newTotal   = totalReviews + 1;
        // Weighted average: ((oldAvg * oldCount) + newRating) / newCount
        final newAverage = ((currentAvg * totalReviews) + rating) / newTotal;

        // 1 — Write review document
        tx.set(reviewRef, ReviewModel(
          jobId:      jobId,
          clientId:   clientId,
          clientName: clientName,
          workerId:   workerId,
          rating:     rating,
          comment:    comment,
          createdAt:  Timestamp.now(),
        ).toJson());

        // 2 — Update worker's aggregate rating (rounded to 1 decimal)
        tx.update(workerRef, {
          'ratings.average':      double.parse(newAverage.toStringAsFixed(1)),
          'ratings.totalReviews': newTotal,
        });

        // 3 — Mark job so client can't review twice
        tx.update(jobRef, {'reviewSubmitted': true});
      });

      debugPrint('ReviewService: review submitted for job $jobId');
    } catch (e) {
      throw Exception('Failed to submit review: $e');
    }
  }

  // ── Check if client already reviewed a specific job ────────────
  Future<bool> hasReviewed({
    required String jobId,
    required String clientId,
  }) async {
    try {
      final snap = await _firestore
          .collection('reviews')
          .where('jobId',    isEqualTo: jobId)
          .where('clientId', isEqualTo: clientId)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Get all reviews for a worker (for profile screen) ──────────
  Future<List<ReviewModel>> getWorkerReviews(String workerId) async {
    try {
      final snap = await _firestore
          .collection('reviews')
          .where('workerId', isEqualTo: workerId)
          .orderBy('createdAt', descending: true)
          .get();
      return snap.docs
          .map((d) => ReviewModel.fromSnapshot(
          d as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
    } catch (e) {
      debugPrint('ReviewService: error fetching reviews: $e');
      return [];
    }
  }

  // ── Stream of reviews for a worker (live updates) ──────────────
  Stream<List<ReviewModel>> workerReviewsStream(String workerId) {
    return _firestore
        .collection('reviews')
        .where('workerId', isEqualTo: workerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
        .map((d) => ReviewModel.fromSnapshot(
        d as DocumentSnapshot<Map<String, dynamic>>))
        .toList());
  }
}