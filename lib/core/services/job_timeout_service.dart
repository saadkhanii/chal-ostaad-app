// lib/core/services/job_timeout_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class JobTimeoutService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Timer? _graceTimer;
  Timer? _workerStartTimer;

  void dispose() {
    _graceTimer?.cancel();
    _workerStartTimer?.cancel();
  }

  void watchJobTimeouts(String jobId, Function(String event) onTimeout) {
    _firestore.collection('jobs').doc(jobId).snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;
      final status = data['status'] as String?;

      final graceExpiry = (data['gracePeriodExpiry'] as Timestamp?)?.toDate();
      if (status == 'grace_period' && graceExpiry != null) {
        final now = DateTime.now();
        if (now.isAfter(graceExpiry)) {
          onTimeout('grace_period_expired');
        } else {
          _scheduleGraceTimer(graceExpiry, () => onTimeout('grace_period_expired'));
        }
      }

      final workerDeadline = (data['workerStartDeadline'] as Timestamp?)?.toDate();
      if ((status == 'active' || status == 'scheduled') && workerDeadline != null) {
        final now = DateTime.now();
        if (now.isAfter(workerDeadline)) {
          onTimeout('worker_start_deadline_expired');
        } else {
          _scheduleWorkerStartTimer(workerDeadline, () => onTimeout('worker_start_deadline_expired'));
        }
      }
    });
  }

  void _scheduleGraceTimer(DateTime expiry, VoidCallback onExpired) {
    _graceTimer?.cancel();
    final delay = expiry.difference(DateTime.now());
    if (delay.isNegative) {
      onExpired();
    } else {
      _graceTimer = Timer(delay, onExpired);
    }
  }

  void _scheduleWorkerStartTimer(DateTime expiry, VoidCallback onExpired) {
    _workerStartTimer?.cancel();
    final delay = expiry.difference(DateTime.now());
    if (delay.isNegative) {
      onExpired();
    } else {
      _workerStartTimer = Timer(delay, onExpired);
    }
  }

  Future<void> onGracePeriodExpired(String jobId) async {
    await _firestore.collection('jobs').doc(jobId).get();
  }

  Future<void> onWorkerStartDeadlineExpired(String jobId) async {
    await _firestore.collection('jobs').doc(jobId).get();
  }
}