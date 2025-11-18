import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../shared/logo/logo.dart';
import '../../../shared/widgets/Cbutton.dart';
import '../../../shared/widgets/Ccontainer.dart';
import '../../../shared/widgets/CtextField.dart';

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
              CustomShapeContainer(
                height: size.height * 0.25, // Reduced height
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 1),
                    AppLogo(
                      fontSize: 24, // Smaller font
                      minWidth: 250,
                      maxWidth: 350,
                    ),
                    const SizedBox(height: CSizes.sm),
                    Text(
                      'Worker Portal',
                      style: textTheme.titleMedium?.copyWith(
                        color: CColors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      height: 3,
                      width: 50,
                      decoration: BoxDecoration(
                        color: CColors.white.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: CSizes.md),
                  ],
                ),
              ),

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
                              'Create Account!',
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isDark ? CColors.white : CColors.textPrimary,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: CSizes.xs),
                            Text(
                              'Register to create your worker account',
                              style: textTheme.bodyMedium?.copyWith(
                                color: isDark ? CColors.lightGrey : CColors.darkGrey,
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

                        // Phone Field
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
      text: 'SIGN UP AS WORKER',
      onPressed: _handleWorkerSignUp,
      width: double.infinity,
      backgroundColor: CColors.primary,
      foregroundColor: CColors.white,
    );
  }

  Widget _buildHelpText(BuildContext context, TextTheme textTheme) {
    return Center(
      child: TextButton(
        onPressed: _handleForgotCredentials,
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

      _logger.i('Worker sign up attempt: CNIC=$cnic, Phone=$phone');

      // Check if worker already exists
      final querySnapshot = await FirebaseFirestore.instance
          .collection('workers')
          .where('personalInfo.cnic', isEqualTo: cnic)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      if (querySnapshot.docs.isNotEmpty) {
        throw Exception('Worker with this CNIC already exists');
      }

      // Create new worker document
      final newWorkerRef = FirebaseFirestore.instance.collection('workers').doc();

      await newWorkerRef.set({
        'personalInfo': {
          'cnic': cnic,
          'phone': phone,
          'createdAt': FieldValue.serverTimestamp(),
        },
        'verification': {
          'status': 'pending',
          'requestedAt': FieldValue.serverTimestamp(),
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Success - Show message
      _showSuccessMessage('Registration successful! Your account is pending verification.');
      _logger.i('Worker sign up successful: ${newWorkerRef.id}');

      // TODO: Navigate to pending verification screen or back to login
      // Navigator.pushReplacement(
      //   context,
      //   MaterialPageRoute(builder: (context) => PendingVerificationScreen()),
      // );

    } on FirebaseException catch (e) {
      _logger.e('Firebase error: ${e.code} - ${e.message}');
      _showErrorMessage('Network error. Please try again.');
    } on Exception catch (e) {
      _logger.e('Sign up error: $e');
      _showErrorMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleForgotCredentials() {
    // Navigate back to login screen
    Navigator.pop(context);
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
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