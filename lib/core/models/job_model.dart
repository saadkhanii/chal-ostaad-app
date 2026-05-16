// lib/core/models/job_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

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
  final List<String> mediaUrls;
  final List<String> mediaTypes;
  final List<String> mediaBase64;  // legacy

  // ── Location fields ──────────────────────────────────────────────
  final GeoPoint? location;
  final String? locationAddress;
  final String? city;

  // ── Phase 1: Budget range & scheduling ───────────────────────────
  final double? recommendedAmountMin;
  final double? recommendedAmountMax;
  final Timestamp? scheduledAt;        // client's preferred start time
  final bool isUrgent;                 // NEW: ASAP/Urgent flag

  // ── Start agreement flow (NEW) ───────────────────────────────────
  final Timestamp? agreedStartTime;           // final agreed start time
  final Timestamp? startAgreementExpiry;      // when the 10-min window ends
  final Timestamp? startAgreementCreatedAt;   // when the agreement was made
  final String? startAgreementStatus;         // 'pending', 'confirmed', 'cancelled'

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
    this.recommendedAmountMin,
    this.recommendedAmountMax,
    this.scheduledAt,
    this.isUrgent = false,
    this.agreedStartTime,
    this.startAgreementExpiry,
    this.startAgreementCreatedAt,
    this.startAgreementStatus,
  });

  factory JobModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
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
      mediaBase64:     _parseStringList(data['mediaBase64']),
      location:        data['location']        as GeoPoint?,
      locationAddress: data['locationAddress'] as String?,
      city:            data['city']            as String?,
      recommendedAmountMin: _parseDouble(data['recommendedAmountMin']),
      recommendedAmountMax: _parseDouble(data['recommendedAmountMax']),
      scheduledAt:     data['scheduledAt'] as Timestamp?,
      isUrgent:        data['isUrgent']   ?? false,
      agreedStartTime: data['agreedStartTime'] as Timestamp?,
      startAgreementExpiry: data['startAgreementExpiry'] as Timestamp?,
      startAgreementCreatedAt: data['startAgreementCreatedAt'] as Timestamp?,
      startAgreementStatus: data['startAgreementStatus'] as String?,
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
      mediaBase64:     _parseStringList(data['mediaBase64']),
      location:        data['location']        as GeoPoint?,
      locationAddress: data['locationAddress'] as String?,
      city:            data['city']            as String?,
      recommendedAmountMin: _parseDouble(data['recommendedAmountMin']),
      recommendedAmountMax: _parseDouble(data['recommendedAmountMax']),
      scheduledAt:     data['scheduledAt'] as Timestamp?,
      isUrgent:        data['isUrgent']   ?? false,
      agreedStartTime: data['agreedStartTime'] as Timestamp?,
      startAgreementExpiry: data['startAgreementExpiry'] as Timestamp?,
      startAgreementCreatedAt: data['startAgreementCreatedAt'] as Timestamp?,
      startAgreementStatus: data['startAgreementStatus'] as String?,
    );
  }

  static List<Map<String, dynamic>> _parseExtraCharges(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return [];
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  static double? _parseDouble(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return null;
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
      if (mediaUrls.isNotEmpty) 'mediaUrls': mediaUrls,
      if (mediaTypes.isNotEmpty) 'mediaTypes': mediaTypes,
      if (location != null) 'location': location,
      if (locationAddress != null) 'locationAddress': locationAddress,
      if (city != null) 'city': city,
      if (recommendedAmountMin != null) 'recommendedAmountMin': recommendedAmountMin,
      if (recommendedAmountMax != null) 'recommendedAmountMax': recommendedAmountMax,
      if (scheduledAt != null) 'scheduledAt': scheduledAt,
      'isUrgent': isUrgent,
      if (agreedStartTime != null) 'agreedStartTime': agreedStartTime,
      if (startAgreementExpiry != null) 'startAgreementExpiry': startAgreementExpiry,
      if (startAgreementCreatedAt != null) 'startAgreementCreatedAt': startAgreementCreatedAt,
      if (startAgreementStatus != null) 'startAgreementStatus': startAgreementStatus,
    };
  }

  bool get hasLocation => location != null;
  bool get hasMedia => mediaUrls.isNotEmpty || mediaBase64.isNotEmpty;
  bool get hasUrlMedia => mediaUrls.isNotEmpty;
  bool get hasLegacyMedia => mediaUrls.isEmpty && mediaBase64.isNotEmpty;
  double? get latitude => location?.latitude;
  double? get longitude => location?.longitude;
  String get displayLocation => locationAddress ?? city ?? 'Location not specified';
  bool get isPaid => paymentStatus == 'paid';
  bool get isCash => paymentMethod == 'cash';
  bool get isDeleted => status == 'deleted';
  bool get isCancelled => status == 'cancelled';
  bool get hasBudget => recommendedAmountMin != null && recommendedAmountMax != null;
  String get budgetDisplay {
    if (!hasBudget) return 'Not specified';
    final min = recommendedAmountMin!.toStringAsFixed(0);
    final max = recommendedAmountMax!.toStringAsFixed(0);
    return 'PKR $min – $max';
  }
  bool get hasSchedule => scheduledAt != null;
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
  List<Map<String, dynamic>> get pendingExtraCharges => extraCharges.where((c) => c['status'] == 'pending').toList();
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
    double? recommendedAmountMin,
    double? recommendedAmountMax,
    Timestamp? scheduledAt,
    bool? isUrgent,
    Timestamp? agreedStartTime,
    Timestamp? startAgreementExpiry,
    Timestamp? startAgreementCreatedAt,
    String? startAgreementStatus,
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
      mediaUrls: mediaUrls ?? this.mediaUrls,
      mediaTypes: mediaTypes ?? this.mediaTypes,
      mediaBase64: mediaBase64 ?? this.mediaBase64,
      location: location ?? this.location,
      locationAddress: locationAddress ?? this.locationAddress,
      city: city ?? this.city,
      recommendedAmountMin: recommendedAmountMin ?? this.recommendedAmountMin,
      recommendedAmountMax: recommendedAmountMax ?? this.recommendedAmountMax,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      isUrgent: isUrgent ?? this.isUrgent,
      agreedStartTime: agreedStartTime ?? this.agreedStartTime,
      startAgreementExpiry: startAgreementExpiry ?? this.startAgreementExpiry,
      startAgreementCreatedAt: startAgreementCreatedAt ?? this.startAgreementCreatedAt,
      startAgreementStatus: startAgreementStatus ?? this.startAgreementStatus,
    );
  }
}