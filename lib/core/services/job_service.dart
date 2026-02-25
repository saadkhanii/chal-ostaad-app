// lib/core/services/job_service.dart
//
// Phase 5: Proximity-based notification filtering added to createJob().
// Phase 6: Progress-update request flow (worker → client approval).
//
// Progress flow:
//   Worker calls requestProgressUpdate()  → writes progressRequest to job doc
//                                          → notifies client
//   Client calls respondToProgressRequest():
//     • accepted  → job status becomes 'completed', progressRequest cleared
//     • rejected  → progressRequest cleared, job stays 'in-progress'
//   Client calls alterJobProgress()       → resets job back to 'in-progress'
//                                          → clears any pending request
// ─────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';

import '../models/job_model.dart';
import 'client_service.dart';
import 'location_service.dart';
import 'notification_service.dart';

class JobService {
  final FirebaseFirestore    _firestore           = FirebaseFirestore.instance;
  final NotificationService  _notificationService = NotificationService();
  final ClientService        _clientService       = ClientService();
  final LocationService      _locationService     = LocationService();

  // ── Create job ───────────────────────────────────────────────────

  Future<String> createJob(JobModel job) async {
    try {
      final docRef = await _firestore.collection('jobs').add(job.toJson());

      try {
        List<String> workerIds =
        await _notificationService.getRelevantWorkersForJob(job.category);

        debugPrint(
            'Phase 5: ${workerIds.length} workers found in category "${job.category}"');

        if (job.hasLocation && workerIds.isNotEmpty) {
          final nearbyIds = await _locationService.filterWorkerIdsByRadius(
            workerIds:   workerIds,
            jobLocation: job.location!,
            radiusKm:    _defaultNotificationRadiusKm,
          );

          debugPrint(
              'Phase 5: narrowed to ${nearbyIds.length} nearby workers '
                  '(within ${_defaultNotificationRadiusKm} km of job)');

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
        debugPrint('Phase 5: notification error (non-fatal): $e');
      }

      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create job: $e');
    }
  }

  // ── Progress-update request (worker → client) ────────────────────
  //
  // Writes a `progressRequest` sub-map onto the job document and sends
  // a notification to the client. The client then accepts or rejects it.
  //
  // Fields written:
  //   progressRequest: {
  //     workerId:    <id of the requesting worker>
  //     requestedAt: <server timestamp>
  //     note:        <optional message from the worker>   (may be null)
  //     status:      'pending'
  //   }

  Future<void> requestProgressUpdate({
    required String jobId,
    required String workerId,
    required String clientId,
    required String jobTitle,
    String? note,
  }) async {
    try {
      await _firestore.collection('jobs').doc(jobId).update({
        'progressRequest': {
          'workerId':    workerId,
          'requestedAt': FieldValue.serverTimestamp(),
          'note':        note,
          'status':      'pending',
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Notify the client
      try {
        await _notificationService.sendProgressRequestNotification(
          jobId:    jobId,
          jobTitle: jobTitle,
          clientId: clientId,
          workerId: workerId,
        );
      } catch (e) {
        debugPrint('Progress notification error (non-fatal): $e');
      }

      debugPrint('Phase 6: progress request sent for job $jobId');
    } catch (e) {
      throw Exception('Failed to request progress update: $e');
    }
  }

  // ── Respond to progress request (client) ────────────────────────
  //
  // [accepted]:
  //   • job status → 'completed'
  //   • progressRequest cleared
  //   • notifies worker
  //
  // [rejected]:
  //   • progressRequest cleared (job stays 'in-progress')
  //   • notifies worker

  Future<void> respondToProgressRequest({
    required String jobId,
    required String jobTitle,
    required String workerId,
    required bool   accepted,
  }) async {
    try {
      final Map<String, dynamic> update = {
        'progressRequest': FieldValue.delete(),
        'updatedAt':       FieldValue.serverTimestamp(),
      };

      if (accepted) {
        update['status'] = 'completed';
      }

      await _firestore.collection('jobs').doc(jobId).update(update);

      // Notify the worker of the outcome
      try {
        await _notificationService.sendProgressResponseNotification(
          jobId:    jobId,
          jobTitle: jobTitle,
          workerId: workerId,
          accepted: accepted,
        );
      } catch (e) {
        debugPrint('Progress response notification error (non-fatal): $e');
      }

      debugPrint(
          'Phase 6: progress request ${accepted ? "accepted" : "rejected"} '
              'for job $jobId');
    } catch (e) {
      throw Exception('Failed to respond to progress request: $e');
    }
  }

  // ── Alter job progress (client) ──────────────────────────────────
  //
  // Lets the client manually change the progress status (e.g. set it
  // back to 'in-progress' if it was completed prematurely, or cancel).
  // Also clears any pending progress request from the worker.

  Future<void> alterJobProgress({
    required String jobId,
    required String newStatus,
  }) async {
    try {
      await _firestore.collection('jobs').doc(jobId).update({
        'status':          newStatus,
        'progressRequest': FieldValue.delete(),   // clear any pending request
        'updatedAt':       FieldValue.serverTimestamp(),
      });

      debugPrint('Phase 6: job $jobId status altered to "$newStatus"');
    } catch (e) {
      throw Exception('Failed to alter job progress: $e');
    }
  }

  // ── Radius used when the job has a location ──────────────────────

  static const double _defaultNotificationRadiusKm = 25.0;

  // ── Nearby jobs query (for worker dashboard / map) ───────────────

  Future<List<JobModel>> getNearbyJobsForWorker({
    required String   category,
    required GeoPoint workerLocation,
    required double   radiusKm,
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

      final jobsWithLocation    = allJobs.where((j) => j.hasLocation).toList();
      final jobsWithoutLocation = allJobs.where((j) => !j.hasLocation).toList();

      final nearbyJobs = jobsWithLocation.where((job) {
        return _locationService.isWithinRadius(
          workerLocation,
          job.location!,
          radiusKm,
        );
      }).toList();

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
      final doc = await _firestore.collection('jobs').doc(jobId).get();
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