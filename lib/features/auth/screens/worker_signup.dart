// lib/features/auth/screens/worker_signup.dart

import 'dart:convert';
import 'dart:math';
import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/widgets/Cbutton.dart';
import '../../../shared/widgets/CtextField.dart';
import '../../../shared/widgets/common_header.dart';

class WorkerSignUpScreen extends StatefulWidget {
  const WorkerSignUpScreen({super.key});

  @override
  State<WorkerSignUpScreen> createState() => _WorkerSignUpScreenState();
}

class _WorkerSignUpScreenState extends State<WorkerSignUpScreen> {
  final TextEditingController _cnicController = TextEditingController();
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

  Future<void> _handleWorkerSignUp(WidgetRef ref) async {
    if (!_formKey.currentState!.validate()) return;

    ref.read(authProvider.notifier).state = const AuthState(isLoading: true);

    final cnic = _cnicController.text.trim();
    final email = _emailController.text.trim().toLowerCase();

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('workers')
          .where('personalInfo.cnic', isEqualTo: cnic)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      if (querySnapshot.docs.isEmpty) {
        throw Exception('errors.worker_not_found'.tr());
      }

      final workerDoc = querySnapshot.docs.first;
      final workerData = workerDoc.data();
      final String existingEmail = workerData['personalInfo']['email'];

      if (email != existingEmail) {
        throw Exception('errors.email_mismatch'.tr());
      }

      final userName = workerData['personalInfo']['fullName'] ?? 'Worker';
      final otp = _generateOtp();
      final otpExpiry = DateTime.now().add(const Duration(minutes: 10));

      await workerDoc.reference.update({
        'verification': {
          'otp': otp,
          'otpExpiry': Timestamp.fromDate(otpExpiry),
        }
      });

      await _sendEmailOtp(otp: otp, userName: userName, userEmail: email);

      if (mounted) {
        _showSuccessMessage('auth.welcome_back_verify'.tr());
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: CSizes.lg),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'auth.create_worker_account'.tr(),
                                style: textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? CColors.white : CColors.textPrimary,
                                  fontSize: isUrdu ? 24 : 20,
                                ),
                              ),
                              const SizedBox(height: CSizes.xs),
                              Text(
                                'auth.enter_registered_details'.tr(),
                                style: textTheme.bodyMedium?.copyWith(
                                  color: isDark ? CColors.lightGrey : CColors.darkGrey,
                                  fontSize: isUrdu ? 16 : 12,
                                  height: isUrdu ? 1.5 : 1.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: CSizes.xl),
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
                          const SizedBox(height: CSizes.xl),
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
      text: 'auth.verify_and_proceed'.tr(),
      onPressed: () => _handleWorkerSignUp(ref),
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
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
      ),
    );
  }
}