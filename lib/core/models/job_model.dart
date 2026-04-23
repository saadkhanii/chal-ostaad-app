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
  final String status;

  // ── Payment ──────────────────────────────────────────────────────
  final String? paymentStatus;
  final String? paymentMethod;
  final String? paymentId;

  // ── Extra charges ────────────────────────────────────────────────
  final List<Map<String, dynamic>> extraCharges;

  // ── Media (new: Cloudinary URLs) ─────────────────────────────────
  // mediaUrls  : list of Cloudinary HTTPS URLs (images or videos)
  // mediaTypes : 'image' | 'video' for each entry in mediaUrls
  final List<String> mediaUrls;
  final List<String> mediaTypes;

  // ── Media (legacy: base64 photos) ────────────────────────────────
  // Kept read-only so old Firestore documents still display correctly.
  // New jobs never write to this field.
  final List<String> mediaBase64;

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
    this.mediaUrls    = const [],
    this.mediaTypes   = const [],
    this.mediaBase64  = const [],
    this.location,
    this.locationAddress,
    this.city,
  });

  factory JobModel.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data()!;
    return JobModel(
      id:              document.id,
      title:           data['title']       ?? '',
      description:     data['description'] ?? '',
      category:        data['category']    ?? '',
      clientId:        data['clientId']    ?? '',
      createdAt:       data['createdAt']   ?? Timestamp.now(),
      status:          data['status']      ?? 'open',
      paymentStatus:   data['paymentStatus'] as String?,
      paymentMethod:   data['paymentMethod'] as String?,
      paymentId:       data['paymentId']     as String?,
      extraCharges:    _parseExtraCharges(data['extraCharges']),
      mediaUrls:       _parseStringList(data['mediaUrls']),
      mediaTypes:      _parseStringList(data['mediaTypes']),
      mediaBase64:     _parseStringList(data['mediaBase64']),  // legacy
      location:        data['location']        as GeoPoint?,
      locationAddress: data['locationAddress'] as String?,
      city:            data['city']            as String?,
    );
  }

  factory JobModel.fromMap(Map<String, dynamic> data, String id) {
    return JobModel(
      id:              id,
      title:           data['title']       ?? '',
      description:     data['description'] ?? '',
      category:        data['category']    ?? '',
      clientId:        data['clientId']    ?? '',
      createdAt:       data['createdAt']   ?? Timestamp.now(),
      status:          data['status']      ?? 'open',
      paymentStatus:   data['paymentStatus'] as String?,
      paymentMethod:   data['paymentMethod'] as String?,
      paymentId:       data['paymentId']     as String?,
      extraCharges:    _parseExtraCharges(data['extraCharges']),
      mediaUrls:       _parseStringList(data['mediaUrls']),
      mediaTypes:      _parseStringList(data['mediaTypes']),
      mediaBase64:     _parseStringList(data['mediaBase64']),  // legacy
      location:        data['location']        as GeoPoint?,
      locationAddress: data['locationAddress'] as String?,
      city:            data['city']            as String?,
    );
  }

  static List<Map<String, dynamic>> _parseExtraCharges(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  Map<String, dynamic> toJson() {
    return {
      'title':       title,
      'description': description,
      'category':    category,
      'clientId':    clientId,
      'createdAt':   createdAt,
      'status':      status,
      if (paymentStatus        != null) 'paymentStatus':   paymentStatus,
      if (paymentMethod        != null) 'paymentMethod':   paymentMethod,
      if (paymentId            != null) 'paymentId':       paymentId,
      if (extraCharges.isNotEmpty)      'extraCharges':    extraCharges,
      if (mediaUrls.isNotEmpty)         'mediaUrls':       mediaUrls,
      if (mediaTypes.isNotEmpty)        'mediaTypes':      mediaTypes,
      // mediaBase64 intentionally NOT written — old docs keep their own value
      if (location             != null) 'location':        location,
      if (locationAddress      != null) 'locationAddress': locationAddress,
      if (city                 != null) 'city':            city,
    };
  }

  // ── Helpers ──────────────────────────────────────────────────────
  bool get hasLocation => location != null;

  /// True if the job has any media (new URL-based or legacy base64).
  bool get hasMedia => mediaUrls.isNotEmpty || mediaBase64.isNotEmpty;

  /// True if the job uses the new Cloudinary URL media system.
  bool get hasUrlMedia => mediaUrls.isNotEmpty;

  /// True if the job only has legacy base64 media (older jobs).
  bool get hasLegacyMedia => mediaUrls.isEmpty && mediaBase64.isNotEmpty;

  double? get latitude  => location?.latitude;
  double? get longitude => location?.longitude;
  String get displayLocation =>
      locationAddress ?? city ?? 'Location not specified';

  bool get isPaid      => paymentStatus == 'paid';
  bool get isCash      => paymentMethod == 'cash';
  bool get isDeleted   => status == 'deleted';
  bool get isCancelled => status == 'cancelled';

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
    List<String>? mediaUrls,
    List<String>? mediaTypes,
    List<String>? mediaBase64,
    GeoPoint? location,
    String? locationAddress,
    String? city,
  }) {
    return JobModel(
      id:              id              ?? this.id,
      title:           title           ?? this.title,
      description:     description     ?? this.description,
      category:        category        ?? this.category,
      clientId:        clientId        ?? this.clientId,
      createdAt:       createdAt       ?? this.createdAt,
      status:          status          ?? this.status,
      paymentStatus:   paymentStatus   ?? this.paymentStatus,
      paymentMethod:   paymentMethod   ?? this.paymentMethod,
      paymentId:       paymentId       ?? this.paymentId,
      extraCharges:    extraCharges    ?? this.extraCharges,
      mediaUrls:       mediaUrls       ?? this.mediaUrls,
      mediaTypes:      mediaTypes      ?? this.mediaTypes,
      mediaBase64:     mediaBase64     ?? this.mediaBase64,
      location:        location        ?? this.location,
      locationAddress: locationAddress ?? this.locationAddress,
      city:            city            ?? this.city,
    );
  }
}