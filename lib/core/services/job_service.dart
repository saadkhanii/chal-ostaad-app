import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import '../models/job_model.dart';
import 'notification_service.dart';
import 'client_service.dart';

class JobService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();
  final ClientService _clientService = ClientService();

  Future<String> createJob(JobModel job) async {
    try {
      final docRef = await _firestore.collection('jobs').add(job.toJson());

      // Send notifications to relevant workers
      try {
        final workerIds = await _notificationService.getRelevantWorkersForJob(job.category);
        if (workerIds.isNotEmpty) {
          final clientName = await _clientService.getClientName(job.clientId);
          await _notificationService.sendJobPostedNotification(
            jobId: docRef.id,
            jobTitle: job.title,
            clientId: job.clientId,
            clientName: clientName,
            workerIds: workerIds,
            category: job.category,
          );
          print('Notifications sent to ${workerIds.length} workers');
        }
      } catch (e) {
        print('Error sending job notifications: $e');
      }

      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create job: $e');
    }
  }

  Future<List<JobModel>> getJobsByClient(String clientId) async {
    try {
      final querySnapshot = await _firestore
          .collection('jobs')
          .where('clientId', isEqualTo: clientId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        return JobModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
      }).toList();
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
          .where('status', isEqualTo: 'open')
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        return JobModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
      }).toList();
    } catch (e) {
      debugPrint('Error getting jobs by category: $e');
      return [];
    }
  }

  Future<JobModel?> getJobById(String jobId) async {
    try {
      final doc = await _firestore.collection('jobs').doc(jobId).get();
      if (doc.exists) {
        return JobModel.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>);
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
        'status': status,
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