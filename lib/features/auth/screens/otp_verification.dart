// D:/FlutterProjects/chal_ostaad/lib/features/auth/screens/otp_verification.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:chal_ostaad/core/constants/colors.dart';
import 'package:chal_ostaad/core/constants/sizes.dart';
import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/widgets/common_header.dart';

// firebase_auth is no longer needed here
// import 'package:firebase_auth/firebase_auth.dart';

class OTPVerificationScreen extends StatefulWidget {
  // 1. Now we only need the email to identify the user
  final String email;

  const OTPVerificationScreen({
    super.key,
    required this.email,
  });

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final List<TextEditingController> _otpControllers =
  List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());
  bool _isLoading = false;
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    _logger.i('OTP screen initialized for email: ${widget.email}');
    // Setup focus node listeners
    for (int i = 0; i < _otpControllers.length - 1; i++) {
      _otpControllers[i].addListener(() {
        if (_otpControllers[i].text.length == 1) {
          _focusNodes[i + 1].requestFocus();
        }
      });
    }
  }

  // --- The `build` method and most of its children are updated slightly ---

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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Email Verification', // Title changed
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? CColors.white : CColors.textPrimary,
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: CSizes.sm),
                      Text(
                        // Text changed to reflect email
                        'Enter the 6-digit code sent to your email at ${widget.email}',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: isDark ? CColors.lightGrey : CColors.darkGrey,
                        ),
                      ),
                      const SizedBox(height: CSizes.xl),
                      _buildOTPInputFields(isDark, textTheme),
                      const SizedBox(height: CSizes.md),
                      Center(
                        child: TextButton(
                          onPressed: _handleChangeEmail,
                          child: Text(
                            'Change Email', // Text changed
                            style: textTheme.bodyMedium?.copyWith(
                              color: CColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: CSizes.xl),
                      _buildResendRow(textTheme, isDark),
                      const SizedBox(height: CSizes.xl),
                      _buildVerifyButton(isDark),
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

  // --- NEW: Handle verification against Firestore ---
  Future<void> _handleVerify() async {
    if (!_isOTPComplete()) return;
    setState(() => _isLoading = true);

    final otp = _getOTP();
    _logger.i('Verifying email OTP: $otp for email: ${widget.email}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final userRole = prefs.getString('user_role') ?? 'client';
      final collectionName = userRole == 'client' ? 'clients' : 'workers';

      // 1. Find the user document by email
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

      // 2. Check if OTP has expired
      if (DateTime.now().isAfter(storedExpiry.toDate())) {
        throw Exception('The verification code has expired. Please request a new one.');
      }

      // 3. Check if OTP matches
      if (otp != storedOtp) {
        throw Exception('Invalid OTP. Please check the code and try again.');
      }

      // 4. Success! Update the user's account status
      await userDoc.reference.update({
        'accountStatus': 'active',
        'verification': FieldValue.delete(), // Clean up the verification field
      });

      _logger.i('Email verification successful! User is now active.');
      _showSuccessMessage('Verification Successful!');

      // 5. Navigate to the correct dashboard
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          userRole == 'client' ? AppRoutes.clientDashboard : AppRoutes.workerDashboard,
              (route) => false,
        );
      }
    } on Exception catch (e) {
      final errorMessage = e.toString().startsWith('Exception: ')
          ? e.toString().substring(11)
          : e.toString();
      _logger.e('OTP Verification Failed: $errorMessage');
      _showErrorMessage(errorMessage);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleChangeEmail() {
    Navigator.pop(context); // Go back to the previous screen
  }

  void _handleResendCode() {
    // TODO: Implement resend email logic.
    // This would involve calling a function on the previous screen
    // or re-running the `_handleClientSignUp` logic to generate and send a new OTP.
    _logger.i('Resending OTP to: ${widget.email}');
    _showSuccessMessage('A new verification code has been sent to your email.');
  }

  // --- All other private helper methods and widgets (_build..., _getOTP, _show..., dispose) can remain largely the same. ---

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
              filled: true,
              fillColor:
              isDark ? CColors.darkContainer : CColors.lightContainer,
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
          foregroundColor: isEnabled ? CColors.white : CColors.darkGrey,
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
          'Verify',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: isEnabled ? CColors.white : CColors.darkGrey,
          ),
        ),
      ),
    );
  }

  Widget _buildResendRow(TextTheme textTheme, bool isDark) {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Didn't receive code? ",
            style: textTheme.bodyMedium?.copyWith(
              color: isDark ? CColors.lightGrey : CColors.darkGrey,
            ),
          ),
          TextButton(
            onPressed: _handleResendCode,
            child: Text(
              'Resend',
              style: textTheme.bodyMedium?.copyWith(
                color: CColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
    ));
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: CColors.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  void dispose() {
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }
}
