// lib/core/services/bid_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import '../models/bid_model.dart';
import 'notification_service.dart';

class BidService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  // ── Create bid ────────────────────────────────────────────────────
  Future<String> createBid(BidModel bid) async {
    try {
      final docRef = await _firestore.collection('bids').add(bid.toJson());

      try {
        final jobDoc = await _firestore.collection('jobs').doc(bid.jobId).get();
        if (jobDoc.exists) {
          final jobTitle = jobDoc.data()?['title'] ?? 'a job';
          String workerName = 'A worker';
          final workerDoc = await _firestore.collection('workers').doc(bid.workerId).get();
          if (workerDoc.exists) {
            final personalInfo = workerDoc.data()?['personalInfo'] as Map<String, dynamic>?;
            workerName = personalInfo?['fullName'] ?? 'Worker';
          }
          await _notificationService.sendBidPlacedNotification(
            jobId: bid.jobId,
            jobTitle: jobTitle,
            workerId: bid.workerId,
            workerName: workerName,
            bidAmount: bid.amount,
            clientId: bid.clientId,
          );
        }
      } catch (e) {
        debugPrint('Error sending bid notification: $e');
      }
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create bid: $e');
    }
  }

  // ── Update bid ────────────────────────────────────────────────────
  Future<void> updateBid(String bidId, BidModel updatedBid) async {
    try {
      final doc = await _firestore.collection('bids').doc(bidId).get();
      if (!doc.exists) throw Exception('Bid not found');
      final status = doc.data()?['status'] as String?;
      if (status != 'pending') throw Exception('Cannot update a non-pending bid');

      await _firestore.collection('bids').doc(bidId).update({
        'amount': updatedBid.amount,
        if (updatedBid.message != null) 'message': updatedBid.message,
        if (updatedBid.availableTime != null) 'availableTime': Timestamp.fromDate(updatedBid.availableTime!),
        if (updatedBid.workerProposedStartTime != null) 'workerProposedStartTime': Timestamp.fromDate(updatedBid.workerProposedStartTime!),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update bid: $e');
    }
  }

  // ── Delete bid ────────────────────────────────────────────────────
  Future<void> deleteBid(String bidId) async {
    try {
      final doc = await _firestore.collection('bids').doc(bidId).get();
      if (!doc.exists) throw Exception('Bid not found');
      final status = doc.data()?['status'] as String?;
      if (status != 'pending') throw Exception('Cannot delete a non-pending bid');
      await _firestore.collection('bids').doc(bidId).delete();
    } catch (e) {
      throw Exception('Failed to delete bid: $e');
    }
  }

  // ── Accept bid (final) ────────────────────────────────────────────
  Future<void> acceptBid(String bidId) async {
    final bidDoc = await _firestore.collection('bids').doc(bidId).get();
    if (!bidDoc.exists) throw Exception('Bid not found');
    final bidData = bidDoc.data()!;
    final jobId   = bidData['jobId']   as String;
    final clientId = bidData['clientId'] as String;
    final workerId = bidData['workerId'] as String;

    final batch = _firestore.batch();

    batch.update(_firestore.collection('bids').doc(bidId), {
      'status': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final otherBids = await _firestore
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .where('status', isEqualTo: 'pending')
        .get();
    for (final doc in otherBids.docs) {
      if (doc.id != bidId) {
        batch.update(doc.reference, {'status': 'rejected', 'updatedAt': FieldValue.serverTimestamp()});
      }
    }

    batch.update(_firestore.collection('jobs').doc(jobId), {
      'status': 'in-progress',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    try {
      final jobDoc = await _firestore.collection('jobs').doc(jobId).get();
      final jobTitle = jobDoc.data()?['title'] ?? 'a job';
      String clientName = 'Client';
      final clientDoc = await _firestore.collection('clients').doc(clientId).get();
      if (clientDoc.exists) {
        final info = clientDoc.data()?['personalInfo'] as Map<String, dynamic>?;
        clientName = info?['fullName'] ?? 'Client';
      }
      await _notificationService.sendBidStatusNotification(
        jobId: jobId,
        jobTitle: jobTitle,
        workerId: workerId,
        clientName: clientName,
        status: 'accepted',
      );
    } catch (e) {
      debugPrint('Error sending bid accepted notification: $e');
    }
  }

  // ── Accept bid provisionally with start time agreement ────────────
  Future<void> acceptBidProvisional({
    required String bidId,
    required DateTime agreedStartTime,
  }) async {
    final bidDoc = await _firestore.collection('bids').doc(bidId).get();
    if (!bidDoc.exists) throw Exception('Bid not found');
    final bidData = bidDoc.data()!;
    final jobId = bidData['jobId'] as String;
    final clientId = bidData['clientId'] as String;
    final workerId = bidData['workerId'] as String;

    final now = Timestamp.now();
    final expiry = Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 10)));
    final batch = _firestore.batch();

    batch.update(_firestore.collection('bids').doc(bidId), {
      'status': 'accepted',
      'updatedAt': now,
    });

    final otherBids = await _firestore
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .where('status', isEqualTo: 'pending')
        .get();
    for (final doc in otherBids.docs) {
      if (doc.id != bidId) {
        batch.update(doc.reference, {'status': 'rejected', 'updatedAt': now});
      }
    }

    batch.update(_firestore.collection('jobs').doc(jobId), {
      'status': 'pending_start_agreement',
      'agreedStartTime': Timestamp.fromDate(agreedStartTime),
      'startAgreementExpiry': expiry,
      'startAgreementCreatedAt': now,
      'startAgreementStatus': 'pending',
      'updatedAt': now,
    });

    await batch.commit();

    try {
      final jobDoc = await _firestore.collection('jobs').doc(jobId).get();
      final jobTitle = jobDoc.data()?['title'] ?? 'a job';
      String clientName = 'Client';
      final clientDoc = await _firestore.collection('clients').doc(clientId).get();
      if (clientDoc.exists) {
        final info = clientDoc.data()?['personalInfo'] as Map<String, dynamic>?;
        clientName = info?['fullName'] ?? 'Client';
      }
      await _notificationService.sendBidStatusNotification(
        jobId: jobId,
        jobTitle: jobTitle,
        workerId: workerId,
        clientName: clientName,
        status: 'accepted_pending_confirmation',
      );
    } catch (e) {
      debugPrint('Error sending provisional accept notification: $e');
    }
  }

  // ── Cancel job (client or worker) ────────────────────────────────
  Future<void> cancelJob({
    required String jobId,
    required String cancelledBy,
    String? reason,
  }) async {
    await _firestore.collection('jobs').doc(jobId).update({
      'status': 'cancelled',
      'cancelledBy': cancelledBy,
      if (reason != null) 'cancelReason': reason,
      'cancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Delete job (client only, while status is open) ────────────────
  Future<void> deleteJob(String jobId) async {
    await _firestore.collection('jobs').doc(jobId).update({
      'status': 'deleted',
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Worker confirms start time (after grace period) ──────────────
  Future<void> confirmStartTime(String jobId) async {
    final jobRef = _firestore.collection('jobs').doc(jobId);
    final snap = await jobRef.get();
    if (!snap.exists) throw Exception('Job not found');
    final data = snap.data()!;
    final status = data['status'] as String?;
    if (status != 'pending_start_agreement') throw Exception('Job not in start agreement state');

    final createdAt = (data['startAgreementCreatedAt'] as Timestamp?)?.toDate();
    if (createdAt == null) throw Exception('No agreement timestamp');
    final now = DateTime.now();
    if (now.isBefore(createdAt.add(const Duration(seconds: 60)))) {
      throw Exception('Cannot confirm before 60 seconds grace period');
    }

    await jobRef.update({
      'status': 'in-progress',
      'startAgreementStatus': 'confirmed',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Client cancels the start agreement (within 10 min) – reverts everything ──
  Future<void> cancelStartAgreement(String jobId) async {
    final jobRef = _firestore.collection('jobs').doc(jobId);
    final snap = await jobRef.get();
    if (!snap.exists) throw Exception('Job not found');
    final data = snap.data()!;
    final status = data['status'] as String?;
    if (status != 'pending_start_agreement') throw Exception('Job not in start agreement state');

    // Get all bids for this job
    final bidsSnapshot = await _firestore
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .get();

    final batch = _firestore.batch();
    // Set all bids to 'pending' (revert provisional accept)
    for (final doc in bidsSnapshot.docs) {
      batch.update(doc.reference, {'status': 'pending', 'updatedAt': FieldValue.serverTimestamp()});
    }
    // Update job back to 'open' and clear agreement fields
    batch.update(jobRef, {
      'status': 'open',
      'startAgreementStatus': 'cancelled',
      'agreedStartTime': FieldValue.delete(),
      'startAgreementExpiry': FieldValue.delete(),
      'startAgreementCreatedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  // ── Legacy updateBidStatus ───────────────────────────────────────
  Future<void> updateBidStatus(String bidId, String status) async {
    if (status == 'accepted') {
      return acceptBid(bidId);
    }
    try {
      final bidDoc = await _firestore.collection('bids').doc(bidId).get();
      if (!bidDoc.exists) throw Exception('Bid not found');
      final bidData = bidDoc.data()!;
      await _firestore.collection('bids').doc(bidId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      try {
        final jobDoc = await _firestore.collection('jobs').doc(bidData['jobId']).get();
        if (jobDoc.exists) {
          final jobTitle = jobDoc.data()?['title'] ?? 'a job';
          String clientName = 'Client';
          final clientDoc = await _firestore.collection('clients').doc(bidData['clientId']).get();
          if (clientDoc.exists) {
            final info = clientDoc.data()?['personalInfo'] as Map<String, dynamic>?;
            clientName = info?['fullName'] ?? 'Client';
          }
          await _notificationService.sendBidStatusNotification(
            jobId: bidData['jobId'],
            jobTitle: jobTitle,
            workerId: bidData['workerId'],
            clientName: clientName,
            status: status,
          );
        }
      } catch (e) {
        debugPrint('Error sending bid status notification: $e');
      }
    } catch (e) {
      throw Exception('Failed to update bid status: $e');
    }
  }

  // ── Queries ───────────────────────────────────────────────────────
  Future<List<BidModel>> getBidsByJob(String jobId) async {
    try {
      final querySnapshot = await _firestore
          .collection('bids')
          .where('jobId', isEqualTo: jobId)
          .orderBy('createdAt', descending: true)
          .get();
      return querySnapshot.docs
          .map((doc) => BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
    } catch (e) {
      debugPrint('Error getting bids by job: $e');
      return [];
    }
  }

  Future<List<BidModel>> getBidsByWorker(String workerId) async {
    try {
      final querySnapshot = await _firestore
          .collection('bids')
          .where('workerId', isEqualTo: workerId)
          .orderBy('createdAt', descending: true)
          .get();
      return querySnapshot.docs
          .map((doc) => BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
    } catch (e) {
      debugPrint('Error getting bids by worker: $e');
      return [];
    }
  }

  Future<List<BidModel>> getBidsByClient(String clientId) async {
    try {
      final querySnapshot = await _firestore
          .collection('bids')
          .where('clientId', isEqualTo: clientId)
          .orderBy('createdAt', descending: true)
          .get();
      return querySnapshot.docs
          .map((doc) => BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
    } catch (e) {
      debugPrint('Error getting bids by client: $e');
      return [];
    }
  }

  Future<bool> hasWorkerBidOnJob(String workerId, String jobId) async {
    try {
      final querySnapshot = await _firestore
          .collection('bids')
          .where('workerId', isEqualTo: workerId)
          .where('jobId', isEqualTo: jobId)
          .limit(1)
          .get();
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking existing bid: $e');
      return false;
    }
  }
}