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

  JobModel({
    this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.clientId,
    required this.createdAt,
    this.status = 'open',
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'category': category,
      'clientId': clientId,
      'createdAt': createdAt,
      'status': status,
    };
  }
}
