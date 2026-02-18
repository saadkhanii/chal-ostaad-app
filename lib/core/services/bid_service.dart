import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import '../models/bid_model.dart';
import 'notification_service.dart';

class BidService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  Future<String> createBid(BidModel bid) async {
    try {
      final docRef = await _firestore.collection('bids').add(bid.toJson());

      try {
        final jobDoc = await _firestore.collection('jobs').doc(bid.jobId).get();
        if (jobDoc.exists) {
          final jobData = jobDoc.data();
          final jobTitle = jobData?['title'] ?? 'a job';

          String workerName = 'A worker';
          final workerDoc = await _firestore.collection('workers').doc(bid.workerId).get();
          if (workerDoc.exists) {
            final workerData = workerDoc.data();
            final personalInfo = workerData?['personalInfo'] as Map<String, dynamic>?;
            workerName = personalInfo?['name'] ?? 'Worker';
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
        print('Error sending bid notification: $e');
      }

      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create bid: $e');
    }
  }

  Future<void> updateBidStatus(String bidId, String status) async {
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
          final jobData = jobDoc.data();
          final jobTitle = jobData?['title'] ?? 'a job';

          String clientName = 'Client';
          final clientDoc = await _firestore.collection('clients').doc(bidData['clientId']).get();
          if (clientDoc.exists) {
            final clientData = clientDoc.data();
            final personalInfo = clientData?['personalInfo'] as Map<String, dynamic>?;
            clientName = personalInfo?['fullName'] ?? 'Client';
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
        print('Error sending bid status notification: $e');
      }
    } catch (e) {
      throw Exception('Failed to update bid status: $e');
    }
  }
  Future<List<BidModel>> getBidsByJob(String jobId) async {
    try {
      final querySnapshot = await _firestore
          .collection('bids')
          .where('jobId', isEqualTo: jobId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        return BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
      }).toList();
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

      return querySnapshot.docs.map((doc) {
        return BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
      }).toList();
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

      return querySnapshot.docs.map((doc) {
        return BidModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
      }).toList();
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