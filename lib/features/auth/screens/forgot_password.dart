// lib/features/auth/screens/forgot_password.dart

import 'package:chal_ostaad/core/providers/auth_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

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
  String? _userRole;

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
  }

  Future<void> _handleSendResetLink(WidgetRef ref) async {
    if (!_formKey.currentState!.validate()) return;
    if (_userRole == null) {
      _showErrorMessage('errors.role_not_identified'.tr());
      return;
    }

    ref.read(authProvider.notifier).state = const AuthState(isLoading: true);

    final email = _emailController.text.trim();

    try {
      final secondaryApp = Firebase.app(_userRole!);
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      await secondaryAuth.sendPasswordResetEmail(email: email);

      if (mounted) {
        _showSuccessMessage('auth.reset_link_sent'.tr());
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _showErrorMessage('errors.email_not_registered'.tr(args: [_userRole ?? 'user']));
      } else {
        _showErrorMessage('errors.try_again'.tr());
      }
    } on Exception catch(_) {
      _showErrorMessage('errors.unexpected_error'.tr());
    } finally {
      if (mounted) {
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
        final isUrdu = context.locale.languageCode == 'ur';

        return Scaffold(
          backgroundColor: isDark ? CColors.dark : CColors.white,
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.height),
              child: Column(
                children: [
                  // Using translation key from ur.json
                  CommonHeader(
                    title: 'auth.password'.tr(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(CSizes.xl, CSizes.sm, CSizes.xl, CSizes.xl),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: CSizes.md),
                          Text(
                            'auth.forgot_password'.tr(),
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark ? CColors.white : CColors.textPrimary,
                              fontSize: isUrdu ? 24 : 20,
                            ),
                          ),
                          const SizedBox(height: CSizes.sm),
                          Text(
                            'auth.reset_instruction'.tr(),
                            style: textTheme.bodyMedium?.copyWith(
                              color: isDark ? CColors.lightGrey : CColors.darkGrey,
                              fontSize: isUrdu ? 16 : 12,
                              height: isUrdu ? 1.5 : 1.2,
                            ),
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