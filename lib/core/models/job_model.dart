// lib/core/models/job_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Job status lifecycle:
///   open  →  in-progress  →  completed
///                          ↘  cancelled  (either party)
///   open  →  deleted        (client only, no bids accepted yet)
class JobModel {
  final String? id;
  final String title;
  final String description;
  final String category;
  final String clientId;
  final Timestamp createdAt;
  final String status; // 'open' | 'in-progress' | 'completed' | 'cancelled' | 'deleted'

  // ── Payment ──────────────────────────────────────────────────────
  final String? paymentStatus; // 'unpaid' | 'paid'
  final String? paymentMethod; // 'stripe' | 'cash'
  final String? paymentId;

  // ── Extra charges ────────────────────────────────────────────────
  // List of charge maps: { id, amount, description, requestedBy,
  //                        status('pending'|'approved'|'rejected'), createdAt }
  final List<Map<String, dynamic>> extraCharges;

  // ── Location fields ──────────────────────────────────────────────
  final GeoPoint? location;
  final String? locationAddress;
  final String? city;

  JobModel({
    this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.clientId,
    required this.createdAt,
    this.status = 'open',
    this.paymentStatus,
    this.paymentMethod,
    this.paymentId,
    this.extraCharges = const [],
    this.location,
    this.locationAddress,
    this.city,
  });

  factory JobModel.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data()!;
    return JobModel(
      id: document.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? '',
      clientId: data['clientId'] ?? '',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      status: data['status'] ?? 'open',
      paymentStatus: data['paymentStatus'] as String?,
      paymentMethod: data['paymentMethod'] as String?,
      paymentId: data['paymentId'] as String?,
      extraCharges: _parseExtraCharges(data['extraCharges']),
      location: data['location'] as GeoPoint?,
      locationAddress: data['locationAddress'] as String?,
      city: data['city'] as String?,
    );
  }

  factory JobModel.fromMap(Map<String, dynamic> data, String id) {
    return JobModel(
      id: id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? '',
      clientId: data['clientId'] ?? '',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      status: data['status'] ?? 'open',
      paymentStatus: data['paymentStatus'] as String?,
      paymentMethod: data['paymentMethod'] as String?,
      paymentId: data['paymentId'] as String?,
      extraCharges: _parseExtraCharges(data['extraCharges']),
      location: data['location'] as GeoPoint?,
      locationAddress: data['locationAddress'] as String?,
      city: data['city'] as String?,
    );
  }

  static List<Map<String, dynamic>> _parseExtraCharges(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'category': category,
      'clientId': clientId,
      'createdAt': createdAt,
      'status': status,
      if (paymentStatus != null) 'paymentStatus': paymentStatus,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (paymentId != null) 'paymentId': paymentId,
      if (extraCharges.isNotEmpty) 'extraCharges': extraCharges,
      if (location != null) 'location': location,
      if (locationAddress != null) 'locationAddress': locationAddress,
      if (city != null) 'city': city,
    };
  }

  // ── Helpers ──────────────────────────────────────────────────────
  bool get hasLocation => location != null;
  double? get latitude => location?.latitude;
  double? get longitude => location?.longitude;
  String get displayLocation =>
      locationAddress ?? city ?? 'Location not specified';

  bool get isPaid => paymentStatus == 'paid';
  bool get isCash => paymentMethod == 'cash';
  bool get isDeleted => status == 'deleted';
  bool get isCancelled => status == 'cancelled';

  /// Sum of base bid + all APPROVED extra charges
  double totalWithExtras(double baseAmount) {
    final approved = extraCharges
        .where((c) => c['status'] == 'approved')
        .fold<double>(0, (sum, c) {
      final amt = c['amount'];
      if (amt is num) return sum + amt.toDouble();
      return sum;
    });
    return baseAmount + approved;
  }

  /// Pending extra charges (not yet approved/rejected)
  List<Map<String, dynamic>> get pendingExtraCharges =>
      extraCharges.where((c) => c['status'] == 'pending').toList();

  bool get hasPendingExtraCharges => pendingExtraCharges.isNotEmpty;

  JobModel copyWith({
    String? id,
    String? title,
    String? description,
    String? category,
    String? clientId,
    Timestamp? createdAt,
    String? status,
    String? paymentStatus,
    String? paymentMethod,
    String? paymentId,
    List<Map<String, dynamic>>? extraCharges,
    GeoPoint? location,
    String? locationAddress,
    String? city,
  }) {
    return JobModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      clientId: clientId ?? this.clientId,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentId: paymentId ?? this.paymentId,
      extraCharges: extraCharges ?? this.extraCharges,
      location: location ?? this.location,
      locationAddress: locationAddress ?? this.locationAddress,
      city: city ?? this.city,
    );
  }
}