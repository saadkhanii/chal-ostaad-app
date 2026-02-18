// lib/core/services/worker_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/worker_model.dart';

class WorkerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<WorkerModel?> getCurrentWorker() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userEmail = prefs.getString('user_email');

      if (userEmail == null) {
        throw Exception('No user email found in shared preferences');
      }

      // Query workers collection by email
      final querySnapshot = await _firestore
          .collection('workers')
          .where('personalInfo.email', isEqualTo: userEmail)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception('Worker not found with email: $userEmail');
      }

      final doc = querySnapshot.docs.first;
      return WorkerModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
    } catch (e) {
      debugPrint('Error fetching worker data: $e');
      rethrow;
    }
  }

  /// Get workers by category ID
  Future<List<String>> getWorkerIdsByCategory(String categoryId) async {
    try {
      final querySnapshot = await _firestore
          .collection('workers')
          .where('workInfo.categoryId', isEqualTo: categoryId)
          .where('accountStatus', isEqualTo: 'active')
          .get();

      return querySnapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      debugPrint('Error getting workers by category: $e');
      return [];
    }
  }

  /// Get worker name by ID
  Future<String> getWorkerName(String workerId) async {
    try {
      final doc = await _firestore.collection('workers').doc(workerId).get();
      if (doc.exists) {
        final data = doc.data();
        final personalInfo = data?['personalInfo'] as Map<String, dynamic>?;
        return personalInfo?['name'] ?? 'Worker';
      }
      return 'Worker';
    } catch (e) {
      debugPrint('Error getting worker name: $e');
      return 'Worker';
    }
  }

  Future<WorkerModel?> getWorkerById(String workerId) async {
    try {
      final doc = await _firestore.collection('workers').doc(workerId).get();
      if (doc.exists) {
        return WorkerModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching worker by ID: $e');
      return null;
    }
  }

  Future<void> updateWorkerProfile(String workerId, Map<String, dynamic> updates) async {
    try {
      await _firestore.collection('workers').doc(workerId).update({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating worker profile: $e');
      rethrow;
    }
  }

  // Get worker stats from jobs collection
  Future<Map<String, dynamic>> getWorkerStats(String workerId) async {
    try {
      // This would query the jobs collection to calculate actual stats
      // For now, returning placeholder data
      return {
        'completedJobs': 0,
        'ongoingJobs': 0,
        'totalEarnings': 0,
        'monthlyEarnings': 0,
        'activeApplications': 0,
      };
    } catch (e) {
      debugPrint('Error fetching worker stats: $e');
      return {
        'completedJobs': 0,
        'ongoingJobs': 0,
        'totalEarnings': 0,
        'monthlyEarnings': 0,
        'activeApplications': 0,
      };
    }
  }
}