// lib/core/services/bid_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import '../models/bid_model.dart';
import '../models/job_model.dart';
import 'notification_service.dart';

class BidService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  // ── Create bid ────────────────────────────────────────────────────
  Future<String> createBid(BidModel bid) async {
    try {
      // Check if worker is banned
      final jobDoc = await _firestore.collection('jobs').doc(bid.jobId).get();
      if (jobDoc.exists) {
        final jobData = jobDoc.data()!;
        final banned = List<String>.from(jobData['bannedWorkerIds'] as List? ?? []);
        if (banned.contains(bid.workerId)) {
          throw Exception('You cannot bid on this job because you previously cancelled or no-showed.');
        }
      }

      final docRef = await _firestore.collection('bids').add(bid.toJson());
      try {
        final jobDoc2 = await _firestore.collection('jobs').doc(bid.jobId).get();
        final jobTitle = jobDoc2.data()?['title'] ?? 'a job';
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

  // ── Client accepts a bid (starts 60-second grace period) ─────────
  Future<void> acceptBidWithGrace(String bidId) async {
    final bidDoc = await _firestore.collection('bids').doc(bidId).get();
    if (!bidDoc.exists) throw Exception('Bid not found');
    final bidData = bidDoc.data()!;
    final jobId = bidData['jobId'] as String;
    final clientId = bidData['clientId'] as String;
    final workerId = bidData['workerId'] as String;

    // Check if job is still open
    final jobDoc = await _firestore.collection('jobs').doc(jobId).get();
    if (!jobDoc.exists) throw Exception('Job not found');
    if (jobDoc.data()?['status'] != 'open') throw Exception('Job is no longer open');

    final graceExpiry = Timestamp.fromDate(DateTime.now().add(const Duration(seconds: 60)));
    final batch = _firestore.batch();

    // Update this bid to 'accepted'
    batch.update(_firestore.collection('bids').doc(bidId), {
      'status': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update job: status = 'grace_period', set expiry, keep urgent flag as is
    batch.update(_firestore.collection('jobs').doc(jobId), {
      'status': 'grace_period',
      'gracePeriodExpiry': graceExpiry,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Notify worker that their bid was accepted (grace period started)
    try {
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
      debugPrint('Error sending grace period notification: $e');
    }
  }

  // ── Client cancels during grace period ────────────────────────────
  Future<void> cancelBidDuringGrace(String jobId) async {
    final jobDoc = await _firestore.collection('jobs').doc(jobId).get();
    if (!jobDoc.exists) throw Exception('Job not found');
    if (jobDoc.data()?['status'] != 'grace_period') throw Exception('Not in grace period');

    final batch = _firestore.batch();

    // Get the accepted bid
    final acceptedBidSnapshot = await _firestore
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();

    if (acceptedBidSnapshot.docs.isNotEmpty) {
      final acceptedBidId = acceptedBidSnapshot.docs.first.id;
      batch.update(_firestore.collection('bids').doc(acceptedBidId), {
        'status': 'pending', // revert to pending
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Revert job status to 'open' and clear grace expiry
    batch.update(_firestore.collection('jobs').doc(jobId), {
      'status': 'open',
      'gracePeriodExpiry': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Notify the worker that client cancelled
    if (acceptedBidSnapshot.docs.isNotEmpty) {
      final workerId = acceptedBidSnapshot.docs.first.data()['workerId'] as String;
      final jobTitle = jobDoc.data()?['title'] ?? 'a job';
      try {
        await _notificationService.sendBidStatusNotification(
          jobId: jobId,
          jobTitle: jobTitle,
          workerId: workerId,
          clientName: 'Client',
          status: 'cancelled_during_grace',
        );
      } catch (_) {}
    }
  }

  // ── Finalise acceptance after grace period ────────────────────────
  Future<void> finaliseAcceptance(String jobId) async {
    final jobDoc = await _firestore.collection('jobs').doc(jobId).get();
    if (!jobDoc.exists) throw Exception('Job not found');
    final jobData = jobDoc.data()!;
    if (jobData['status'] != 'grace_period') {
      // Already finalised or cancelled
      return;
    }

    final batch = _firestore.batch();
    final now = Timestamp.now();

    // Get accepted bid
    final acceptedBidSnapshot = await _firestore
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();

    String? acceptedWorkerId;
    if (acceptedBidSnapshot.docs.isNotEmpty) {
      acceptedWorkerId = acceptedBidSnapshot.docs.first.data()['workerId'] as String;
    } else {
      throw Exception('No accepted bid found');
    }

    // Reject all other pending bids
    final otherBids = await _firestore
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .where('status', isEqualTo: 'pending')
        .get();

    for (final doc in otherBids.docs) {
      batch.update(doc.reference, {
        'status': 'rejected',
        'updatedAt': now,
      });
      // Send rejection notification
      final workerId = doc.data()['workerId'] as String;
      final jobTitle = jobData['title'] ?? 'a job';
      try {
        await _notificationService.sendBidStatusNotification(
          jobId: jobId,
          jobTitle: jobTitle,
          workerId: workerId,
          clientName: 'Client',
          status: 'rejected',
        );
      } catch (_) {}
    }

    // Determine next status based on job type
    final isUrgent = jobData['isUrgent'] ?? false;
    String newStatus;
    Timestamp? workerDeadline;

    if (isUrgent) {
      newStatus = 'active';
      workerDeadline = Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 10)));
    } else {
      newStatus = 'scheduled';
      // For scheduled jobs: deadline = scheduledAt + 2 hours
      final scheduledAt = jobData['scheduledAt'] as Timestamp?;
      if (scheduledAt != null) {
        workerDeadline = Timestamp.fromDate(scheduledAt.toDate().add(const Duration(hours: 2)));
      } else {
        // Fallback: 2 hours from now (should not happen)
        workerDeadline = Timestamp.fromDate(DateTime.now().add(const Duration(hours: 2)));
      }
    }

    // Update job
    batch.update(_firestore.collection('jobs').doc(jobId), {
      'status': newStatus,
      'gracePeriodExpiry': FieldValue.delete(),
      if (workerDeadline != null) 'workerStartDeadline': workerDeadline,
      'updatedAt': now,
    });

    await batch.commit();

    // Notify accepted worker that job is ready
    if (acceptedWorkerId != null) {
      final jobTitle = jobData['title'] ?? 'a job';
      try {
        await _notificationService.sendBidStatusNotification(
          jobId: jobId,
          jobTitle: jobTitle,
          workerId: acceptedWorkerId,
          clientName: 'Client',
          status: 'finalised',
        );
      } catch (_) {}
    }
  }

  // ── Worker starts job (after ready) ───────────────────────────────
  Future<void> startJob(String jobId, String workerId, {bool shareLocation = true}) async {
    final jobDoc = await _firestore.collection('jobs').doc(jobId).get();
    if (!jobDoc.exists) throw Exception('Job not found');
    final jobData = jobDoc.data()!;
    final status = jobData['status'] as String?;
    if (status != 'active' && status != 'scheduled') {
      throw Exception('Job not ready to start');
    }

    // For scheduled jobs, ensure scheduled time has passed
    final isUrgent = jobData['isUrgent'] ?? false;
    if (!isUrgent) {
      final scheduledAt = (jobData['scheduledAt'] as Timestamp?)?.toDate();
      if (scheduledAt != null && DateTime.now().isBefore(scheduledAt)) {
        throw Exception('Job cannot start before scheduled time');
      }
    }

    // Check if worker is the accepted one
    final acceptedBid = await _firestore
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    if (acceptedBid.docs.isEmpty || acceptedBid.docs.first.data()['workerId'] != workerId) {
      throw Exception('You are not the accepted worker for this job');
    }

    final now = Timestamp.now();
    final batch = _firestore.batch();

    // Update job to 'in-progress'
    batch.update(_firestore.collection('jobs').doc(jobId), {
      'status': 'in-progress',
      'workerStartDeadline': FieldValue.delete(),
      'startedAt': now,
      if (shareLocation) 'locationSharingEnabled': true,
      'updatedAt': now,
    });

    await batch.commit();

    // Notify client that job started
    final clientId = jobData['clientId'] as String;
    final jobTitle = jobData['title'] ?? 'a job';
    try {
      await _notificationService.sendJobStatusNotification(
        jobId: jobId,
        jobTitle: jobTitle,
        clientId: clientId,
        status: 'started',
      );
    } catch (_) {}
  }

  // ── Worker cancels job (conditional reopen for scheduled jobs) ───────────
  Future<void> workerCancelJob(
      String jobId,
      String workerId, {
        String? reason,
        bool makeUrgent = false,
      }) async {
    final jobDoc = await _firestore.collection('jobs').doc(jobId).get();
    if (!jobDoc.exists) throw Exception('Job not found');
    final jobData = jobDoc.data()!;
    final status = jobData['status'] as String?;
    if (status != 'active' && status != 'scheduled') {
      throw Exception('Cannot cancel job at this stage');
    }

    // Check worker is the accepted one
    final acceptedBid = await _firestore
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    if (acceptedBid.docs.isEmpty || acceptedBid.docs.first.data()['workerId'] != workerId) {
      throw Exception('You are not the accepted worker');
    }

    final batch = _firestore.batch();
    final now = Timestamp.now();

    // Add worker to banned list
    final banned = List<String>.from(jobData['bannedWorkerIds'] as List? ?? []);
    if (!banned.contains(workerId)) {
      batch.update(_firestore.collection('jobs').doc(jobId), {
        'bannedWorkerIds': FieldValue.arrayUnion([workerId]),
      });
    }

    // Determine how to reopen based on job type and optional override
    final isUrgent = jobData['isUrgent'] ?? false;
    final scheduledAt = (jobData['scheduledAt'] as Timestamp?)?.toDate();

    bool reopenAsUrgent;
    if (makeUrgent) {
      reopenAsUrgent = true;
    } else if (isUrgent) {
      reopenAsUrgent = true;
    } else {
      // Scheduled job: check remaining time until scheduled start
      if (scheduledAt == null) {
        reopenAsUrgent = true; // fallback
      } else {
        final timeRemaining = scheduledAt.difference(DateTime.now());
        reopenAsUrgent = timeRemaining < const Duration(hours: 2);
      }
    }

    // Prepare job update
    final jobUpdate = <String, dynamic>{
      'status': 'open',
      'workerStartDeadline': FieldValue.delete(),
      if (reason != null) 'cancelReason': reason,
      'cancelledBy': 'worker',
      'cancelledAt': now,
      'updatedAt': now,
    };

    if (reopenAsUrgent) {
      jobUpdate['isUrgent'] = true;
      jobUpdate['reopenedAs'] = 'urgent';
      jobUpdate['scheduledAt'] = FieldValue.delete(); // remove scheduled time
    } else {
      // Keep original scheduled time, not urgent
      jobUpdate['isUrgent'] = false;
      jobUpdate['reopenedAs'] = 'scheduled';
      // scheduledAt remains unchanged
    }

    batch.update(_firestore.collection('jobs').doc(jobId), jobUpdate);

    // Update accepted bid status to cancelled
    batch.update(
      _firestore.collection('bids').doc(acceptedBid.docs.first.id),
      {'status': 'cancelled_by_worker', 'updatedAt': now},
    );

    await batch.commit();

    // Notify client
    final clientId = jobData['clientId'] as String;
    final jobTitle = jobData['title'] ?? 'a job';
    try {
      await _notificationService.sendJobStatusNotification(
        jobId: jobId,
        jobTitle: jobTitle,
        clientId: clientId,
        status: 'cancelled_by_worker',
      );
    } catch (_) {}
  }

  // ── Worker no-action timeout (called by Cloud Function) ───────────
  Future<void> workerNoActionTimeout(String jobId, String workerId) async {
    final jobDoc = await _firestore.collection('jobs').doc(jobId).get();
    if (!jobDoc.exists) return;
    final jobData = jobDoc.data()!;
    final status = jobData['status'] as String?;
    if (status != 'active' && status != 'scheduled') return;

    final batch = _firestore.batch();
    final now = Timestamp.now();

    // Add worker to banned list
    final banned = List<String>.from(jobData['bannedWorkerIds'] as List? ?? []);
    if (!banned.contains(workerId)) {
      batch.update(_firestore.collection('jobs').doc(jobId), {
        'bannedWorkerIds': FieldValue.arrayUnion([workerId]),
      });
    }

    batch.update(_firestore.collection('jobs').doc(jobId), {
      'status': 'open',
      'isUrgent': true,
      'reopenedAs': 'urgent',
      'workerStartDeadline': FieldValue.delete(),
      'cancelledBy': 'worker_no_action',
      'cancelledAt': now,
      'updatedAt': now,
    });

    // Also update bid status
    final timedOutBid = await _firestore
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    if (timedOutBid.docs.isNotEmpty) {
      batch.update(
        _firestore.collection('bids').doc(timedOutBid.docs.first.id),
        {'status': 'cancelled_no_action', 'updatedAt': now},
      );
    }

    await batch.commit();

    // Notify client
    final clientId = jobData['clientId'] as String;
    final jobTitle = jobData['title'] ?? 'a job';
    try {
      await _notificationService.sendJobStatusNotification(
        jobId: jobId,
        jobTitle: jobTitle,
        clientId: clientId,
        status: 'worker_no_show',
      );
    } catch (_) {}
  }

  // ── Worker proposes new time (for specific time jobs) ─────────────
  Future<void> proposeNewTime(String jobId, String workerId, DateTime proposedTime) async {
    final jobDoc = await _firestore.collection('jobs').doc(jobId).get();
    if (!jobDoc.exists) throw Exception('Job not found');
    final jobData = jobDoc.data()!;
    // Only allowed for specific time jobs that are in 'scheduled' state
    if (jobData['isUrgent'] == true) throw Exception('Cannot propose new time for urgent jobs');
    if (jobData['status'] != 'scheduled') throw Exception('Cannot propose new time now');

    // Check worker is accepted
    final acceptedBid = await _firestore
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    if (acceptedBid.docs.isEmpty || acceptedBid.docs.first.data()['workerId'] != workerId) {
      throw Exception('You are not the accepted worker');
    }

    await _firestore.collection('jobs').doc(jobId).update({
      'pendingTimeProposal': {
        'proposedBy': 'worker',
        'proposedTime': Timestamp.fromDate(proposedTime),
        'status': 'pending',
        'proposedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Notify client
    final clientId = jobData['clientId'] as String;
    final jobTitle = jobData['title'] ?? 'a job';
    try {
      await _notificationService.sendTimeProposalNotification(
        jobId: jobId,
        jobTitle: jobTitle,
        clientId: clientId,
        workerId: null,
        proposedBy: 'worker',
        proposedTime: proposedTime,
      );
    } catch (_) {}
  }

  // ── Client proposes new time (for specific time jobs) ─────────────
  Future<void> clientProposeNewTime(String jobId, String clientId, DateTime proposedTime) async {
    final jobDoc = await _firestore.collection('jobs').doc(jobId).get();
    if (!jobDoc.exists) throw Exception('Job not found');
    final jobData = jobDoc.data()!;
    // Only allowed for specific time jobs
    if (jobData['isUrgent'] == true) throw Exception('Cannot propose new time for urgent jobs');

    // Check client is the owner
    if (jobData['clientId'] != clientId) throw Exception('Not your job');

    // Get accepted worker
    final acceptedBid = await _firestore
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    if (acceptedBid.docs.isEmpty) throw Exception('No accepted bid found');
    final workerId = acceptedBid.docs.first.data()['workerId'] as String;

    await _firestore.collection('jobs').doc(jobId).update({
      'pendingTimeProposal': {
        'proposedBy': 'client',
        'proposedTime': Timestamp.fromDate(proposedTime),
        'status': 'pending',
        'proposedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Notify worker
    final jobTitle = jobData['title'] ?? 'a job';
    try {
      await _notificationService.sendTimeProposalNotification(
        jobId: jobId,
        jobTitle: jobTitle,
        clientId: null,
        workerId: workerId,
        proposedBy: 'client',
        proposedTime: proposedTime,
      );
    } catch (_) {}
  }

  // ── Respond to time proposal (accept/reject) ──────────────────────
  Future<void> respondToTimeProposal(String jobId, String responderId, bool accept, {DateTime? newTime}) async {
    final jobDoc = await _firestore.collection('jobs').doc(jobId).get();
    if (!jobDoc.exists) throw Exception('Job not found');
    final jobData = jobDoc.data()!;
    final proposal = jobData['pendingTimeProposal'] as Map<String, dynamic>?;
    if (proposal == null || proposal['status'] != 'pending') {
      throw Exception('No pending time proposal');
    }

    final proposedBy = proposal['proposedBy'] as String;
    final proposedTime = (proposal['proposedTime'] as Timestamp).toDate();

    // Check responder is the other party
    if (proposedBy == 'client' && responderId != jobData['clientId']) {
      throw Exception('Only worker can respond to client proposal');
    }
    if (proposedBy == 'worker') {
      if (responderId != jobData['clientId']) throw Exception('Only client can respond to worker proposal');
    }

    final batch = _firestore.batch();

    if (accept) {
      // Update job with new scheduled time
      final newScheduled = newTime ?? proposedTime;
      batch.update(_firestore.collection('jobs').doc(jobId), {
        'scheduledAt': Timestamp.fromDate(newScheduled),
        'pendingTimeProposal': FieldValue.delete(),
        'status': 'scheduled',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Also update workerStartDeadline based on new scheduled time
      final deadline = newScheduled.add(const Duration(hours: 2));
      batch.update(_firestore.collection('jobs').doc(jobId), {
        'workerStartDeadline': Timestamp.fromDate(deadline),
      });
    } else {
      // Reject: only mark proposal as rejected, do NOT reopen job or ban worker.
      // The worker will then see the rejected proposal and decide to continue or cancel.
      batch.update(_firestore.collection('jobs').doc(jobId), {
        'pendingTimeProposal.status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    // Notify both parties
    final jobTitle = jobData['title'] ?? 'a job';
    final clientId = jobData['clientId'] as String;
    final acceptedBid2 = await _firestore
        .collection('bids')
        .where('jobId', isEqualTo: jobId)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    if (acceptedBid2.docs.isNotEmpty) {
      final workerId2 = acceptedBid2.docs.first.data()['workerId'] as String;
      await _notificationService.sendTimeProposalResponseNotification(
        jobId: jobId,
        jobTitle: jobTitle,
        clientId: clientId,
        workerId: workerId2,
        accepted: accept,
      );
    }
  }

  // ── Accept worker's time proposal (client) ──────────────────────
  Future<void> acceptWorkerTimeProposal(String jobId, String clientId, DateTime newTime) async {
    await respondToTimeProposal(jobId, clientId, true, newTime: newTime);
  }

  // ── Reject worker's time proposal (client) ──────────────────────
  Future<void> rejectWorkerTimeProposal(String jobId, String clientId) async {
    await respondToTimeProposal(jobId, clientId, false);
  }

  // ── Clear time proposal (worker continues with original time) ──
  Future<void> clearTimeProposal(String jobId) async {
    await _firestore.collection('jobs').doc(jobId).update({
      'pendingTimeProposal': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Cancel job (legacy, for client) ───────────────────────────────
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