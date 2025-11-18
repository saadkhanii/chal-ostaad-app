import 'package:flutter/material.dart';
import 'package:chal_ostaad/core/constants/colors.dart';
import 'package:chal_ostaad/core/constants/sizes.dart';
import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:logger/logger.dart';

import '../../../shared/widgets/common_header.dart';

class OTPVerificationScreen extends StatefulWidget {
  // 1. Add a final variable to hold the phone number
  final String phoneNumber;

  // 2. Update the constructor to require the phone number
  const OTPVerificationScreen({
    super.key,
    required this.phoneNumber,
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
    _logger.i('OTP screen initialized for phone number: ${widget.phoneNumber}');
    // Setup focus node listeners
    for (int i = 0; i < _focusNodes.length; i++) {
      _focusNodes[i].addListener(() {
        if (!_focusNodes[i].hasFocus && _otpControllers[i].text.isEmpty) {
          // This logic helps move focus backward when a field is cleared.
          // The requestFocus call is commented out to prevent aggressive focus jumping,
          // but can be enabled if desired.
          // if (i > 0) {
          //   _focusNodes[i - 1].requestFocus();
          // }
        }
      });
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
              // Header with CustomShapeContainer
              CommonHeader(
                title: 'OTP',
              ),

              // Form Section
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
                      // Title
                      Text(
                        'OTP Verification',
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? CColors.white : CColors.textPrimary,
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: CSizes.sm),

                      // Description
                      Text(
                        // 3. Display the phone number dynamically
                        'Enter the 6-digit code sent to your mobile number at ${widget.phoneNumber}',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: isDark ? CColors.lightGrey : CColors.darkGrey,
                        ),
                      ),
                      const SizedBox(height: CSizes.xl),

                      // OTP Input Fields
                      _buildOTPInputFields(isDark, textTheme),

                      const SizedBox(height: CSizes.md),

                      // Change Number
                      Center(
                        child: TextButton(
                          onPressed: _handleChangeNumber,
                          child: Text(
                            'Change Number',
                            style: textTheme.bodyMedium?.copyWith(
                              color: CColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: CSizes.xl),

                      // Resend Code
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Didn't receive code? ",
                              style: textTheme.bodyMedium?.copyWith(
                                color:
                                isDark ? CColors.lightGrey : CColors.darkGrey,
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
                      ),

                      const SizedBox(height: CSizes.xl),

                      // Verify Button
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

              // Auto-submit when all fields are filled
              if (_isOTPComplete() && index == 5) {
                _handleVerify();
              }

              // Update UI when OTP changes to enable/disable button
              setState(() {});
            },
          ),
        );
      }),
    );
  }

  Widget _buildVerifyButton(bool isDark) {
    if (_isLoading) {
      return SizedBox(
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
      );
    } else {
      final isEnabled = _isOTPComplete();
      return SizedBox(
        width: double.infinity,
        height: CSizes.buttonHeight,
        child: ElevatedButton(
          onPressed: isEnabled ? _handleVerify : null,
          style: ElevatedButton.styleFrom(
            backgroundColor:
            isEnabled ? CColors.primary : CColors.buttonDisabled,
            foregroundColor: isEnabled ? CColors.white : CColors.darkGrey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CSizes.buttonRadius),
            ),
          ),
          child: Text(
            'Verify',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isEnabled ? CColors.white : CColors.darkGrey,
            ),
          ),
        ),
      );
    }
  }

  bool _isOTPComplete() {
    return _otpControllers.every((controller) => controller.text.isNotEmpty);
  }

  String _getOTP() {
    return _otpControllers.map((controller) => controller.text).join();
  }

  void _handleVerify() {
    if (!_isOTPComplete()) return;

    final otp = _getOTP();
    _logger.i('Verifying OTP: $otp for phone: ${widget.phoneNumber}');

    setState(() => _isLoading = true);

    // TODO: Implement actual OTP verification logic with Firebase Auth here

    // Simulate OTP verification
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isLoading = false);

        // On success, navigate to set new password screen
        // You can pass the phone number here too if needed
        Navigator.pushNamed(context, AppRoutes.setPassword);
      }
    });
  }

  void _handleChangeNumber() {
    Navigator.pop(context); // Go back to the previous screen
  }

  void _handleResendCode() {
    _logger.i('Resending OTP to: ${widget.phoneNumber}');
    // TODO: Implement actual OTP resend logic here

    // Show resend confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('A new verification code has been sent to ${widget.phoneNumber}'),
        backgroundColor: CColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        ),
      ),
    );
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
