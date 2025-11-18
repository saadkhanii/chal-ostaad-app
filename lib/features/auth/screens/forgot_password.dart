import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:chal_ostaad/features/auth/screens/otp_verification.dart';
import 'package:chal_ostaad/shared/widgets/common_header.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:chal_ostaad/core/constants/colors.dart';
import 'package:chal_ostaad/core/constants/sizes.dart';
import 'package:chal_ostaad/shared/widgets/Cbutton.dart';
import 'package:chal_ostaad/shared/widgets/CtextField.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _userRole;
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  // 1. Load the user's role to know which collection to check
  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Defaults to 'client' if no role is found, adjust if needed
      _userRole = prefs.getString('user_role') ?? 'client';
    });
    _logger.i('Forgot Password screen loaded for role: $_userRole');
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
                          'Enter your registered mobile number to reset your password.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                          ),
                        ),
                        const SizedBox(height: CSizes.xl),
                        CTextField(
                          label: 'Mobile number',
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
                        ),
                        const SizedBox(height: CSizes.md),
                        Text(
                          'A 6-digit verification code will be sent to this number.',
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

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your mobile number';
    }
    final cleanPhone = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanPhone.length < 10) {
      return 'Please enter a valid 10-digit mobile number';
    }
    return null;
  }

  // 2. Updated logic to verify number based on role
  Future<void> _handleSendCode() async {
    if (!_formKey.currentState!.validate()) return;
    if (_userRole == null) {
      _showErrorMessage('User role not identified. Please go back and select a role.');
      return;
    }

    setState(() => _isLoading = true);

    final phone = _phoneController.text.trim();
    final collectionName = _userRole == 'client' ? 'clients' : 'workers';

    try {
      _logger.i('Checking for phone number $phone in collection: $collectionName');

      final querySnapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .where('personalInfo.phone', isEqualTo: phone)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      if (querySnapshot.docs.isNotEmpty) {
        // Phone number found, navigate to OTP screen
        _logger.i('Phone number found for $_userRole. Navigating to OTP verification.');

        if (mounted) {
          // *** As discussed, we are now ready to pass the phone number ***
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OTPVerificationScreen(phoneNumber: phone),
            ),
          );
        }
      } else {
        // Phone number NOT found
        throw Exception('This phone number is not registered for a $_userRole account.');
      }
    } on FirebaseException catch (e) {
      _logger.e('Firebase error during phone verification: ${e.code}');
      _showErrorMessage('A network error occurred. Please try again.');
    } on Exception catch (e) {
      final errorMessage = e.toString().substring(11); // Remove "Exception: "
      _logger.e('Verification failed: $errorMessage');
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

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }
}
