// lib/core/models/worker_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class WorkerModel {
  final String id;
  final String? name;
  final String? email;
  final String? phone;
  final String? cnic;
  final String? address;
  final String? dateOfBirth;
  final String? categoryId;
  final String? specialization;
  final List<String> skills;
  final String? experience;
  final int? serviceRadius;
  final String? availability;
  final String? officeId;
  final String? officeName;
  final String? officeCity;
  final String? profileImage;
  final String? verificationStatus;
  final Map<String, dynamic>? ratings;
  final int? completedJobs;
  final int? ongoingJobs;
  final int? totalEarnings;
  final int? monthlyEarnings;
  final double? averageRating;
  final int? totalReviews;
  final String? accountStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  WorkerModel({
    required this.id,
    this.name,
    this.email,
    this.phone,
    this.cnic,
    this.address,
    this.dateOfBirth,
    this.categoryId,
    this.specialization,
    this.skills = const [],
    this.experience,
    this.serviceRadius = 10,
    this.availability = 'full-time',
    this.officeId,
    this.officeName,
    this.officeCity,
    this.profileImage,
    this.verificationStatus = 'pending',
    this.ratings,
    this.completedJobs = 0,
    this.ongoingJobs = 0,
    this.totalEarnings = 0,
    this.monthlyEarnings = 0,
    this.averageRating,
    this.totalReviews = 0,
    this.accountStatus = 'active',
    this.createdAt,
    this.updatedAt,
  });

  factory WorkerModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data()!;
    final personalInfo = data['personalInfo'] as Map<String, dynamic>? ?? {};
    final workInfo = data['workInfo'] as Map<String, dynamic>? ?? {};
    final officeInfo = data['officeInfo'] as Map<String, dynamic>? ?? {};
    final verification = data['verification'] as Map<String, dynamic>? ?? {};
    final ratings = data['ratings'] as Map<String, dynamic>? ?? {};

    // Calculate stats from various sources
    final stats = _calculateStats(ratings, data);

    return WorkerModel(
      id: snapshot.id,
      name: personalInfo['name'] as String?,
      email: personalInfo['email'] as String?,
      phone: personalInfo['phone'] as String?,
      cnic: personalInfo['cnic'] as String?,
      address: personalInfo['address'] as String?,
      dateOfBirth: personalInfo['dateOfBirth'] as String?,
      categoryId: workInfo['categoryId'] as String?,
      specialization: workInfo['specialization'] as String?,
      skills: List<String>.from(workInfo['skills'] as List? ?? []),
      experience: workInfo['experience'] as String?,
      serviceRadius: workInfo['serviceRadius'] as int?,
      availability: workInfo['availability'] as String?,
      officeId: officeInfo['officeId'] as String?,
      officeName: officeInfo['officeName'] as String?,
      officeCity: officeInfo['officeCity'] as String?,
      profileImage: personalInfo['profileImage'] as String?,
      verificationStatus: verification['status'] as String?,
      ratings: ratings,
      completedJobs: stats['completedJobs'],
      ongoingJobs: stats['ongoingJobs'],
      totalEarnings: stats['totalEarnings'],
      monthlyEarnings: stats['monthlyEarnings'],
      averageRating: stats['averageRating'],
      totalReviews: stats['totalReviews'],
      accountStatus: (data['account'] as Map<String, dynamic>?)?['accountStatus'] as String? ?? 'active',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  static Map<String, dynamic> _calculateStats(
      Map<String, dynamic>? ratings, Map<String, dynamic> data) {

    // You might want to calculate these from actual job data
    // For now, using placeholder values or values from ratings
    final avgRating = (ratings?['average'] as num?)?.toDouble() ?? 0.0;
    final totalReviews = (ratings?['totalReviews'] as int?) ?? 0;

    // These would ideally come from a separate stats collection
    // For now, using defaults
    return {
      'completedJobs': 0,
      'ongoingJobs': 0,
      'totalEarnings': 0,
      'monthlyEarnings': 0,
      'averageRating': avgRating,
      'totalReviews': totalReviews,
    };
  }

  String get firstName => name?.split(' ').first ?? 'Worker';
  String get displaySpecialization => specialization ?? skills.firstOrNull ?? 'General Worker';
  bool get isVerified => verificationStatus == 'verified';
  bool get isActive => accountStatus == 'active';
}