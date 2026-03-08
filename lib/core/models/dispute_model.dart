// lib/core/models/dispute_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class DisputeModel {
  final String?    id;
  final String     jobId;
  final String     jobTitle;
  final String     clientId;
  final String     clientName;
  final String     workerId;
  final String     workerName;

  // Who raised it
  final String     raisedBy;      // 'client' | 'worker'
  final String     raisedById;

  // Reason + details
  final String     reason;        // dropdown value
  final String     description;

  // Evidence — both sides can provide one
  final String?    clientEvidence;   // base64 image from client
  final String?    workerEvidence;   // base64 image from worker

  // Admin resolution
  final String     status;        // 'open' | 'reviewing' | 'resolved' | 'closed'
  final String?    resolution;    // 'favor_client' | 'favor_worker' | 'mutual'
  final String?    adminNote;

  final Timestamp  createdAt;
  final Timestamp? resolvedAt;

  const DisputeModel({
    this.id,
    required this.jobId,
    required this.jobTitle,
    required this.clientId,
    required this.clientName,
    required this.workerId,
    required this.workerName,
    required this.raisedBy,
    required this.raisedById,
    required this.reason,
    required this.description,
    this.clientEvidence,
    this.workerEvidence,
    required this.status,
    this.resolution,
    this.adminNote,
    required this.createdAt,
    this.resolvedAt,
  });

  // ── From Firestore ─────────────────────────────────────────────
  factory DisputeModel.fromMap(Map<String, dynamic> map, String docId) {
    return DisputeModel(
      id:             docId,
      jobId:          map['jobId']       as String? ?? '',
      jobTitle:       map['jobTitle']    as String? ?? '',
      clientId:       map['clientId']    as String? ?? '',
      clientName:     map['clientName']  as String? ?? '',
      workerId:       map['workerId']    as String? ?? '',
      workerName:     map['workerName']  as String? ?? '',
      raisedBy:       map['raisedBy']    as String? ?? '',
      raisedById:     map['raisedById']  as String? ?? '',
      reason:         map['reason']      as String? ?? '',
      description:    map['description'] as String? ?? '',
      clientEvidence: map['clientEvidence'] as String?,
      workerEvidence: map['workerEvidence'] as String?,
      status:         map['status']      as String? ?? 'open',
      resolution:     map['resolution']  as String?,
      adminNote:      map['adminNote']   as String?,
      createdAt:      map['createdAt']   as Timestamp? ?? Timestamp.now(),
      resolvedAt:     map['resolvedAt']  as Timestamp?,
    );
  }

  factory DisputeModel.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    return DisputeModel.fromMap(snap.data()!, snap.id);
  }

  // ── To Firestore ───────────────────────────────────────────────
  Map<String, dynamic> toMap() {
    return {
      'jobId':          jobId,
      'jobTitle':       jobTitle,
      'clientId':       clientId,
      'clientName':     clientName,
      'workerId':       workerId,
      'workerName':     workerName,
      'raisedBy':       raisedBy,
      'raisedById':     raisedById,
      'reason':         reason,
      'description':    description,
      'clientEvidence': clientEvidence,
      'workerEvidence': workerEvidence,
      'status':         status,
      'resolution':     resolution,
      'adminNote':      adminNote,
      'createdAt':      createdAt,
      'resolvedAt':     resolvedAt,
    };
  }

  // ── Helpers ────────────────────────────────────────────────────
  bool get isOpen       => status == 'open';
  bool get isReviewing  => status == 'reviewing';
  bool get isResolved   => status == 'resolved';
  bool get isClosed     => status == 'closed';
  bool get isActive     => status == 'open' || status == 'reviewing';

  String get raisedByLabel => raisedBy == 'client' ? clientName : workerName;

  String get resolutionLabel {
    switch (resolution) {
      case 'favor_client': return 'In favour of Client';
      case 'favor_worker': return 'In favour of Worker';
      case 'mutual':       return 'Mutual Resolution';
      default:             return '';
    }
  }
}

// ── Dispute reasons ────────────────────────────────────────────────
class DisputeReasons {
  static const List<String> all = [
    'Work not completed',
    'Poor quality work',
    'Payment issue',
    'Worker did not show up',
    'Client unresponsive',
    'Harassment or misconduct',
    'Other',
  ];
}