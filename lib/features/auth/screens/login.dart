import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chal_ostaad/core/constants/colors.dart';
import 'package:chal_ostaad/core/constants/sizes.dart';
import 'package:chal_ostaad/shared/logo/logo.dart';
import 'package:chal_ostaad/shared/widgets/Cbutton.dart';
import 'package:chal_ostaad/shared/widgets/Ccontainer.dart';
import 'package:chal_ostaad/shared/widgets/CtextField.dart';
import 'package:chal_ostaad/features/splash/role_selection.dart';

import '../../../shared/widgets/common_header.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    print('🔍 [DEBUG] Login page initialized');
    _loadUserRole();
  }

  // Load user role from multiple sources
  Future<void> _loadUserRole() async {
    try {
      print('🔍 [DEBUG] Starting to load user role...');

      String? role;

      // Method 1: Try temporary storage first
      role = RoleSelection.tempUserRole;
      if (role != null) {
        print('✅ [DEBUG] Role loaded from TEMPORARY storage: $role');
      } else {
        print('⚠️ [DEBUG] No role in temporary storage');
      }

      // Method 2: Try SharedPreferences as backup
      if (role == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          role = prefs.getString('user_role');
          if (role != null) {
            print('✅ [DEBUG] Role loaded from SHARED PREFERENCES: $role');
          } else {
            print('⚠️ [DEBUG] No role in SharedPreferences');
          }
        } catch (e) {
          print('⚠️ [DEBUG] SharedPreferences failed: $e');
        }
      }

      setState(() {
        _userRole = role;
      });

      print('🔍 [DEBUG] Final user role set in state: $_userRole');

      if (_userRole != null) {
        print(
          '🎯 [DEBUG] Ready! User will go to ${_userRole!.toUpperCase()} dashboard after login',
        );
      } else {
        print('⚠️ [DEBUG] No role found! User needs to select role first');
      }
    } catch (e) {
      print('❌ [DEBUG] Error loading role: $e');
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
          constraints: BoxConstraints(minHeight: size.height),
          child: Column(
            children: [
              CommonHeader(
                title: 'Login',
              ),

              // Login Form
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
                        // Welcome Section
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello Again!',
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? CColors.white
                                    : CColors.textPrimary,
                                fontSize: 24,
                              ),
                            ),
                            const SizedBox(height: CSizes.xs),
                            Text(
                              'We\'re happy to see you. Log in and get started.',
                              style: textTheme.bodyMedium?.copyWith(
                                color: isDark
                                    ? CColors.lightGrey
                                    : CColors.darkGrey,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: CSizes.xl),

                        // Email Field
                        CTextField(
                          label: 'Email',
                          hintText: 'Enter your email address',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          prefixIcon: Icon(
                            Icons.email_outlined,
                            color: isDark
                                ? CColors.lightGrey
                                : CColors.darkGrey,
                            size: 20,
                          ),
                          isRequired: true,
                          validator: _validateEmail,
                        ),

                        const SizedBox(height: CSizes.lg),

                        // Password Field
                        CTextField(
                          label: 'Password',
                          hintText: 'Enter your password',
                          controller: _passwordController,
                          keyboardType: TextInputType.visiblePassword,
                          obscureText: _obscurePassword,
                          prefixIcon: Icon(
                            Icons.lock_outlined,
                            color: isDark
                                ? CColors.lightGrey
                                : CColors.darkGrey,
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: isDark
                                  ? CColors.lightGrey
                                  : CColors.darkGrey,
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

                        const SizedBox(height: CSizes.md),

                        // Forgot Password
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _handleForgotPassword,
                            child: Text(
                              'Forgot Password?',
                              style: textTheme.bodyMedium?.copyWith(
                                color: CColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: CSizes.xl),

                        // Login Button
                        _buildLoginButton(),

                        const SizedBox(height: CSizes.xl),

                        // Sign Up Section
                        _buildSignUpSection(context, textTheme, isDark),

                        // Debug button to check role
                        const SizedBox(height: CSizes.lg),
                        Center(
                          child: TextButton(
                            onPressed: () {
                              print(
                                '🔍 [DEBUG MANUAL CHECK] Current role: $_userRole',
                              );
                              _loadUserRole(); // Reload to check
                            },
                            child: Text(
                              'Debug: Check Current Role',
                              style: textTheme.bodySmall?.copyWith(
                                color: CColors.darkGrey,
                              ),
                            ),
                          ),
                        ),
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

  Widget _buildLoginButton() {
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
            text: 'Login',
            onPressed: _handleLogin,
            width: double.infinity,
            backgroundColor: CColors.secondary,
            foregroundColor: CColors.white,
          );
  }

  Widget _buildSignUpSection(
    BuildContext context,
    TextTheme textTheme,
    bool isDark,
  ) {
    return Center(

      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Don't have an account? ",
            style: textTheme.bodyMedium?.copyWith(
              color: isDark ? CColors.lightGrey : CColors.darkGrey,
            ),
          ),
          // Use a TextButton for the clickable part
          TextButton(
            onPressed: _navigateToRoleBasedSignup,
            // Remove default padding for seamless alignment
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size(50, 30), // Adjust if needed
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerLeft
            ),
            child: Text(
              'Sign Up!',
              style: textTheme.bodyMedium?.copyWith(
                color: CColors.primary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email address';
    }
    if (!value.contains('@') || !value.contains('.')) {
      return 'Please enter a valid email address';
    }
    return null;
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

  void _handleLogin() {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Simulate login process
    Future.delayed(const Duration(seconds: 2), () {
      setState(() => _isLoading = false);

      // Navigate to dashboard based on user role
      _navigateToDashboard();
    });
  }

  void _navigateToDashboard() {
    print('🔍 [DEBUG] Navigating to dashboard. Current role: $_userRole');

    if (_userRole == 'client') {
      print('🚀 [DEBUG] Navigating to CLIENT dashboard');
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/client-dashboard',
        (route) => false,
      );
    } else if (_userRole == 'worker') {
      print('🚀 [DEBUG] Navigating to WORKER dashboard');
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/worker-dashboard',
        (route) => false,
      );
    } else {
      print('⚠️ [DEBUG] No role found! Navigating to role selection');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select your role first'),
          backgroundColor: CColors.error,
        ),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/role', (route) => false);
    }
  }

  void _navigateToRoleBasedSignup() {
    print('🔍 [DEBUG] Navigating to signup. Current role: $_userRole');

    if (_userRole == 'client') {
      print('🚀 [DEBUG] Navigating to CLIENT signup');
      Navigator.pushNamed(context, '/client-signup');
    } else if (_userRole == 'worker') {
      print('🚀 [DEBUG] Navigating to WORKER signup');
      Navigator.pushNamed(context, '/worker-login');
    } else {
      print('⚠️ [DEBUG] No role found! Navigating to role selection');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select your role first'),
          backgroundColor: CColors.error,
        ),
      );
      Navigator.pushNamed(context, '/role');
    }
  }

  void _handleForgotPassword() {
    Navigator.pushNamed(context, '/forgot-password');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
