// lib/features/auth/screens/client_signup.dart

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/routes/app_routes.dart';
import '../../../shared/widgets/Cbutton.dart';
import '../../../shared/widgets/CtextField.dart';
import '../../../shared/widgets/common_header.dart';

class ClientSignUpScreen extends StatefulWidget {
  const ClientSignUpScreen({super.key});

  @override
  State<ClientSignUpScreen> createState() => _ClientSignUpScreenState();
}

class _ClientSignUpScreenState extends State<ClientSignUpScreen> {
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _cnicController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  final Logger _logger = Logger();

  static final RegExp _cnicRegex = RegExp(r'^\d{5}-\d{7}-\d{1}$');
  static final RegExp _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

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
      _logger.i('Client verification OTP sent successfully to $userEmail.');
    } else {
      _logger.e('Failed to send email. Status: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to send verification email.');
    }
  }

  Future<void> _handleClientSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final email = _emailController.text.trim().toLowerCase();
    final cnic = _cnicController.text.trim();
    final phone = _phoneController.text.trim();
    final fullName = _fullNameController.text.trim();

    try {
      // 1. Check for email duplication across all roles (emails must be unique)
      final emailExistsInClients = await _checkIfValueExists('personalInfo.email', email, 'clients');
      if (emailExistsInClients) {
        throw Exception('This email is already registered as a client.');
      }
      final emailExistsInWorkers = await _checkIfValueExists('personalInfo.email', email, 'workers');
      if (emailExistsInWorkers) {
        throw Exception('This email is already in use by a worker account.');
      }

      // 2. Check for CNIC duplication only within the 'clients' collection
      final cnicExists = await _checkIfValueExists('personalInfo.cnic', cnic, 'clients');
      if (cnicExists) {
        throw Exception('This CNIC is already registered as a client.');
      }

      _logger.i('Client details are unique. Proceeding with OTP verification.');

      // 3. Generate OTP and create a temporary document in Firestore
      final otp = _generateOtp();
      final otpExpiry = DateTime.now().add(const Duration(minutes: 10));
      final tempDocRef = FirebaseFirestore.instance.collection('clients').doc();

      await tempDocRef.set({
        'personalInfo': {
          'fullName': fullName,
          'cnic': cnic,
          'phone': phone,
          'email': email,
        },
        'verification': {
          'otp': otp,
          'otpExpiry': Timestamp.fromDate(otpExpiry),
        },
        'account': {
          'accountStatus': 'pending_verification',
          'createdAt': FieldValue.serverTimestamp(),
        }
      });
      _logger.i('Temporary client document created. Sending OTP.');

      // 4. Send OTP via EmailJS
      await _sendEmailOtp(otp: otp, userName: fullName, userEmail: email);

      // 5. Navigate to OTP screen on success
      if (mounted) {
        _showSuccessMessage('Verification code sent to your email.');
        Navigator.pushNamed(
          context,
          AppRoutes.otpVerification,
          arguments: {'email': email},
        );
      }
    } on Exception catch (e) {
      final errorMessage = e.toString().startsWith('Exception: ') ? e.toString().substring(11) : e.toString();
      _logger.e('Client Sign-Up Error: $errorMessage');
      _showErrorMessage(errorMessage);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _checkIfValueExists(String field, String value, String collection) async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection(collection)
        .where(field, isEqualTo: value)
        .limit(1)
        .get();
    return querySnapshot.docs.isNotEmpty;
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: CSizes.lg,
                    vertical: CSizes.sm,
                  ),
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
                              'Create Client Account!',
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isDark ? CColors.white : CColors.textPrimary,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: CSizes.xs),
                            Text(
                              'Register to post jobs and hire workers',
                              style: textTheme.bodyMedium?.copyWith(
                                color: isDark ? CColors.lightGrey : CColors.darkGrey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: CSizes.xl),
                        CTextField(
                          label: 'Full Name',
                          hintText: 'Enter your full name',
                          controller: _fullNameController,
                          keyboardType: TextInputType.name,
                          prefixIcon: Icon(
                            Icons.person_outlined,
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                            size: 20,
                          ),
                          isRequired: true,
                          validator: _validateFullName,
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: CSizes.lg),
                        CTextField(
                          label: 'CNIC Number',
                          hintText: 'XXXXX-XXXXXXX-X',
                          controller: _cnicController,
                          keyboardType: TextInputType.text,
                          prefixIcon: Icon(
                            Icons.badge_outlined,
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
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
                          label: 'Phone Number',
                          hintText: '03XX-XXXXXXX',
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          prefixIcon: Icon(
                            Icons.phone_iphone_outlined,
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                            size: 20,
                          ),
                          isRequired: true,
                          validator: _validatePhone,
                          onChanged: _formatPhoneInput,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(12),
                            FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
                          ],
                        ),
                        const SizedBox(height: CSizes.lg),
                        CTextField(
                          label: 'Email Address',
                          hintText: 'your.email@example.com',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          prefixIcon: Icon(
                            Icons.email_outlined,
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                            size: 20,
                          ),
                          isRequired: true,
                          validator: _validateEmail,
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
      text: 'SIGN UP & VERIFY',
      onPressed: _handleClientSignUp,
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
          'Already have an account? Sign In',
          style: textTheme.bodyMedium?.copyWith(
            color: CColors.primary,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  void _handleBackToLogin() {
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
  }

  // --- Validators and Formatters ---
  String? _validateFullName(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your full name';
    if (value.length < 3) return 'Name must be at least 3 characters long';
    return null;
  }

  String? _validateCnic(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your CNIC number';
    if (!_cnicRegex.hasMatch(value)) return 'Please enter valid CNIC format (XXXXX-XXXXXXX-X)';
    return null;
  }

  // Corrected phone validation function
  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }
    // First, remove all non-digit characters (like the hyphen)
    final cleanPhone = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanPhone.length != 11) {
      return 'Phone number must be 11 digits';
    }
    if (!cleanPhone.startsWith('03')) {
      return 'Please enter a valid Pakistani mobile number (starts with 03)';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your email address';
    if (!_emailRegex.hasMatch(value)) return 'Please enter a valid email address';
    return null;
  }

  void _formatCnicInput(String value) {
    final cleanValue = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanValue.length <= 5) {
      _cnicController.text = cleanValue;
    } else if (cleanValue.length <= 12) {
      _cnicController.text = '${cleanValue.substring(0, 5)}-${cleanValue.substring(5)}';
    } else {
      _cnicController.text = '${cleanValue.substring(0, 5)}-${cleanValue.substring(5, 12)}-${cleanValue.substring(12, 13)}';
    }
    _cnicController.selection = TextSelection.collapsed(offset: _cnicController.text.length);
  }

  void _formatPhoneInput(String value) {
    final cleanValue = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanValue.length <= 4) {
      _phoneController.text = cleanValue;
    } else {
      _phoneController.text = '${cleanValue.substring(0, 4)}-${cleanValue.substring(4)}';
    }
    _phoneController.selection = TextSelection.collapsed(offset: _phoneController.text.length);
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: CColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
    ));
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: CColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
    ));
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _cnicController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}
