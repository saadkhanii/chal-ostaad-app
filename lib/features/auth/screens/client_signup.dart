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

  // CNIC validation regex (Pakistani format: XXXXX-XXXXXXX-X)
  static final RegExp _cnicRegex = RegExp(r'^\d{5}-\d{7}-\d{1}$');
  static final RegExp _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

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
              // Header Section with CustomShapeContainer
              CustomShapeContainer(
                height: size.height * 0.25,
                color: CColors.primary,
                padding: const EdgeInsets.only(top: 60),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppLogo(
                      fontSize: 24,
                      minWidth: 250,
                      maxWidth: 350,
                    ),
                    const SizedBox(height: CSizes.sm),
                    Text(
                      'Client Portal',
                      style: textTheme.titleMedium?.copyWith(
                        color: CColors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
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

                        // Full Name Field
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

                        const SizedBox(height: CSizes.lg),

                        // Email Field
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
      text: 'SIGN UP AS CLIENT',
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

  String? _validateFullName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your full name';
    }
    if (value.length < 3) {
      return 'Name must be at least 3 characters long';
    }
    return null;
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

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email address';
    }
    if (!_emailRegex.hasMatch(value)) {
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

  Future<void> _handleClientSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final fullName = _fullNameController.text.trim();
      final cnic = _cnicController.text.trim();
      final phone = _phoneController.text.trim();
      final email = _emailController.text.trim().toLowerCase();

      _logger.i('Client sign up attempt: Name=$fullName, CNIC=$cnic, Phone=$phone, Email=$email');

      // Check if client already exists with same CNIC or Email
      final cnicQuery = await FirebaseFirestore.instance
          .collection('clients')
          .where('personalInfo.cnic', isEqualTo: cnic)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      if (cnicQuery.docs.isNotEmpty) {
        throw Exception('Client with this CNIC already exists');
      }

      final emailQuery = await FirebaseFirestore.instance
          .collection('clients')
          .where('personalInfo.email', isEqualTo: email)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      if (emailQuery.docs.isNotEmpty) {
        throw Exception('Client with this email already exists');
      }

      // Create new client document
      final newClientRef = FirebaseFirestore.instance.collection('clients').doc();

      await newClientRef.set({
        'personalInfo': {
          'fullName': fullName,
          'cnic': cnic,
          'phone': phone,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
        },
        'accountStatus': 'active', // Clients are active immediately (no verification needed)
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Success - Show message
      _showSuccessMessage('Client registration successful! You can now post jobs.');
      _logger.i('Client sign up successful: ${newClientRef.id}');

      // TODO: Navigate to client dashboard or appropriate screen
      // Navigator.pushReplacement(
      //   context,
      //   MaterialPageRoute(builder: (context) => ClientDashboard()),
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

  void _handleBackToLogin() {
    // Navigate back to role selection or login screen
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
    _fullNameController.dispose();
    _cnicController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}