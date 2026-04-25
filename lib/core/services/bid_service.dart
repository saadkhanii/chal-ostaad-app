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
          final workerDoc =
          await _firestore.collection('workers').doc(bid.workerId).get();
          if (workerDoc.exists) {
            final personalInfo =
            workerDoc.data()?['personalInfo'] as Map<String, dynamic>?;
            workerName = personalInfo?['fullName'] ?? 'Worker';
          }

          await _notificationService.sendBidPlacedNotification(
            jobId:      bid.jobId,
            jobTitle:   jobTitle,
            workerId:   bid.workerId,
            workerName: workerName,
            bidAmount:  bid.amount,
            clientId:   bid.clientId,
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

  // ── Accept bid → auto-sets job to in-progress ─────────────────────
  /// Accepts [bidId], rejects all other pending bids for the same job,
  /// and updates the job status to 'in-progress' atomically.
  Future<void> acceptBid(String bidId) async {
    final bidDoc = await _firestore.collection('bids').doc(bidId).get();
    if (!bidDoc.exists) throw Exception('Bid not found');
    final bidData = bidDoc.data()!;
    final jobId   = bidData['jobId']   as String;
    final clientId = bidData['clientId'] as String;
    final workerId = bidData['workerId'] as String;

    final batch = _firestore.batch();

    // 1. Mark this bid as accepted
    batch.update(_firestore.collection('bids').doc(bidId), {
      'status':    'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Reject all other pending bids for this job
    final otherBids = await _firestore
        .collection('bids')
        .where('jobId',  isEqualTo: jobId)
        .where('status', isEqualTo: 'pending')
        .get();
    for (final doc in otherBids.docs) {
      if (doc.id != bidId) {
        batch.update(doc.reference, {
          'status':    'rejected',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    // 3. Move job to in-progress
    batch.update(_firestore.collection('jobs').doc(jobId), {
      'status':    'in-progress',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // 4. Send notification to worker
    try {
      final jobDoc = await _firestore.collection('jobs').doc(jobId).get();
      final jobTitle = jobDoc.data()?['title'] ?? 'a job';

      String clientName = 'Client';
      final clientDoc =
      await _firestore.collection('clients').doc(clientId).get();
      if (clientDoc.exists) {
        final info =
        clientDoc.data()?['personalInfo'] as Map<String, dynamic>?;
        clientName = info?['fullName'] ?? 'Client';
      }

      await _notificationService.sendBidStatusNotification(
        jobId:      jobId,
        jobTitle:   jobTitle,
        workerId:   workerId,
        clientName: clientName,
        status:     'accepted',
      );
    } catch (e) {
      debugPrint('Error sending bid accepted notification: $e');
    }
  }

  // ── Cancel job ────────────────────────────────────────────────────
  /// Both client and worker can cancel. Moves job to 'cancelled'.
  Future<void> cancelJob({
    required String jobId,
    required String cancelledBy, // 'client' | 'worker'
    String? reason,
  }) async {
    await _firestore.collection('jobs').doc(jobId).update({
      'status':        'cancelled',
      'cancelledBy':   cancelledBy,
      if (reason != null) 'cancelReason': reason,
      'cancelledAt':   FieldValue.serverTimestamp(),
      'updatedAt':     FieldValue.serverTimestamp(),
    });
  }

  // ── Delete job (client only, while status is open) ────────────────
  Future<void> deleteJob(String jobId) async {
    await _firestore.collection('jobs').doc(jobId).update({
      'status':    'deleted',
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Legacy updateBidStatus (kept for backwards compat) ────────────
  Future<void> updateBidStatus(String bidId, String status) async {
    if (status == 'accepted') {
      return acceptBid(bidId);
    }
    try {
      final bidDoc = await _firestore.collection('bids').doc(bidId).get();
      if (!bidDoc.exists) throw Exception('Bid not found');
      final bidData = bidDoc.data()!;

      await _firestore.collection('bids').doc(bidId).update({
        'status':    status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      try {
        final jobDoc =
        await _firestore.collection('jobs').doc(bidData['jobId']).get();
        if (jobDoc.exists) {
          final jobTitle = jobDoc.data()?['title'] ?? 'a job';

          String clientName = 'Client';
          final clientDoc = await _firestore
              .collection('clients')
              .doc(bidData['clientId'])
              .get();
          if (clientDoc.exists) {
            final info =
            clientDoc.data()?['personalInfo'] as Map<String, dynamic>?;
            clientName = info?['fullName'] ?? 'Client';
          }

          await _notificationService.sendBidStatusNotification(
            jobId:      bidData['jobId'],
            jobTitle:   jobTitle,
            workerId:   bidData['workerId'],
            clientName: clientName,
            status:     status,
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
          .map((doc) => BidModel.fromSnapshot(
          doc as DocumentSnapshot<Map<String, dynamic>>))
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
          .map((doc) => BidModel.fromSnapshot(
          doc as DocumentSnapshot<Map<String, dynamic>>))
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
          .map((doc) => BidModel.fromSnapshot(
          doc as DocumentSnapshot<Map<String, dynamic>>))
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