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

  static const String _cloudFunctionUrl =
      'https://chal-ostaad-backend.vercel.app/api/createPaymentIntent';

  // ── Platform fee percentage (taken by the platform) ──────────────
  // 5 % of the total job amount. Adjust as needed.
  static const double platformFeePercent = 5.0;

  static double calcPlatformFee(double amount) =>
      (amount * platformFeePercent / 100);

  // ── Stripe payment ────────────────────────────────────────────────
  Future<String> processStripePayment({
    required double amount,
    required String jobId,
    required String clientId,
    required String workerId,
    required String jobTitle,
  }) async {
    final clientSecret = await _createPaymentIntent(
      amount:   amount,
      jobId:    jobId,
      clientId: clientId,
    );

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'Chal Ostaad',
        style: ThemeMode.system,
        appearance: PaymentSheetAppearance(
          colors: PaymentSheetAppearanceColors(
            primary: const Color(0xFF4CAF50),
          ),
        ),
      ),
    );

    await Stripe.instance.presentPaymentSheet();

    final paymentId = await _savePaymentToFirestore(
      amount:    amount,
      jobId:     jobId,
      jobTitle:  jobTitle,
      clientId:  clientId,
      workerId:  workerId,
      method:    'stripe',
    );

    return paymentId;
  }

  // ── Cash payment ──────────────────────────────────────────────────
  /// Called by client — records intent to pay cash.
  /// The job stays in 'in-progress'; worker must later confirm receipt.
  Future<String> recordCashPaymentIntent({
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
      'method':      'cash',
      'status':      'pending',              // worker still needs to confirm
      'createdAt':   FieldValue.serverTimestamp(),
      'cashConfirmedByWorker': false,
    });

    // Mark the job payment method so both sides know cash is chosen
    await _firestore.collection('jobs').doc(jobId).update({
      'paymentMethod': 'cash',
      'paymentId':     docRef.id,
      'updatedAt':     FieldValue.serverTimestamp(),
    });

    debugPrint('PaymentService: cash intent recorded ${docRef.id}');
    return docRef.id;
  }

  /// Called by worker — confirms they received the cash.
  /// Marks payment as completed and job status → completed.
  Future<void> confirmCashReceived({
    required String paymentId,
    required String jobId,
  }) async {
    final batch = _firestore.batch();

    batch.update(_firestore.collection('payments').doc(paymentId), {
      'status':                'completed',
      'cashConfirmedByWorker': true,
      'cashConfirmedAt':       FieldValue.serverTimestamp(),
      'completedAt':           FieldValue.serverTimestamp(),
    });

    batch.update(_firestore.collection('jobs').doc(jobId), {
      'paymentStatus': 'paid',
      'status':        'completed',
      'updatedAt':     FieldValue.serverTimestamp(),
    });

    await batch.commit();
    debugPrint('PaymentService: cash confirmed for payment $paymentId');
  }

  // ── Extra charges ─────────────────────────────────────────────────
  /// Either party can add a charge. The other party must approve it.
  Future<void> addExtraCharge({
    required String jobId,
    required double amount,
    required String description,
    required String requestedBy, // 'client' | 'worker'
  }) async {
    final charge = {
      'id':          _firestore.collection('_').doc().id,
      'amount':      amount,
      'description': description,
      'requestedBy': requestedBy,
      'status':      'pending',
      'createdAt':   Timestamp.now(),
    };

    await _firestore.collection('jobs').doc(jobId).update({
      'extraCharges': FieldValue.arrayUnion([charge]),
      'updatedAt':    FieldValue.serverTimestamp(),
    });
  }

  /// Approve or reject an extra charge by its id.
  /// We rewrite the entire extraCharges array because Firestore doesn't
  /// support updating individual array-element fields.
  Future<void> respondToExtraCharge({
    required String jobId,
    required String chargeId,
    required bool   approved,
  }) async {
    final snap = await _firestore.collection('jobs').doc(jobId).get();
    final raw  = snap.data()?['extraCharges'] as List<dynamic>? ?? [];

    final updated = raw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      if (m['id'] == chargeId) {
        m['status'] = approved ? 'approved' : 'rejected';
      }
      return m;
    }).toList();

    await _firestore.collection('jobs').doc(jobId).update({
      'extraCharges': updated,
      'updatedAt':    FieldValue.serverTimestamp(),
    });
  }

  // ── Internal helpers ──────────────────────────────────────────────
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
        throw Exception('Server error ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['clientSecret'] as String;
    } catch (e) {
      throw Exception('Failed to connect to payment server: $e');
    }
  }

  Future<String> _savePaymentToFirestore({
    required double amount,
    required String jobId,
    required String jobTitle,
    required String clientId,
    required String workerId,
    required String method,
  }) async {
    final platformFee = calcPlatformFee(amount);

    final docRef = await _firestore.collection('payments').add({
      'jobId':       jobId,
      'jobTitle':    jobTitle,
      'clientId':    clientId,
      'workerId':    workerId,
      'amount':      amount,
      'platformFee': platformFee,
      'workerNet':   amount - platformFee,
      'method':      method,
      'status':      'completed',
      'createdAt':   FieldValue.serverTimestamp(),
      'completedAt': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('jobs').doc(jobId).update({
      'paymentStatus': 'paid',
      'paymentMethod': method,
      'paymentId':     docRef.id,
      'status':        'completed',
      'updatedAt':     FieldValue.serverTimestamp(),
    });

    debugPrint('PaymentService: saved payment ${docRef.id}');
    return docRef.id;
  }

  // ── Queries ───────────────────────────────────────────────────────
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

  Future<PaymentModel?> getPaymentByJobId(String jobId) async {
    try {
      final snap = await _firestore
          .collection('payments')
          .where('jobId', isEqualTo: jobId)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return PaymentModel.fromSnapshot(snap.docs.first);
    } catch (_) {
      return null;
    }
  }

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
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => PaymentModel.fromSnapshot(d)).toList());
  }
}