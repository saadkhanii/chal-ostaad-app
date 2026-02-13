// lib/features/auth/screens/client_signup.dart

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/providers/auth_provider.dart';
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

  static final RegExp _cnicRegex = RegExp(r'^\d{5}-\d{7}-\d{1}$');

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

    if (response.statusCode != 200) {
      throw Exception('Failed to send verification email.');
    }
  }

  Future<void> _handleClientSignUp(WidgetRef ref) async {
    if (!_formKey.currentState!.validate()) return;

    ref.read(authProvider.notifier).state = const AuthState(isLoading: true);

    final email = _emailController.text.trim().toLowerCase();
    final cnic = _cnicController.text.trim();
    final phone = _phoneController.text.trim();
    final fullName = _fullNameController.text.trim();

    try {
      final emailExistsInClients = await _checkIfValueExists('personalInfo.email', email, 'clients');
      if (emailExistsInClients) {
        throw Exception('auth.email_already_registered_client'.tr());
      }
      final emailExistsInWorkers = await _checkIfValueExists('personalInfo.email', email, 'workers');
      if (emailExistsInWorkers) {
        throw Exception('auth.email_already_registered_worker'.tr());
      }

      final cnicExists = await _checkIfValueExists('personalInfo.cnic', cnic, 'clients');
      if (cnicExists) {
        throw Exception('auth.cnic_already_registered'.tr());
      }

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

      await _sendEmailOtp(otp: otp, userName: fullName, userEmail: email);

      if (mounted) {
        _showSuccessMessage('auth.verification_code_sent'.tr());
        Navigator.pushNamed(
          context,
          AppRoutes.otpVerification,
          arguments: {'email': email},
        );
      }
    } on Exception catch (e) {
      final errorMessage = e.toString().startsWith('Exception: ') ? e.toString().substring(11) : e.toString();
      _showErrorMessage(errorMessage);
    } finally {
      if (mounted) {
        ref.read(authProvider.notifier).state = const AuthState(isLoading: false);
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
    return Consumer(
      builder: (context, ref, child) {
        final authState = ref.watch(authProvider);
        final size = MediaQuery.of(context).size;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textTheme = Theme.of(context).textTheme;
        final isUrdu = context.locale.languageCode == 'ur';

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
                  CommonHeader(
                    title: 'auth.sign_up'.tr(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(CSizes.xl, CSizes.sm, CSizes.xl, CSizes.xl),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, // REMOVED isUrdu condition
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start, // REMOVED isUrdu condition
                            children: [
                              Text(
                                'auth.create_client_account'.tr(),
                                style: textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? CColors.white : CColors.textPrimary,
                                  fontSize: isUrdu ? 24 : 20, // Larger for Urdu
                                ),
                              ),
                              const SizedBox(height: CSizes.xs),
                              Text(
                                'auth.register_to_post_jobs'.tr(),
                                style: textTheme.bodyMedium?.copyWith(
                                  color: isDark ? CColors.lightGrey : CColors.darkGrey,
                                  fontSize: isUrdu ? 16 : 12, // Larger for Urdu
                                  height: isUrdu ? 1.5 : 1.2, // Better line spacing for Urdu
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: CSizes.md),
                          CTextField(
                            label: 'auth.full_name'.tr(),
                            hintText: 'auth.full_name_hint'.tr(),
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
                          const SizedBox(height: CSizes.sm),
                          CTextField(
                            label: 'auth.cnic'.tr(),
                            hintText: 'auth.cnic_hint'.tr(),
                            controller: _cnicController,
                            keyboardType: TextInputType.number,
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
                          const SizedBox(height: CSizes.sm),
                          CTextField(
                            label: 'auth.phone'.tr(),
                            hintText: 'auth.phone_hint'.tr(),
                            controller: _phoneController,
                            keyboardType: TextInputType.number,
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
                          const SizedBox(height: CSizes.sm),
                          CTextField(
                            label: 'auth.email'.tr(),
                            hintText: 'auth.email_hint_signup'.tr(),
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
                          const SizedBox(height: CSizes.lg),
                          _buildSignUpButton(authState, ref),
                          const SizedBox(height: CSizes.lg),
                          _buildHelpText(context, textTheme, isDark),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSignUpButton(AuthState authState, WidgetRef ref) {
    return CButton(
      text: 'auth.sign_up'.tr(),
      onPressed: () => _handleClientSignUp(ref),
      width: double.infinity,
      isLoading: authState.isLoading,
    );
  }

  Widget _buildHelpText(BuildContext context, TextTheme textTheme, bool isDark) {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'auth.already_have_account'.tr(),
            style: textTheme.bodyMedium?.copyWith(
              color: isDark ? CColors.lightGrey : CColors.darkGrey,
              fontSize: 12,
            ),
          ),
          TextButton(
            onPressed: _handleBackToLogin,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(50, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'auth.login_exclamation'.tr(),
              style: textTheme.bodyMedium?.copyWith(
                color: CColors.primary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleBackToLogin() {
    Navigator.pop(context);
  }

  String? _validateFullName(String? value) {
    if (value == null || value.isEmpty) {
      return 'auth.full_name_required'.tr();
    }
    if (value.length < 3) {
      return 'auth.full_name_min_length'.tr();
    }
    return null;
  }

  String? _validateCnic(String? value) {
    if (value == null || value.isEmpty) {
      return 'auth.cnic_required'.tr();
    }
    if (!_cnicRegex.hasMatch(value)) {
      return 'auth.cnic_invalid'.tr();
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'auth.phone_required'.tr();
    }
    if (value.length != 12) {
      return 'auth.phone_invalid'.tr();
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'auth.email_required'.tr();
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'auth.email_invalid'.tr();
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

  void _formatPhoneInput(String value) {
    final cleanValue = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanValue.length <= 4) {
      _phoneController.text = cleanValue;
    } else {
      _phoneController.text =
      '${cleanValue.substring(0, 4)}-${cleanValue.substring(4, min(11, cleanValue.length))}';
    }
    _phoneController.selection = TextSelection.collapsed(
      offset: _phoneController.text.length,
    );
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
        backgroundColor: CColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd), // Fixed: borderRadius not border-radius
        ),
      ),
    );
  }
}