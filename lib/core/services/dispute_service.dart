// lib/core/services/dispute_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/dispute_model.dart';

class DisputeService {
  final _db = FirebaseFirestore.instance;

  // ── Raise a new dispute ────────────────────────────────────────
  // Returns error string if not allowed, null on success.
  Future<String?> raiseDispute({
    required String jobId,
    required String jobTitle,
    required String clientId,
    required String clientName,
    required String workerId,
    required String workerName,
    required String raisedBy,      // 'client' | 'worker'
    required String raisedById,
    required String reason,
    required String description,
    String?         evidenceBase64, // the raiser's evidence
  }) async {
    try {
      // ── Rule: only one active dispute per job ──────────────────
      final existing = await _db
          .collection('disputes')
          .where('jobId',  isEqualTo: jobId)
          .where('status', whereIn: ['open', 'reviewing'])
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        return 'A dispute is already active for this job.';
      }

      // ── Rule: worker freeze — block if 3+ open disputes ───────
      if (raisedBy == 'worker') {
        final workerDisputes = await _db
            .collection('disputes')
            .where('workerId', isEqualTo: workerId)
            .where('status',   whereIn: ['open', 'reviewing'])
            .get();

        if (workerDisputes.docs.length >= 3) {
          return 'You have too many open disputes. '
              'Please wait for existing disputes to be resolved.';
        }
      }

      // ── Build evidence fields ──────────────────────────────────
      final clientEvidence =
      raisedBy == 'client' ? evidenceBase64 : null;
      final workerEvidence =
      raisedBy == 'worker' ? evidenceBase64 : null;

      // ── Write to Firestore ─────────────────────────────────────
      await _db.collection('disputes').add(
        DisputeModel(
          jobId:          jobId,
          jobTitle:       jobTitle,
          clientId:       clientId,
          clientName:     clientName,
          workerId:       workerId,
          workerName:     workerName,
          raisedBy:       raisedBy,
          raisedById:     raisedById,
          reason:         reason,
          description:    description,
          clientEvidence: clientEvidence,
          workerEvidence: workerEvidence,
          status:         'open',
          createdAt:      Timestamp.now(),
        ).toMap(),
      );

      // ── Notify the other party in-app ────────────────────────
      final notifyUserId = raisedBy == 'client' ? workerId : clientId;
      final raisedByName = raisedBy == 'client' ? clientName : workerName;
      try {
        await _db.collection('notifications').add({
          'userId':    notifyUserId,
          'title':     'Dispute Raised',
          'body':      '$raisedByName has raised a dispute on "$jobTitle".',
          'type':      'dispute',
          'jobId':     jobId,
          'isRead':    false,
          'createdAt': Timestamp.now(),
        });
      } catch (_) {} // notification failure must not block dispute creation

      return null; // success
    } catch (e) {
      return 'Failed to raise dispute: $e';
    }
  }

  // ── Add / update evidence for the OTHER party ─────────────────
  // Called when the non-raiser wants to submit their side.
  Future<void> addEvidence({
    required String disputeId,
    required String role,          // 'client' | 'worker'
    required String evidenceBase64,
  }) async {
    final field =
    role == 'client' ? 'clientEvidence' : 'workerEvidence';
    await _db.collection('disputes').doc(disputeId).update({
      field: evidenceBase64,
    });
  }

  // ── Stream: dispute for a specific job (if any) ────────────────
  Stream<DisputeModel?> jobDisputeStream(String jobId) {
    return _db
        .collection('disputes')
        .where('jobId', isEqualTo: jobId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      return DisputeModel.fromMap(
          snap.docs.first.data(), snap.docs.first.id);
    });
  }

  // ── Stream: all disputes for a user (client or worker) ─────────
  Stream<List<DisputeModel>> userDisputesStream({
    required String userId,
    required String role, // 'client' | 'worker'
  }) {
    final field = role == 'client' ? 'clientId' : 'workerId';
    return _db
        .collection('disputes')
        .where(field, isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
        .map((d) => DisputeModel.fromMap(d.data(), d.id))
        .toList());
  }

  // ── Check: does this job already have an active dispute? ───────
  Future<bool> hasActiveDispute(String jobId) async {
    final snap = await _db
        .collection('disputes')
        .where('jobId',  isEqualTo: jobId)
        .where('status', whereIn: ['open', 'reviewing'])
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  // ── Fetch single dispute by job (one-time) ─────────────────────
  Future<DisputeModel?> getDisputeByJob(String jobId) async {
    final snap = await _db
        .collection('disputes')
        .where('jobId', isEqualTo: jobId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return DisputeModel.fromMap(snap.docs.first.data(), snap.docs.first.id);
  }
}