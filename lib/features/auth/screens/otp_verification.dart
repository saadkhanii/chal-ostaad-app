// lib/features/auth/screens/otp_verification.dart

import 'package:chal_ostaad/features/auth/screens/set_password.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../shared/widgets/common_header.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String email;

  const OTPVerificationScreen({
    super.key,
    required this.email,
  });

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    _logger.i('OTP screen initialized for email: ${widget.email}');
    for (int i = 0; i < _otpControllers.length - 1; i++) {
      _otpControllers[i].addListener(() {
        if (_otpControllers[i].text.length == 1) {
          _focusNodes[i + 1].requestFocus();
        }
      });
    }
  }

  Future<void> _handleVerify() async {
    if (!_isOTPComplete()) return;
    setState(() => _isLoading = true);

    final otp = _getOTP();
    _logger.i('Verifying email OTP: $otp for email: ${widget.email}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final userRole = prefs.getString('user_role') ?? 'client';
      final collectionName = userRole == 'client' ? 'clients' : 'workers';

      final querySnapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .where('personalInfo.email', isEqualTo: widget.email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception('No user found with this email. Please sign up again.');
      }

      final userDoc = querySnapshot.docs.first;
      final userData = userDoc.data();
      final String storedOtp = userData['verification']['otp'];
      final Timestamp storedExpiry = userData['verification']['otpExpiry'];

      if (DateTime.now().isAfter(storedExpiry.toDate())) {
        throw Exception('The verification code has expired. Please request a new one.');
      }

      if (otp != storedOtp) {
        throw Exception('Invalid OTP. Please check the code and try again.');
      }

      _logger.i('Email verification successful! Proceeding to set password.');
      _showSuccessMessage('Verification Successful!');

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SetPasswordScreen(email: widget.email),
          ),
        );
      }
    } on Exception catch (e) {
      final errorMessage = e.toString().startsWith('Exception: ') ? e.toString().substring(11) : e.toString();
      _logger.e('OTP Verification Failed: $errorMessage');
      _showErrorMessage(errorMessage);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // This build method is correct and does not need to change.
    // ... all your existing UI code ...
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
              CommonHeader(title: 'OTP'),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Email Verification',
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? CColors.white : CColors.textPrimary,
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: CSizes.sm),
                      Text(
                        'Enter the 6-digit code sent to your email at ${widget.email}',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: isDark ? CColors.lightGrey : CColors.darkGrey,
                        ),
                      ),
                      const SizedBox(height: CSizes.xl),
                      _buildOTPInputFields(isDark, textTheme),
                      const SizedBox(height: CSizes.xl),
                      _buildVerifyButton(isDark),
                      const SizedBox(height: CSizes.md),
                      _buildResendRow(textTheme, isDark),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOTPInputFields(bool isDark, TextTheme textTheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (index) {
        return SizedBox(
          width: 50,
          height: 50,
          child: TextFormField(
            controller: _otpControllers[index],
            focusNode: _focusNodes[index],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            style: textTheme.headlineSmall?.copyWith(
              color: isDark ? CColors.white : CColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                borderSide: BorderSide(color: CColors.borderPrimary),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                borderSide: BorderSide(color: CColors.borderPrimary),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                borderSide: BorderSide(color: CColors.primary, width: 2.0),
              ),
            ),
            onChanged: (value) {
              if (value.length == 1 && index < 5) {
                _focusNodes[index + 1].requestFocus();
              } else if (value.isEmpty && index > 0) {
                _focusNodes[index - 1].requestFocus();
              }
              if (_isOTPComplete() && index == 5) {
                _handleVerify();
              }
              setState(() {});
            },
          ),
        );
      }),
    );
  }

  Widget _buildVerifyButton(bool isDark) {
    final isEnabled = _isOTPComplete() && !_isLoading;
    return SizedBox(
      width: double.infinity,
      height: CSizes.buttonHeight,
      child: ElevatedButton(
        onPressed: isEnabled ? _handleVerify : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnabled ? CColors.primary : CColors.buttonDisabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CSizes.buttonRadius),
          ),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          strokeWidth: 2,
        )
            : Text(
          'Verify & Proceed',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: isEnabled ? Colors.white : CColors.darkGrey,
          ),
        ),
      ),
    );
  }

  Widget _buildResendRow(TextTheme textTheme, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Didn't receive code? ",
          style: textTheme.bodyMedium?.copyWith(
            color: isDark ? CColors.lightGrey : CColors.darkGrey,
          ),
        ),
        TextButton(
          onPressed: () { /* TODO: Resend logic */},
          child: Text(
            'Resend',
            style: textTheme.bodyMedium?.copyWith(
              color: CColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  bool _isOTPComplete() {
    return _otpControllers.every((controller) => controller.text.length == 1);
  }

  String _getOTP() {
    return _otpControllers.map((controller) => controller.text).join();
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: CColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
      ),
    ));
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: CColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
      ),
    ));
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }
}
