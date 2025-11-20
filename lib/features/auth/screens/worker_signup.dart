import 'dart:convert';
import 'dart:math';
import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../shared/widgets/Cbutton.dart';
import '../../../shared/widgets/CtextField.dart';
import '../../../shared/widgets/common_header.dart';

// firebase_auth is no longer needed
// import 'package:firebase_auth/firebase_auth.dart';

class WorkerSignUpScreen extends StatefulWidget {
  const WorkerSignUpScreen({super.key});

  @override
  State<WorkerSignUpScreen> createState() => _WorkerSignUpScreenState();
}

class _WorkerSignUpScreenState extends State<WorkerSignUpScreen> {
  final TextEditingController _cnicController = TextEditingController();
  // Changed from _phoneController to _emailController
  final TextEditingController _emailController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  final Logger _logger = Logger();

  static final RegExp _cnicRegex = RegExp(r'^\d{5}-\d{7}-\d{1}$');

  // --- NEW: EmailJS Logic ---
  String _generateOtp() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  Future<void> _sendEmailOtp({
    required String otp,
    required String userName,
    required String userEmail,
  }) async {
    const serviceId = 'service_q3lyy6u';
    const templateId = 'template_tz363fr';
    const userId = 'EJmKoj4BDtja4_EPh';

    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
    final response = await http.post(
      url,
      headers: {
        'origin': 'http://localhost',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'service_id': serviceId,
        'template_id': templateId,
        'user_id': userId,
        'template_params': {
          'otp_code': otp,
          'user_name': userName,
          'to_email': userEmail,
        },
      }),
    );

    if (response.statusCode == 200) {
      _logger.i('Worker verification OTP sent successfully to $userEmail.');
    } else {
      _logger.e('Failed to send email. Status: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to send verification email.');
    }
  }


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: isDark ? CColors.darkGrey : CColors.white,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: size.height - MediaQuery.of(context).padding.top,
          ),
          child: Column(
            children: [
              CommonHeader(title: 'SignUp'),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? CColors.darkContainer : CColors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(CSizes.cardRadiusLg),
                    topRight: Radius.circular(CSizes.cardRadiusLg),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(CSizes.lg),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: CSizes.lg),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Verify Worker Account',
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? CColors.white
                                    : CColors.textPrimary,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: CSizes.xs),
                            Text(
                              'Enter your registered details to proceed',
                              style: textTheme.bodyMedium?.copyWith(
                                color: isDark
                                    ? CColors.lightGrey
                                    : CColors.darkGrey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: CSizes.xl),
                        CTextField(
                          label: 'CNIC Number',
                          hintText: 'XXXXX-XXXXXXX-X',
                          controller: _cnicController,
                          keyboardType: TextInputType.text,
                          prefixIcon: Icon(
                            Icons.badge_outlined,
                            color: isDark
                                ? CColors.lightGrey
                                : CColors.darkGrey,
                            size: 20,
                          ),
                          isRequired: true,
                          validator: _validateCnic,
                          onChanged: _formatCnicInput,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(15),
                            FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
                          ],
                        ),
                        const SizedBox(height: CSizes.lg),
                        CTextField(
                          label: 'Email Address', // Updated label
                          hintText: 'your.email@example.com', // Updated hint
                          controller: _emailController, // Updated controller
                          keyboardType: TextInputType.emailAddress, // Updated type
                          prefixIcon: Icon(
                            Icons.email_outlined, // Updated icon
                            color: isDark
                                ? CColors.lightGrey
                                : CColors.darkGrey,
                            size: 20,
                          ),
                          isRequired: true,
                          validator: _validateEmail, // Updated validator
                        ),
                        const SizedBox(height: CSizes.xl),
                        _buildSignUpButton(isDark),
                        const SizedBox(height: CSizes.lg),
                        _buildHelpText(context, textTheme),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignUpButton(bool isDark) {
    return _isLoading
        ? SizedBox(
      width: double.infinity,
      height: CSizes.buttonHeight,
      child: ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: CColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CSizes.buttonRadius),
          ),
        ),
        child: const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          strokeWidth: 2,
        ),
      ),
    )
        : CButton(
      text: 'VERIFY & PROCEED',
      onPressed: _handleWorkerSignUp,
      width: double.infinity,
      backgroundColor: CColors.primary,
      foregroundColor: CColors.white,
    );
  }

  Widget _buildHelpText(BuildContext context, TextTheme textTheme) {
    return Center(
      child: TextButton(
        onPressed: _handleBackToLogin,
        child: Text(
          'Want to sign in instead?',
          style: textTheme.bodyMedium?.copyWith(
            color: CColors.primary,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  String? _validateCnic(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your CNIC number';
    }
    if (!_cnicRegex.hasMatch(value)) {
      return 'Please enter valid CNIC format (XXXXX-XXXXXXX-X)';
    }
    return null;
  }

  // New validator for email
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email address';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }


  void _formatCnicInput(String value) {
    final cleanValue = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanValue.length <= 5) {
      _cnicController.text = cleanValue;
    } else if (cleanValue.length <= 12) {
      _cnicController.text =
      '${cleanValue.substring(0, 5)}-${cleanValue.substring(5)}';
    } else {
      _cnicController.text =
      '${cleanValue.substring(0, 5)}-${cleanValue.substring(5, 12)}-${cleanValue.substring(12, 13)}';
    }
    _cnicController.selection = TextSelection.collapsed(
      offset: _cnicController.text.length,
    );
  }

  // --- UPDATED: Main handler logic ---
  Future<void> _handleWorkerSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final cnic = _cnicController.text.trim();
    final email = _emailController.text.trim().toLowerCase();

    try {
      _logger.i('Worker verification attempt: CNIC=$cnic, Email=$email');

      // 1. Find the worker by CNIC
      final querySnapshot = await FirebaseFirestore.instance
          .collection('workers')
          .where('personalInfo.cnic', isEqualTo: cnic)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      if (querySnapshot.docs.isEmpty) {
        throw Exception('No worker found with this CNIC. Please contact support to register.');
      }

      final workerDoc = querySnapshot.docs.first;
      final workerData = workerDoc.data();
      final String existingEmail = workerData['personalInfo']['email'];

      // 2. Check if the provided email matches the one in the record
      if (email != existingEmail) {
        throw Exception('The email address does not match the registered CNIC.');
      }

      _logger.i('Worker found. Sending OTP to $email');
      final userName = workerData['personalInfo']['fullName'] ?? 'Worker';

      // 3. Generate and save OTP
      final otp = _generateOtp();
      final otpExpiry = DateTime.now().add(const Duration(minutes: 10));

      await workerDoc.reference.update({
        'verification': {
          'otp': otp,
          'otpExpiry': Timestamp.fromDate(otpExpiry),
        }
      });

      // 4. Send email
      await _sendEmailOtp(otp: otp, userName: userName, userEmail: email);

      // 5. Navigate to OTP screen
      if (mounted) {
        _showSuccessMessage('Welcome back! Please verify with the code sent to your email.');
        Navigator.pushNamed(
          context,
          AppRoutes.otpVerification,
          arguments: {'email': email},
        );
      }
    } on Exception catch (e) {
      _logger.e('Worker verification error: $e');
      final errorMessage = e.toString().startsWith('Exception: ') ? e.toString().substring(11) : e.toString();
      _showErrorMessage(errorMessage);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleBackToLogin() {
    Navigator.pop(context);
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: CColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _cnicController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}
