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

  final String? paymentStatus;
  final String? paymentMethod;
  final String? paymentId;
  final List<Map<String, dynamic>> extraCharges;
  final List<String> mediaUrls;
  final List<String> mediaTypes;
  final List<String> mediaBase64;

  final GeoPoint? location;
  final String? locationAddress;
  final String? city;

  final double? recommendedAmountMin;
  final double? recommendedAmountMax;
  final Timestamp? scheduledAt;
  final bool isUrgent;

  final Timestamp? agreedStartTime;
  final Timestamp? startAgreementExpiry;
  final Timestamp? startAgreementCreatedAt;
  final String? startAgreementStatus;

  // NEW FLOW fields
  final List<String> bannedWorkerIds;
  final Timestamp? gracePeriodExpiry;
  final Timestamp? workerStartDeadline;
  final String? reopenedAs;
  final Map<String, dynamic>? pendingTimeProposal;
  final bool workerReachedLocation;   // ← new

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
    this.mediaUrls = const [],
    this.mediaTypes = const [],
    this.mediaBase64 = const [],
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
    this.bannedWorkerIds = const [],
    this.gracePeriodExpiry,
    this.workerStartDeadline,
    this.reopenedAs,
    this.pendingTimeProposal,
    this.workerReachedLocation = false,
  });

  factory JobModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
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
      mediaUrls: _parseStringList(data['mediaUrls']),
      mediaTypes: _parseStringList(data['mediaTypes']),
      mediaBase64: _parseStringList(data['mediaBase64']),
      location: data['location'] as GeoPoint?,
      locationAddress: data['locationAddress'] as String?,
      city: data['city'] as String?,
      recommendedAmountMin: _parseDouble(data['recommendedAmountMin']),
      recommendedAmountMax: _parseDouble(data['recommendedAmountMax']),
      scheduledAt: data['scheduledAt'] as Timestamp?,
      isUrgent: data['isUrgent'] ?? false,
      agreedStartTime: data['agreedStartTime'] as Timestamp?,
      startAgreementExpiry: data['startAgreementExpiry'] as Timestamp?,
      startAgreementCreatedAt: data['startAgreementCreatedAt'] as Timestamp?,
      startAgreementStatus: data['startAgreementStatus'] as String?,
      bannedWorkerIds: List<String>.from(data['bannedWorkerIds'] as List? ?? []),
      gracePeriodExpiry: data['gracePeriodExpiry'] as Timestamp?,
      workerStartDeadline: data['workerStartDeadline'] as Timestamp?,
      reopenedAs: data['reopenedAs'] as String?,
      pendingTimeProposal: data['pendingTimeProposal'] as Map<String, dynamic>?,
      workerReachedLocation: data['workerReachedLocation'] as bool? ?? false,
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
      mediaUrls: _parseStringList(data['mediaUrls']),
      mediaTypes: _parseStringList(data['mediaTypes']),
      mediaBase64: _parseStringList(data['mediaBase64']),
      location: data['location'] as GeoPoint?,
      locationAddress: data['locationAddress'] as String?,
      city: data['city'] as String?,
      recommendedAmountMin: _parseDouble(data['recommendedAmountMin']),
      recommendedAmountMax: _parseDouble(data['recommendedAmountMax']),
      scheduledAt: data['scheduledAt'] as Timestamp?,
      isUrgent: data['isUrgent'] ?? false,
      agreedStartTime: data['agreedStartTime'] as Timestamp?,
      startAgreementExpiry: data['startAgreementExpiry'] as Timestamp?,
      startAgreementCreatedAt: data['startAgreementCreatedAt'] as Timestamp?,
      startAgreementStatus: data['startAgreementStatus'] as String?,
      bannedWorkerIds: List<String>.from(data['bannedWorkerIds'] as List? ?? []),
      gracePeriodExpiry: data['gracePeriodExpiry'] as Timestamp?,
      workerStartDeadline: data['workerStartDeadline'] as Timestamp?,
      reopenedAs: data['reopenedAs'] as String?,
      pendingTimeProposal: data['pendingTimeProposal'] as Map<String, dynamic>?,
      workerReachedLocation: data['workerReachedLocation'] as bool? ?? false,
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
      if (bannedWorkerIds.isNotEmpty) 'bannedWorkerIds': bannedWorkerIds,
      if (gracePeriodExpiry != null) 'gracePeriodExpiry': gracePeriodExpiry,
      if (workerStartDeadline != null) 'workerStartDeadline': workerStartDeadline,
      if (reopenedAs != null) 'reopenedAs': reopenedAs,
      if (pendingTimeProposal != null) 'pendingTimeProposal': pendingTimeProposal,
      'workerReachedLocation': workerReachedLocation,
    };
  }

  bool get hasLocation => location != null;
  double? get latitude => location?.latitude;
  double? get longitude => location?.longitude;
  bool get hasMedia => mediaUrls.isNotEmpty || mediaBase64.isNotEmpty;
  String get displayLocation => locationAddress ?? city ?? 'Location not specified';
  bool get isPaid => paymentStatus == 'paid';
  bool get isCash => paymentMethod == 'cash';
  bool get hasBudget => recommendedAmountMin != null && recommendedAmountMax != null;
  String get budgetDisplay {
    if (!hasBudget) return 'Not specified';
    final min = recommendedAmountMin!.toStringAsFixed(0);
    final max = recommendedAmountMax!.toStringAsFixed(0);
    return 'PKR $min – $max';
  }
  bool get hasSchedule => scheduledAt != null;
}