// lib/core/services/worker_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/worker_model.dart';

class WorkerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Current worker ───────────────────────────────────────────────

  Future<WorkerModel?> getCurrentWorker() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userEmail = prefs.getString('user_email');

      if (userEmail == null) {
        throw Exception('No user email found in shared preferences');
      }

      final querySnapshot = await _firestore
          .collection('workers')
          .where('personalInfo.email', isEqualTo: userEmail)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception('Worker not found with email: $userEmail');
      }

      final doc = querySnapshot.docs.first;
      return WorkerModel.fromSnapshot(
          doc as DocumentSnapshot<Map<String, dynamic>>);
    } catch (e) {
      debugPrint('Error fetching worker data: $e');
      rethrow;
    }
  }

  // ── Get by ID ────────────────────────────────────────────────────

  Future<WorkerModel?> getWorkerById(String workerId) async {
    try {
      final doc =
      await _firestore.collection('workers').doc(workerId).get();
      if (doc.exists) {
        return WorkerModel.fromSnapshot(
            doc as DocumentSnapshot<Map<String, dynamic>>);
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching worker by ID: $e');
      return null;
    }
  }

  // ── Get worker name ──────────────────────────────────────────────

  Future<String> getWorkerName(String workerId) async {
    try {
      final doc =
      await _firestore.collection('workers').doc(workerId).get();
      if (doc.exists) {
        final data = doc.data();
        final personalInfo =
        data?['personalInfo'] as Map<String, dynamic>?;
        return personalInfo?['name'] ?? 'Worker';
      }
      return 'Worker';
    } catch (e) {
      debugPrint('Error getting worker name: $e');
      return 'Worker';
    }
  }

  // ── Category-based worker IDs (used by notification service) ────
  //
  // NOTE: Firestore cannot do radius queries natively.
  // We fetch all workers in the category here, then Phase 2's
  // LocationService.filterWorkersByRadius() will trim the list
  // to only those within the job's serviceRadius.
  Future<List<String>> getWorkerIdsByCategory(String categoryId) async {
    try {
      final querySnapshot = await _firestore
          .collection('workers')
          .where('workInfo.categoryId', isEqualTo: categoryId)
          .where('account.accountStatus', isEqualTo: 'active')
          .get();

      return querySnapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      debugPrint('Error getting workers by category: $e');
      return [];
    }
  }

  // ── Location updates ─────────────────────────────────────────────

  /// Call this whenever the worker's live GPS position changes.
  /// Updates only the locationInfo.currentLocation field — does not
  /// touch any other worker data.
  Future<void> updateCurrentLocation(
      String workerId, double latitude, double longitude) async {
    try {
      await _firestore.collection('workers').doc(workerId).update({
        'locationInfo.currentLocation':
        GeoPoint(latitude, longitude),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint(
          'Worker $workerId location updated: $latitude, $longitude');
    } catch (e) {
      debugPrint('Error updating worker location: $e');
      rethrow;
    }
  }

  /// Call this when a worker sets their home/base location in profile settings.
  Future<void> updateHomeLocation(
      String workerId, double latitude, double longitude) async {
    try {
      await _firestore.collection('workers').doc(workerId).update({
        'locationInfo.homeLocation': GeoPoint(latitude, longitude),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint(
          'Worker $workerId home location updated: $latitude, $longitude');
    } catch (e) {
      debugPrint('Error updating home location: $e');
      rethrow;
    }
  }

  // ── Profile update ───────────────────────────────────────────────

  Future<void> updateWorkerProfile(
      String workerId, Map<String, dynamic> updates) async {
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

  // ── Stats ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getWorkerStats(String workerId) async {
    try {
      // TODO: calculate from real jobs data in Phase 5
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