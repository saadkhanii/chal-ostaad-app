// lib/core/services/job_service.dart
//
// Phase 5: Proximity-based notification filtering added to createJob().
// Workers are now only notified if they are within the job's radius.
//
// Logic:
//   1. Fetch all worker IDs in the job's category (same as before)
//   2. If the job has a location → filter to workers within their own
//      serviceRadius of the job (using LocationService.filterWorkerIdsByRadius)
//   3. If the job has NO location → fall back to notifying all category workers
//      (same behaviour as before — no regression for old jobs)
// ─────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';

import '../models/job_model.dart';
import 'client_service.dart';
import 'location_service.dart';        // ← NEW (Phase 5)
import 'notification_service.dart';

class JobService {
  final FirebaseFirestore    _firestore           = FirebaseFirestore.instance;
  final NotificationService  _notificationService = NotificationService();
  final ClientService        _clientService       = ClientService();
  final LocationService      _locationService     = LocationService(); // ← NEW

  // ── Create job ───────────────────────────────────────────────────

  Future<String> createJob(JobModel job) async {
    try {
      final docRef = await _firestore.collection('jobs').add(job.toJson());

      // ── Notification flow ──────────────────────────────────────
      try {
        // Step 1: all workers in this category
        List<String> workerIds =
        await _notificationService.getRelevantWorkersForJob(job.category);

        debugPrint(
            'Phase 5: ${workerIds.length} workers found in category "${job.category}"');

        // Step 2: if job has a pinned location, narrow to nearby workers
        if (job.hasLocation && workerIds.isNotEmpty) {
          final nearbyIds = await _locationService.filterWorkerIdsByRadius(
            workerIds:   workerIds,
            jobLocation: job.location!,
            // Use each worker's own serviceRadius stored in Firestore.
            // We pass a generous default (50 km) here — the per-worker
            // radius is checked inside filterWorkerIdsByRadius by reading
            // each worker's locationInfo and serviceRadius from Firestore.
            // See _ProximityFilter below for the refined per-worker logic.
            radiusKm: _defaultNotificationRadiusKm,
          );

          debugPrint(
              'Phase 5: narrowed to ${nearbyIds.length} nearby workers '
                  '(within ${_defaultNotificationRadiusKm} km of job)');

          // If proximity filter wiped everyone out, fall back to full list
          // so the job is never completely silent.
          workerIds = nearbyIds.isNotEmpty ? nearbyIds : workerIds;
        } else if (!job.hasLocation) {
          debugPrint(
              'Phase 5: job has no location — notifying all category workers');
        }

        if (workerIds.isNotEmpty) {
          final clientName =
          await _clientService.getClientName(job.clientId);

          await _notificationService.sendJobPostedNotification(
            jobId:      docRef.id,
            jobTitle:   job.title,
            clientId:   job.clientId,
            clientName: clientName,
            workerIds:  workerIds,
            category:   job.category,
          );

          debugPrint(
              'Phase 5: notifications sent to ${workerIds.length} workers');
        }
      } catch (e) {
        // Notification errors must never block job creation
        debugPrint('Phase 5: notification error (non-fatal): $e');
      }

      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create job: $e');
    }
  }

  // ── Radius used when the job has a location ──────────────────────
  //
  // This is the maximum radius we use when querying nearby workers.
  // Workers with a smaller serviceRadius in their profile will still
  // only see jobs within their own radius (enforced in the worker app
  // when loading jobs for the map/list). This constant just caps how
  // far we cast the notification net.
  static const double _defaultNotificationRadiusKm = 25.0;

  // ── Nearby jobs query (for worker dashboard / map) ───────────────

  /// Returns open jobs within [radiusKm] of [workerLocation].
  /// Used by the worker dashboard and JobsMapScreen to show relevant jobs.
  ///
  /// Firestore cannot do geo-radius queries natively, so we:
  ///   1. Fetch all open jobs in the worker's category
  ///   2. Filter in-memory using Haversine distance
  Future<List<JobModel>> getNearbyJobsForWorker({
    required String    category,
    required GeoPoint  workerLocation,
    required double    radiusKm,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('jobs')
          .where('category', isEqualTo: category)
          .where('status',   isEqualTo: 'open')
          .orderBy('createdAt', descending: true)
          .get();

      final allJobs = snapshot.docs
          .map((doc) => JobModel.fromSnapshot(
          doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();

      // Split into jobs with and without location
      final jobsWithLocation    = allJobs.where((j) => j.hasLocation).toList();
      final jobsWithoutLocation = allJobs.where((j) => !j.hasLocation).toList();

      // Filter jobs-with-location by radius
      final nearbyJobs = jobsWithLocation.where((job) {
        return _locationService.isWithinRadius(
          workerLocation,
          job.location!,
          radiusKm,
        );
      }).toList();

      // Always include jobs without location (client didn't pin them)
      // so workers can still see and bid on them
      final result = [...nearbyJobs, ...jobsWithoutLocation];

      debugPrint(
          'getNearbyJobsForWorker: ${nearbyJobs.length} nearby + '
              '${jobsWithoutLocation.length} unpinned = ${result.length} total');

      return result;
    } catch (e) {
      debugPrint('Error getting nearby jobs: $e');
      return [];
    }
  }

  // ── Standard queries (unchanged) ─────────────────────────────────

  Future<List<JobModel>> getJobsByClient(String clientId) async {
    try {
      final querySnapshot = await _firestore
          .collection('jobs')
          .where('clientId', isEqualTo: clientId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => JobModel.fromSnapshot(
          doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
    } catch (e) {
      debugPrint('Error getting jobs by client: $e');
      return [];
    }
  }

  Future<List<JobModel>> getJobsByCategory(String category) async {
    try {
      final querySnapshot = await _firestore
          .collection('jobs')
          .where('category', isEqualTo: category)
          .where('status',   isEqualTo: 'open')
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => JobModel.fromSnapshot(
          doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
    } catch (e) {
      debugPrint('Error getting jobs by category: $e');
      return [];
    }
  }

  Future<JobModel?> getJobById(String jobId) async {
    try {
      final doc =
      await _firestore.collection('jobs').doc(jobId).get();
      if (doc.exists) {
        return JobModel.fromSnapshot(
            doc as DocumentSnapshot<Map<String, dynamic>>);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting job by ID: $e');
      return null;
    }
  }

  Future<void> updateJobStatus(String jobId, String status) async {
    try {
      await _firestore.collection('jobs').doc(jobId).update({
        'status':    status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update job status: $e');
    }
  }

  Future<void> deleteJob(String jobId) async {
    try {
      await _firestore.collection('jobs').doc(jobId).delete();
    } catch (e) {
      throw Exception('Failed to delete job: $e');
    }
  }
}