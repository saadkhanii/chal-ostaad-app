// lib/core/services/bid_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';

import '../models/bid_model.dart';

class BidService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> createBid(BidModel bid) async {
    try {
      final docRef = await _firestore.collection('bids').add(bid.toJson());
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create bid: $e');
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

  Future<void> updateBidStatus(String bidId, String status) async {
    try {
      await _firestore.collection('bids').doc(bidId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update bid status: $e');
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