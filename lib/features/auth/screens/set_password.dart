// lib/features/auth/screens/set_password.dart

import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../shared/widgets/Cbutton.dart';
import '../../../shared/widgets/CtextField.dart';
import '../../../shared/widgets/common_header.dart';

class SetPasswordScreen extends ConsumerStatefulWidget {
  final String email;

  const SetPasswordScreen({
    super.key,
    required this.email,
  });

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final Logger _logger = Logger();

  Future<void> _handleSetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    String? userRole;

    try {
      final prefs = await SharedPreferences.getInstance();
      userRole = prefs.getString('user_role') ?? 'client';
      _logger.i('Attempting to create user for role: $userRole');

      final secondaryApp = Firebase.app(userRole);
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final password = _passwordController.text;

      UserCredential userCredential = await secondaryAuth.createUserWithEmailAndPassword(
        email: widget.email,
        password: password,
      );

      _logger.i('Successfully created user in Firebase Auth. UID: ${userCredential.user?.uid}');

      final collectionName = userRole == 'client' ? 'clients' : 'workers';
      final querySnapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .where('personalInfo.email', isEqualTo: widget.email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        await userCredential.user?.delete();
        throw Exception('Could not find your registration data. Please sign up again.');
      }

      final oldDoc = querySnapshot.docs.first;
      final oldDocData = oldDoc.data();
      final newDocRef = FirebaseFirestore.instance.collection(collectionName).doc(userCredential.user!.uid);

      await newDocRef.set({
        ...oldDocData,
        'account': {
          ...(oldDocData['account'] as Map<String, dynamic>? ?? {}),
          'accountStatus': 'active',
          'uid': userCredential.user!.uid,
        },
      });

      await newDocRef.update({'verification': FieldValue.delete()});
      await oldDoc.reference.delete();

      _logger.i('Firestore document migrated to UID and activated for ${widget.email}.');

      if (mounted) {
        _showSuccessMessage('Account created successfully!');
        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        _showErrorMessage('This email is already registered for a ${userRole ?? 'user'} account.');
      } else if (e.code == 'weak-password') {
        _showErrorMessage('The password is too weak (must be at least 6 characters).');
      } else {
        _showErrorMessage('An authentication error occurred: ${e.message}');
      }
      _logger.e('FirebaseAuthException in Set Password: ${e.code}');
    } on Exception catch (e) {
      final errorMessage = e.toString().startsWith('Exception: ') ? e.toString().substring(11) : e.toString();
      _logger.e('Set Password Failed: $errorMessage');
      _showErrorMessage(errorMessage);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
              const CommonHeader(title: 'Set Password'),
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
                          'Set a new password',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? CColors.white : CColors.textPrimary,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: CSizes.sm),
                        Text(
                          'Create a new, strong password to complete your account.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                          ),
                        ),
                        const SizedBox(height: CSizes.xl),
                        CTextField(
                          label: 'Password',
                          hintText: 'Enter your new password',
                          controller: _passwordController,
                          keyboardType: TextInputType.visiblePassword,
                          obscureText: _obscurePassword,
                          prefixIcon: Icon(
                            Icons.lock_outline,
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: isDark ? CColors.lightGrey : CColors.darkGrey,
                                size: 20),
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
                                size: 20),
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
      text: 'Create Account & Login',
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
}
