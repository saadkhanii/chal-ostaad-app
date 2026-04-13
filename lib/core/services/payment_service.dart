// lib/core/services/payment_service.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import '../models/payment_model.dart';

class PaymentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  // ── Your Cloud Function URL ──────────────────────────────────────
  // After deploying: firebase deploy --only functions
  // Get URL from Firebase Console → Functions → your function → trigger URL
  // Looks like: https://us-central1-chalostaad.cloudfunctions.net/createPaymentIntent
  static const String _cloudFunctionUrl =
      'https://chal-ostaad-backend-o00de13dw-saadkhaniis-projects.vercel.app/api/createPaymentIntent'; // 👈 replace after deploying

  // ── Main payment method ──────────────────────────────────────────
  Future<String> processStripePayment({
    required double amount,
    required String jobId,
    required String clientId,
    required String workerId,
    required String jobTitle,
  }) async {
    // 1. Create PaymentIntent via Cloud Function
    final clientSecret = await _createPaymentIntent(
      amount:   amount,
      jobId:    jobId,
      clientId: clientId,
    );

    // 2. Initialize Stripe payment sheet
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName:       'Chal Ostaad',
        style:                     ThemeMode.system,
        appearance: PaymentSheetAppearance(
          colors: PaymentSheetAppearanceColors(
            primary: const Color(0xFF4CAF50),
          ),
        ),
      ),
    );

    // 3. Show Stripe payment sheet — user enters card details
    await Stripe.instance.presentPaymentSheet();

    // 4. If we reach here, payment succeeded — save to Firestore
    final paymentId = await _savePaymentToFirestore(
      amount:   amount,
      jobId:    jobId,
      jobTitle: jobTitle,
      clientId: clientId,
      workerId: workerId,
    );

    return paymentId;
  }

  // ── Create PaymentIntent via Firebase Cloud Function ─────────────
  Future<String> _createPaymentIntent({
    required double amount,
    required String jobId,
    required String clientId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_cloudFunctionUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount':   amount,
          'currency': 'usd',
          'jobId':    jobId,
          'clientId': clientId,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.body}');
      }

      final data = jsonDecode(response.body);
      return data['clientSecret'] as String;
    } catch (e) {
      throw Exception('Failed to connect to payment server: $e');
    }
  }

  // ── Save payment record to Firestore ─────────────────────────────
  Future<String> _savePaymentToFirestore({
    required double amount,
    required String jobId,
    required String jobTitle,
    required String clientId,
    required String workerId,
  }) async {
    final docRef = await _firestore.collection('payments').add({
      'jobId':       jobId,
      'jobTitle':    jobTitle,
      'clientId':    clientId,
      'workerId':    workerId,
      'amount':      amount,
      'method':      'stripe',
      'status':      'completed',
      'createdAt':   FieldValue.serverTimestamp(),
      'completedAt': FieldValue.serverTimestamp(),
    });

    // Mark job as paid
    await _firestore.collection('jobs').doc(jobId).update({
      'paymentStatus': 'paid',
      'paymentId':     docRef.id,
      'updatedAt':     FieldValue.serverTimestamp(),
    });

    debugPrint('PaymentService: saved payment ${docRef.id}');
    return docRef.id;
  }

  // ── Check if job is already paid ─────────────────────────────────
  Future<bool> isJobPaid(String jobId) async {
    try {
      final snap = await _firestore
          .collection('payments')
          .where('jobId',  isEqualTo: jobId)
          .where('status', isEqualTo: 'completed')
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Get payment for a specific job ───────────────────────────────
  Future<PaymentModel?> getPaymentByJobId(String jobId) async {
    try {
      final snap = await _firestore
          .collection('payments')
          .where('jobId',  isEqualTo: jobId)
          .where('status', isEqualTo: 'completed')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return PaymentModel.fromSnapshot(snap.docs.first);
    } catch (_) {
      return null;
    }
  }

  // ── Stream payments for wallet screen ────────────────────────────
  Stream<List<PaymentModel>> streamPaymentsByClient(String clientId) {
    return _firestore
        .collection('payments')
        .where('clientId', isEqualTo: clientId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => PaymentModel.fromSnapshot(d)).toList());
  }

  Stream<List<PaymentModel>> streamPaymentsByWorker(String workerId) {
    return _firestore
        .collection('payments')
        .where('workerId', isEqualTo: workerId)
        .where('status',   isEqualTo: 'completed')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => PaymentModel.fromSnapshot(d)).toList());
  }
}