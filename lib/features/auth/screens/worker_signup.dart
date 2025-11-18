import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
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
  final TextEditingController _phoneController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  final Logger _logger = Logger();

  // CNIC validation regex (Pakistani format: XXXXX-XXXXXXX-X)
  static final RegExp _cnicRegex = RegExp(r'^\d{5}-\d{7}-\d{1}$');

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
              // Header Section with Custom Shape
              CommonHeader(title: 'SignUp'),

              // Sign Up Form Section
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

                        // Welcome Section
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Verify Your Account',
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
                              'Enter your details to proceed',
                              style: textTheme.bodyMedium?.copyWith(
                                color: isDark
                                    ? CColors.lightGrey
                                    : CColors.darkGrey,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: CSizes.xl),

                        // CNIC Field
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

                        // Phone Field
                        CTextField(
                          label: 'Phone Number',
                          hintText: '03XX-XXXXXXX',
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          prefixIcon: Icon(
                            Icons.phone_iphone_outlined,
                            color: isDark
                                ? CColors.lightGrey
                                : CColors.darkGrey,
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

                        const SizedBox(height: CSizes.xl),

                        // Sign Up Button
                        _buildSignUpButton(isDark),

                        const SizedBox(height: CSizes.lg),

                        // Help Text
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

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }

    final cleanPhone = value.replaceAll(RegExp(r'[^\d]'), '');

    if (cleanPhone.length < 10) {
      return 'Phone number must be at least 10 digits';
    }

    if (!cleanPhone.startsWith('03') && !cleanPhone.startsWith('+92')) {
      return 'Please enter a valid Pakistani phone number';
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
          '${cleanValue.substring(0, 4)}-${cleanValue.substring(4)}';
    }

    _phoneController.selection = TextSelection.collapsed(
      offset: _phoneController.text.length,
    );
  }

  Future<void> _handleWorkerSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final cnic = _cnicController.text.trim();
      final phone = _phoneController.text.trim();

      _logger.i('Worker verification attempt: CNIC=$cnic, Phone=$phone');

      // Check if a worker exists with the provided CNIC
      final querySnapshot = await FirebaseFirestore.instance
          .collection('workers')
          .where('personalInfo.cnic', isEqualTo: cnic)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      if (querySnapshot.docs.isEmpty) {
        // If no document is found, the worker is not registered.
        throw Exception(
          'No worker found with this CNIC. Please contact support to register.',
        );
      }

      // Worker with CNIC exists, now check if the phone number matches.
      final workerData = querySnapshot.docs.first.data();
      final String existingPhone = workerData['personalInfo']['phone'];

      if (phone == existingPhone) {
        // CNIC and Phone number match, proceed to OTP verification.
        _logger.i('Worker found and verified. Navigating to OTP screen.');
        _showSuccessMessage('Welcome back! Please verify your number.');

        if (mounted) {
          Navigator.pushNamed(
            context,
            AppRoutes.otpVerification,
            arguments: phone,
          );
        }
      } else {
        // CNIC exists but phone number does not match.
        throw Exception('The phone number does not match the registered CNIC.');
      }
    } on FirebaseException catch (e) {
      _logger.e(
        'Firebase error during worker verification: ${e.code} - ${e.message}',
      );
      _showErrorMessage(
        'A network error occurred. Please check your connection and try again.',
      );
    } on Exception catch (e) {
      _logger.e('Worker verification error: $e');
      // Remove 'Exception: ' prefix for a cleaner message
      final errorMessage = e.toString().startsWith('Exception: ')
          ? e.toString().substring(11)
          : e.toString();
      _showErrorMessage(errorMessage);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleBackToLogin() {
    // Navigate back to the previous screen, likely the role or login page
    Navigator.pop(context);
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        ),
        duration: const Duration(seconds: 3),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _cnicController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
