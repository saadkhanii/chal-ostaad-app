import 'dart:convert';
import 'dart:math';
import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:chal_ostaad/features/auth/screens/otp_verification.dart';
import 'package:chal_ostaad/shared/widgets/common_header.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:chal_ostaad/core/constants/colors.dart';
import 'package:chal_ostaad/core/constants/sizes.dart';
import 'package:chal_ostaad/shared/widgets/Cbutton.dart';
import 'package:chal_ostaad/shared/widgets/CtextField.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

// firebase_auth is no longer needed
// import 'package:firebase_auth/firebase_auth.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  // Switched from _phoneController to _emailController
  final TextEditingController _emailController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _userRole;
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('user_role') ?? 'client';
    });
    _logger.i('Forgot Password screen loaded for role: $_userRole');
  }

  // --- NEW: EmailJS Logic (copied from client_signup) ---
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
      _logger.i('Password reset OTP sent successfully to $userEmail.');
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
      backgroundColor: isDark ? CColors.dark : CColors.white,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: size.height,
          ),
          child: Column(
            children: [
              CommonHeader(title: 'Forgot'),
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
                  padding: const EdgeInsets.all(CSizes.xl),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Forgot Password?',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? CColors.white : CColors.textPrimary,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: CSizes.sm),
                        Text(
                          'Enter your registered email to reset your password.', // Updated text
                          style: textTheme.bodyMedium?.copyWith(
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                          ),
                        ),
                        const SizedBox(height: CSizes.xl),
                        CTextField(
                          label: 'Email Address', // Updated label
                          hintText: 'your.email@example.com', // Updated hint
                          controller: _emailController, // Updated controller
                          keyboardType: TextInputType.emailAddress, // Updated type
                          prefixIcon: Icon(
                            Icons.email_outlined, // Updated icon
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                            size: 20,
                          ),
                          isRequired: true,
                          validator: _validateEmail, // Updated validator
                        ),
                        const SizedBox(height: CSizes.md),
                        Text(
                          'A 6-digit verification code will be sent to this email.', // Updated text
                          style: textTheme.bodySmall?.copyWith(
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: CSizes.xl),
                        _buildSendCodeButton(),
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

  Widget _buildSendCodeButton() {
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
      text: 'Send Code',
      onPressed: _handleSendCode,
      width: double.infinity,
      backgroundColor: CColors.secondary,
      foregroundColor: CColors.white,
    );
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

  // --- UPDATED: Main handler logic ---
  Future<void> _handleSendCode() async {
    if (!_formKey.currentState!.validate()) return;
    if (_userRole == null) {
      _showErrorMessage('User role not identified. Please restart the app.');
      return;
    }

    setState(() => _isLoading = true);

    final email = _emailController.text.trim().toLowerCase();
    final collectionName = _userRole == 'client' ? 'clients' : 'workers';

    try {
      _logger.i('Checking for email $email in collection: $collectionName');

      // 1. Find the user by email
      final querySnapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .where('personalInfo.email', isEqualTo: email)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      if (querySnapshot.docs.isEmpty) {
        throw Exception('This email is not registered for a $_userRole account.');
      }

      final userDoc = querySnapshot.docs.first;
      final userName = userDoc.data()['personalInfo']['fullName'] ?? 'User';

      // 2. Generate OTP and save it to the user's document
      final otp = _generateOtp();
      final otpExpiry = DateTime.now().add(const Duration(minutes: 10));

      await userDoc.reference.update({
        'verification': {
          'otp': otp,
          'otpExpiry': Timestamp.fromDate(otpExpiry),
        }
      });
      _logger.i('OTP generated and saved for $email.');

      // 3. Send the OTP via Email
      await _sendEmailOtp(otp: otp, userName: userName, userEmail: email);

      // 4. Navigate to OTP screen
      if (mounted) {
        _showSuccessMessage('Verification code sent to your email.');
        // We use Navigator.push and pass arguments directly
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OTPVerificationScreen(email: email),
          ),
        );
      }
    } on Exception catch (e) {
      final errorMessage = e.toString().startsWith('Exception: ') ? e.toString().substring(11) : e.toString();
      _logger.e('Forgot Password error: $errorMessage');
      _showErrorMessage(errorMessage);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: CColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
      ),
    );
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

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}
