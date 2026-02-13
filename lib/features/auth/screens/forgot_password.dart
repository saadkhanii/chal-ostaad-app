// lib/features/auth/screens/forgot_password.dart

import 'package:chal_ostaad/core/providers/auth_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/services/localization_service.dart';
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
  Future<void> _handleSendResetLink(WidgetRef ref) async {
    if (!_formKey.currentState!.validate()) return;
    if (_userRole == null) {
      _showErrorMessage('errors.role_not_identified'.tr());
      return;
    }

    // Update loading state using Riverpod
    ref.read(authProvider.notifier).state = const AuthState(isLoading: true);

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
        _showSuccessMessage('auth.reset_link_sent'.tr());
        // Navigate back to the login screen after sending the link
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _showErrorMessage('errors.email_not_registered'.tr(args: [_userRole ?? 'user']));
      } else {
        _showErrorMessage('errors.try_again'.tr());
      }
      _logger.e('Forgot Password error: ${e.code}');
    } on Exception catch(e) {
      _logger.e("Forgot Password generic error: $e");
      _showErrorMessage('errors.unexpected_error'.tr());
    }
    finally {
      if (mounted) {
        // Reset loading state
        ref.read(authProvider.notifier).state = const AuthState(isLoading: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final authState = ref.watch(authProvider);
        final size = MediaQuery.of(context).size;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textTheme = Theme.of(context).textTheme;
        final isUrdu = LocalizationService.isUrdu(context);

        return Scaffold(
          backgroundColor: isDark ? CColors.dark : CColors.white,
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.height),
              child: Column(
                children: [
                  CommonHeader(
                    title: 'auth.reset_password'.tr(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(CSizes.xl, CSizes.sm, CSizes.xl, CSizes.xl),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: isUrdu ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          Text(
                            'auth.forgot_password'.tr(),
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark ? CColors.white : CColors.textPrimary,
                              fontSize: 20,
                            ),
                            textAlign: isUrdu ? TextAlign.right : TextAlign.left,
                          ),
                          const SizedBox(height: CSizes.xs),
                          Text(
                            'auth.reset_instruction'.tr(),
                            style: textTheme.bodyMedium?.copyWith(
                              color: isDark ? CColors.lightGrey : CColors.darkGrey,
                              fontSize: 12,
                            ),
                            textAlign: isUrdu ? TextAlign.right : TextAlign.left,
                          ),
                          const SizedBox(height: CSizes.md),
                          CTextField(
                            label: 'auth.email'.tr(),
                            hintText: 'auth.email_hint_reset'.tr(),
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            prefixIcon: Icon(
                              Icons.email_outlined,
                              color: isDark ? CColors.lightGrey : CColors.darkGrey,
                              size: 20,
                            ),
                            isRequired: true,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'auth.email_required'.tr();
                              }
                              if (!value.contains('@') || !value.contains('.')) {
                                return 'auth.email_invalid'.tr();
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: CSizes.lg),
                          CButton(
                            text: 'auth.send_reset_link'.tr(),
                            onPressed: () => _handleSendResetLink(ref),
                            width: double.infinity,
                            isLoading: authState.isLoading,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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