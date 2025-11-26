// lib/core/services/client_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';

class ClientService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final ClientService _instance = ClientService._internal();
  factory ClientService() => _instance;
  ClientService._internal();

  /// Get client name from client ID - uses the exact structure from signup
  Future<String> getClientName(String clientId) async {
    try {
      debugPrint('CLIENT SERVICE: Fetching name for client ID: $clientId');

      final clientDoc = await _firestore.collection('clients').doc(clientId).get();

      if (clientDoc.exists) {
        final clientData = clientDoc.data()!;

        // Extract name from personalInfo.fullName (exact structure from signup)
        final personalInfo = clientData['personalInfo'];
        if (personalInfo is Map<String, dynamic>) {
          final fullName = personalInfo['fullName'];
          if (fullName is String && fullName.trim().isNotEmpty) {
            debugPrint('CLIENT SERVICE: Found client name: $fullName');
            return fullName.trim();
          }
        }

        // Fallback: Check other possible name fields
        final name = _extractNameFromData(clientData);
        if (name.isNotEmpty) {
          debugPrint('CLIENT SERVICE: Found client name (fallback): $name');
          return name;
        }
      }

      debugPrint('CLIENT SERVICE: No client name found, using formatted ID');
      return 'Client ${clientId.substring(0, 8)}...';

    } catch (e) {
      debugPrint('CLIENT SERVICE: Error fetching client name: $e');
      return 'Client ${clientId.substring(0, 8)}...';
    }
  }

  /// Extract name from data using common field names as fallback
  String _extractNameFromData(Map<String, dynamic> data) {
    // Try direct fields first
    final directFields = ['name', 'fullName', 'userName', 'displayName'];
    for (final field in directFields) {
      final value = data[field];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    // Try personalInfo sub-fields
    final personalInfo = data['personalInfo'];
    if (personalInfo is Map<String, dynamic>) {
      for (final field in directFields) {
        final value = personalInfo[field];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }

    return '';
  }
}