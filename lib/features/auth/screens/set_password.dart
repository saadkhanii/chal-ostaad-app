import 'package:flutter/material.dart';
import 'package:chal_ostaad/core/constants/colors.dart';
import 'package:chal_ostaad/core/constants/sizes.dart';
import 'package:chal_ostaad/shared/logo/logo.dart';
import 'package:chal_ostaad/shared/widgets/Cbutton.dart';
import 'package:chal_ostaad/shared/widgets/Ccontainer.dart';
import 'package:chal_ostaad/shared/widgets/CtextField.dart';

class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

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
                height: size.height * 0.2,
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
                          'Set a new password',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? CColors.white : CColors.textPrimary,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: CSizes.sm),

                        // Description
                        Text(
                          'Create a new password. Ensure it differs from previous ones for security',
                          style: textTheme.bodyMedium?.copyWith(
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                          ),
                        ),
                        const SizedBox(height: CSizes.xl),

                        // Password Field
                        CTextField(
                          label: 'Password',
                          hintText: 'Enter your new password',
                          controller: _passwordController,
                          keyboardType: TextInputType.visiblePassword,
                          obscureText: _obscurePassword,
                          prefixIcon: Icon(
                            Icons.lock_outlined,
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: isDark ? CColors.lightGrey : CColors.darkGrey,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          isRequired: true,
                          validator: _validatePassword,
                        ),

                        const SizedBox(height: CSizes.lg),

                        // Confirm Password Field
                        CTextField(
                          label: 'Confirm Password',
                          hintText: 'Re-enter your password',
                          controller: _confirmPasswordController,
                          keyboardType: TextInputType.visiblePassword,
                          obscureText: _obscureConfirmPassword,
                          prefixIcon: Icon(
                            Icons.lock_outlined,
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: isDark ? CColors.lightGrey : CColors.darkGrey,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword = !_obscureConfirmPassword;
                              });
                            },
                          ),
                          isRequired: true,
                          validator: _validateConfirmPassword,
                        ),

                        const SizedBox(height: CSizes.xl),

                        // Set Password Button
                        _buildSetPasswordButton(),
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

  Widget _buildSetPasswordButton() {
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
      text: 'Set Password',
      onPressed: _handleSetPassword,
      width: double.infinity,
      backgroundColor: CColors.primary,
      foregroundColor: CColors.white,
    );
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters long';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  void _handleSetPassword() {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Simulate password setting process
    Future.delayed(const Duration(seconds: 2), () {
      setState(() => _isLoading = false);

      // Show success message and navigate to login
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Password set successfully!'),
          backgroundColor: CColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
          ),
        ),
      );

      // Navigate to login screen
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    });
  }
}