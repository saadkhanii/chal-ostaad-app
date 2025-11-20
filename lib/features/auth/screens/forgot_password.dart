// lib/features/auth/screens/forgot_password.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../shared/widgets/Cbutton.dart';
import '../../../shared/widgets/CtextField.dart';
import '../../../shared/widgets/common_header.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _userRole;
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('user_role') ?? 'client';
    });
    _logger.i('Forgot Password screen loaded for role: $_userRole');
  }

  // --- SIMPLIFIED, STANDARD FIREBASE PASSWORD RESET ---
  Future<void> _handleSendResetLink() async {
    if (!_formKey.currentState!.validate()) return;
    if (_userRole == null) {
      _showErrorMessage('User role not identified. Please restart the app.');
      return;
    }

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();

    try {
      _logger.i('Sending password reset link for role: $_userRole to email: $email');

      // Get the correct auth instance based on the role
      final secondaryApp = Firebase.app(_userRole!);
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      // Use the built-in Firebase method to send a reset link
      await secondaryAuth.sendPasswordResetEmail(email: email);

      _logger.i('Password reset email sent successfully.');

      if (mounted) {
        _showSuccessMessage('A password reset link has been sent to your email. Please check your inbox.');
        // Navigate back to the login screen after sending the link
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _showErrorMessage('This email is not registered as a $_userRole.');
      } else {
        _showErrorMessage('An error occurred. Please try again.');
      }
      _logger.e('Forgot Password error: ${e.code}');
    } on Exception catch(e) {
      _logger.e("Forgot Password generic error: $e");
      _showErrorMessage('An unexpected error occurred. Please check your connection.');
    }
    finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.white,
      body: SingleChildScrollView(
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
                        "Don't worry, it happens! Enter your registered email to receive a password reset link.",
                        style: textTheme.bodyMedium?.copyWith(
                          color: isDark ? CColors.lightGrey : CColors.darkGrey,
                        ),
                      ),
                      const SizedBox(height: CSizes.xl),
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
                        validator: (value) {
                          if (value == null || value.isEmpty || !value.contains('@')) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: CSizes.xl),
                      _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : CButton(
                        text: 'Send Reset Link',
                        onPressed: _handleSendResetLink,
                        width: double.infinity,
                        backgroundColor: CColors.secondary,
                        foregroundColor: CColors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: CColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
    ));
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: CColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
    ));
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}
