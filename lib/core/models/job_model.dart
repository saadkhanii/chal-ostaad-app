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

  // ── Location fields ──────────────────────────────────────────────
  final GeoPoint? location;        // lat/lng stored as Firestore GeoPoint
  final String? locationAddress;   // human-readable address shown in UI
  final String? city;              // for city-level filtering / display
  // ─────────────────────────────────────────────────────────────────

  JobModel({
    this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.clientId,
    required this.createdAt,
    this.status = 'open',
    // location (all optional so old jobs without coords still work)
    this.location,
    this.locationAddress,
    this.city,
  });

  // ── fromSnapshot ─────────────────────────────────────────────────
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
      // location
      location: data['location'] as GeoPoint?,
      locationAddress: data['locationAddress'] as String?,
      city: data['city'] as String?,
    );
  }

  // ── fromMap ──────────────────────────────────────────────────────
  factory JobModel.fromMap(Map<String, dynamic> data, String id) {
    return JobModel(
      id: id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? '',
      clientId: data['clientId'] ?? '',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      status: data['status'] ?? 'open',
      // location
      location: data['location'] as GeoPoint?,
      locationAddress: data['locationAddress'] as String?,
      city: data['city'] as String?,
    );
  }

  // ── toJson ───────────────────────────────────────────────────────
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'category': category,
      'clientId': clientId,
      'createdAt': createdAt,
      'status': status,
      // only write location fields when they have values
      if (location != null) 'location': location,
      if (locationAddress != null) 'locationAddress': locationAddress,
      if (city != null) 'city': city,
    };
  }

  // ── Helpers ──────────────────────────────────────────────────────

  /// Returns true if this job has a pinned location
  bool get hasLocation => location != null;

  /// Convenience getters for lat/lng
  double? get latitude => location?.latitude;
  double? get longitude => location?.longitude;

  /// Display-friendly location string
  String get displayLocation =>
      locationAddress ?? city ?? 'Location not specified';

  // ── copyWith (useful for local state updates) ────────────────────
  JobModel copyWith({
    String? id,
    String? title,
    String? description,
    String? category,
    String? clientId,
    Timestamp? createdAt,
    String? status,
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
      location: location ?? this.location,
      locationAddress: locationAddress ?? this.locationAddress,
      city: city ?? this.city,
    );
  }
}