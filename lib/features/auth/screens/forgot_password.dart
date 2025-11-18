import 'package:flutter/material.dart';
import 'package:chal_ostaad/core/constants/colors.dart';
import 'package:chal_ostaad/core/constants/sizes.dart';
import 'package:chal_ostaad/shared/logo/logo.dart';
import 'package:chal_ostaad/shared/widgets/Cbutton.dart';
import 'package:chal_ostaad/shared/widgets/Ccontainer.dart';
import 'package:chal_ostaad/shared/widgets/CtextField.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

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
              CustomShapeContainer(
                height: size.height * 0.25,
                color: CColors.primary,
                padding: const EdgeInsets.only(top: 60),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppLogo(
                      fontSize: 28,
                      minWidth: 180,
                      maxWidth: 250,
                    ),
                    const SizedBox(height: CSizes.sm),
                    Text(
                      'Reset Your Password',
                      style: textTheme.titleMedium?.copyWith(
                        color: CColors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Text(
                          'Forgot Password?',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? CColors.white : CColors.textPrimary,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: CSizes.sm),

                        // Description
                        Text(
                          'Please enter your mobile number to reset the password',
                          style: textTheme.bodyMedium?.copyWith(
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                          ),
                        ),
                        const SizedBox(height: CSizes.xl),

                        // Phone Number Field
                        CTextField(
                          label: 'Mobile number',
                          hintText: 'Enter your mobile number',
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          prefixIcon: Container(
                            padding: const EdgeInsets.symmetric(horizontal: CSizes.sm),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '+92',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: isDark ? CColors.white : CColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: isDark ? CColors.lightGrey : CColors.darkGrey,
                                ),
                              ],
                            ),
                          ),
                          isRequired: true,
                          validator: _validatePhone,
                        ),

                        const SizedBox(height: CSizes.md),

                        // Info Text
                        Text(
                          'You will receive a 6-digit verification code that may apply message and data rates.',
                          style: textTheme.bodySmall?.copyWith(
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),

                        const SizedBox(height: CSizes.xl),

                        // Send Code Button
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
      backgroundColor: CColors.primary,
      foregroundColor: CColors.white,
    );
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your mobile number';
    }
    final cleanPhone = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanPhone.length < 10) {
      return 'Please enter a valid mobile number';
    }
    return null;
  }

  void _handleSendCode() {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Simulate sending code
    Future.delayed(const Duration(seconds: 2), () {
      setState(() => _isLoading = false);
      Navigator.pushNamed(context, '/otp-verification');
    });
  }
}