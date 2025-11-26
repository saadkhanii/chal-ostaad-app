// lib/features/auth/screens/login.dart

import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:chal_ostaad/features/splash/role_selection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = RoleSelection.tempUserRole ?? prefs.getString('user_role');
    });
    _logger.i('Login screen initialized for role: $_userRole');
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    if (_userRole == null) {
      _showErrorMessage('Could not determine user role. Please go back and select a role.');
      return;
    }

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final collectionName = _userRole == 'client' ? 'clients' : 'workers';

    try {
      _logger.i('Attempting login for role: $_userRole with email: $email');

      // STEP 1: Verify user exists in Firestore
      final querySnapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .where('personalInfo.email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        _logger.w('Login failed: Email $email not found in "$collectionName" collection.');
        throw Exception('This email is not registered as a $_userRole.');
      }
      _logger.i('Firestore check passed: User exists in "$collectionName".');

      // STEP 2: Firebase Auth login
      final secondaryApp = Firebase.app(_userRole!);
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      final userCredential = await secondaryAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      _logger.i('Firebase Auth login successful for UID: ${userCredential.user?.uid}');

      // STEP 3: Verify account status
      final docData = querySnapshot.docs.first.data();
      if (docData['account']?['accountStatus'] != 'active') {
        await secondaryAuth.signOut();
        throw FirebaseAuthException(
          code: 'user-disabled',
          message: 'This account has been disabled or is not yet active.',
        );
      }

      _logger.i('Account status is active.');

      // STEP 4: Enhanced Name Extraction
      String userName = _extractUserName(docData, email, _userRole!);

      // STEP 5: Save session and navigate
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', email);
      await prefs.setString('user_uid', userCredential.user!.uid);
      await prefs.setString('user_role', _userRole!);
      await prefs.setString('user_name', userName);

      _logger.i('User session saved - Name: $userName, Email: $email, Role: $_userRole');

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          _userRole == 'client' ? AppRoutes.clientDashboard : AppRoutes.workerDashboard,
              (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      _logger.e('FirebaseAuthException during login: ${e.code}');
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        _showErrorMessage('Invalid email or password. Please try again.');
      } else if (e.code == 'user-disabled') {
        _showErrorMessage('Your account is not active or has been disabled by an admin.');
      } else {
        _showErrorMessage('An error occurred during login. Please try again.');
      }
    } on Exception catch (e) {
      final errorMessage = e.toString().startsWith('Exception: ') ? e.toString().substring(11) : e.toString();
      _logger.e('Generic exception during login: $errorMessage');
      _showErrorMessage(errorMessage);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _extractUserName(Map<String, dynamic> docData, String email, String userRole) {
    String userName = email.split('@').first; // Default to email username

    // Try multiple possible field locations for name
    final possibleNameFields = [
      docData['name'],
      docData['fullName'],
      docData['displayName'],
      docData['firstName'],
    ];

    // Check personalInfo for both workers and clients
    if (docData['personalInfo'] is Map) {
      final personalInfo = docData['personalInfo'] as Map<String, dynamic>;
      possibleNameFields.addAll([
        personalInfo['name'],
        personalInfo['fullName'],
        personalInfo['firstName'],
      ]);
    }

    // Check userInfo if exists
    if (docData['userInfo'] is Map) {
      final userInfo = docData['userInfo'] as Map<String, dynamic>;
      possibleNameFields.addAll([
        userInfo['name'],
        userInfo['fullName'],
      ]);
    }

    // Find the first non-null, non-empty name
    for (var name in possibleNameFields) {
      if (name != null && name.toString().isNotEmpty) {
        userName = name.toString();
        _logger.i('Extracted $userRole name: $userName');
        break;
      }
    }

    if (userName == email.split('@').first) {
      _logger.i('No name found in document, using email username: $userName');
    }

    return userName;
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
              CommonHeader(title: 'Login'),
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
                          'Hello Again!',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? CColors.white : CColors.textPrimary,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: CSizes.xs),
                        Text(
                          'We\'re happy to see you. Log in as a ${_userRole ?? 'user'}.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: isDark ? CColors.lightGrey : CColors.darkGrey,
                          ),
                        ),
                        const SizedBox(height: CSizes.xl),
                        CTextField(
                          label: 'Email',
                          hintText: 'Enter your email address',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          prefixIcon: Icon(Icons.email_outlined,
                              color: isDark ? CColors.lightGrey : CColors.darkGrey, size: 20),
                          isRequired: true,
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: CSizes.lg),
                        CTextField(
                          label: 'Password',
                          hintText: 'Enter your password',
                          controller: _passwordController,
                          keyboardType: TextInputType.visiblePassword,
                          obscureText: _obscurePassword,
                          prefixIcon: Icon(Icons.lock_outlined,
                              color: isDark ? CColors.lightGrey : CColors.darkGrey, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: isDark ? CColors.lightGrey : CColors.darkGrey,
                                size: 20),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          isRequired: true,
                          validator: _validatePassword,
                        ),
                        const SizedBox(height: CSizes.md),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _handleForgotPassword,
                            child: Text(
                              'Forgot Password?',
                              style: textTheme.bodyMedium
                                  ?.copyWith(color: CColors.primary, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(height: CSizes.xl),
                        _buildLoginButton(),
                        const SizedBox(height: CSizes.xl),
                        _buildSignUpSection(context, textTheme, isDark),
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
        ? Center(child: CircularProgressIndicator(color: CColors.primary))
        : CButton(
      text: 'Login',
      onPressed: _handleLogin,
      width: double.infinity,
      backgroundColor: CColors.secondary,
      foregroundColor: CColors.white,
    );
  }

  Widget _buildSignUpSection(BuildContext context, TextTheme textTheme, bool isDark) {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("Don't have an account? ",
              style: textTheme.bodyMedium?.copyWith(color: isDark ? CColors.lightGrey : CColors.darkGrey)),
          TextButton(
            onPressed: _navigateToRoleBasedSignup,
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero, minimumSize: const Size(50, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text(
              'Sign Up!',
              style: textTheme.bodyMedium
                  ?.copyWith(color: CColors.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToRoleBasedSignup() {
    if (_userRole == 'client') {
      Navigator.pushNamed(context, AppRoutes.clientSignUp);
    } else if (_userRole == 'worker') {
      Navigator.pushNamed(context, AppRoutes.workerLogin);
    } else {
      _showErrorMessage('Please select a role first.');
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.role, (route) => false);
    }
  }

  void _handleForgotPassword() {
    Navigator.pushNamed(context, AppRoutes.forgotPassword);
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your email address';
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) return 'Please enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password';
    return null;
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
}