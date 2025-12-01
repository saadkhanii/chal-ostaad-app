// lib/features/auth/screens/login.dart

import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:chal_ostaad/features/splash/role_selection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../shared/widgets/Cbutton.dart';
import '../../../shared/widgets/CtextField.dart';
import '../../../shared/widgets/common_header.dart';

class Login extends StatefulWidget {
  final String? userRole;

  const Login({super.key, this.userRole});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  String? _userRole;
  bool _credentialsLoaded = false;

  @override
  void initState() {
    super.initState();
    _initializeCredentials();
  }

  // Helper method to get role-specific key names
  String _getRoleSpecificKey(String baseKey, String userRole) {
    return '${userRole}_$baseKey';
  }

  Future<void> _initializeCredentials() async {
    print('🚀 ===== LOGIN INIT START =====');

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Get all keys for debugging
      final keys = prefs.getKeys().toList()..sort();
      print('📋 ALL SHARED PREFS KEYS: $keys');

      // 2. Get user role
      _userRole = widget.userRole ??
          RoleSelection.tempUserRole ??
          prefs.getString('user_role');
      print('🎯 USER ROLE: $_userRole');

      if (_userRole == null) {
        print('⚠️ No role found, going to role selection');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushNamedAndRemoveUntil(
              context,
              AppRoutes.role,
                  (route) => false
          );
        });
        return;
      }

      // 3. Load remember me - IMPORTANT: Check if key exists
      if (prefs.containsKey('remember_me')) {
        _rememberMe = prefs.getBool('remember_me') ?? true;
      } else {
        // If key doesn't exist, default to true and save it
        _rememberMe = true;
        await prefs.setBool('remember_me', true);
      }
      print('💾 REMEMBER ME: $_rememberMe (key exists: ${prefs.containsKey('remember_me')})');

      // 4. Load saved credentials if remember me is true
      if (_rememberMe && _userRole != null) {
        // Use role-specific keys
        final emailKey = _getRoleSpecificKey('saved_email', _userRole!);
        final passwordKey = _getRoleSpecificKey('saved_password', _userRole!);

        final savedEmail = prefs.getString(emailKey);
        final savedPassword = prefs.getString(passwordKey);

        print('📧 SAVED EMAIL FOR $_userRole: $savedEmail');
        print('🔒 SAVED PASSWORD EXISTS FOR $_userRole: ${savedPassword != null}');

        if (savedEmail != null && savedEmail.isNotEmpty) {
          _emailController.text = savedEmail;
          print('✅ EMAIL AUTO-FILLED FOR $_userRole: $savedEmail');
        }

        if (savedPassword != null && savedPassword.isNotEmpty) {
          _passwordController.text = savedPassword;
          print('✅ PASSWORD AUTO-FILLED FOR $_userRole');
        }
      }

      setState(() {
        _credentialsLoaded = true;
      });

      print('✅ LOGIN SCREEN READY FOR $_userRole');
      print('📝 Email field has text: ${_emailController.text.isNotEmpty}');
      print('🔒 Password field length: ${_passwordController.text.length}');

    } catch (e) {
      print('❌ ERROR: $e');
      setState(() {
        _credentialsLoaded = true;
      });
    }

    print('🚀 ===== LOGIN INIT COMPLETE =====');
  }

  Future<void> _saveCredentials() async {
    print('💾 ===== SAVING CREDENTIALS =====');

    try {
      final prefs = await SharedPreferences.getInstance();

      if (_userRole == null) {
        print('❌ Cannot save credentials: userRole is null');
        return;
      }

      // Always save remember_me preference (global)
      await prefs.setBool('remember_me', _rememberMe);
      print('💾 Remember me saved: $_rememberMe');

      // Save user role (global)
      await prefs.setString('user_role', _userRole!);
      print('💾 User role saved: $_userRole');

      if (_rememberMe) {
        final email = _emailController.text.trim();
        final password = _passwordController.text;

        if (email.isNotEmpty) {
          // Save with role-specific key
          final emailKey = _getRoleSpecificKey('saved_email', _userRole!);
          await prefs.setString(emailKey, email);
          print('💾 Email saved for $_userRole: $email');
        }

        if (password.isNotEmpty) {
          // Save with role-specific key
          final passwordKey = _getRoleSpecificKey('saved_password', _userRole!);
          await prefs.setString(passwordKey, password);
          print('💾 Password saved for $_userRole (length: ${password.length})');
        }

        print('✅ CREDENTIALS SAVED SUCCESSFULLY for $_userRole');
      } else {
        // Clear role-specific credentials if remember me is false
        final emailKey = _getRoleSpecificKey('saved_email', _userRole!);
        final passwordKey = _getRoleSpecificKey('saved_password', _userRole!);

        await prefs.remove(emailKey);
        await prefs.remove(passwordKey);
        print('🧹 Credentials cleared for $_userRole (remember me is false)');
      }

      // DEBUG: Show what's saved
      final keys = prefs.getKeys().toList()..sort();
      print('📋 FINAL KEYS AFTER SAVE: $keys');

      // Show role-specific values
      print('📧 client_saved_email: ${prefs.getString('client_saved_email')}');
      print('🔐 client_saved_password exists: ${prefs.getString('client_saved_password') != null}');
      print('📧 worker_saved_email: ${prefs.getString('worker_saved_email')}');
      print('🔐 worker_saved_password exists: ${prefs.getString('worker_saved_password') != null}');

    } catch (e) {
      print('❌ ERROR SAVING CREDENTIALS: $e');
    }

    print('💾 ===== SAVE COMPLETE =====');
  }

  Future<void> _clearSavedCredentials() async {
    print('🧹 ===== CLEARING CREDENTIALS =====');

    try {
      final prefs = await SharedPreferences.getInstance();

      if (_userRole == null) {
        print('⚠️ Cannot clear credentials: userRole is null');
        return;
      }

      // Clear role-specific credentials
      final emailKey = _getRoleSpecificKey('saved_email', _userRole!);
      final passwordKey = _getRoleSpecificKey('saved_password', _userRole!);

      await prefs.remove(emailKey);
      await prefs.remove(passwordKey);
      await prefs.setBool('remember_me', false);

      // Clear text fields
      _emailController.clear();
      _passwordController.clear();

      setState(() {
        _rememberMe = false;
      });

      print('✅ CREDENTIALS CLEARED FOR $_userRole');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved credentials cleared for $_userRole'),
            backgroundColor: CColors.success,
          ),
        );
      }

    } catch (e) {
      print('❌ ERROR CLEARING CREDENTIALS: $e');
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    if (_userRole == null) {
      _showErrorMessage('Please select a role first.');
      return;
    }

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final collectionName = _userRole == 'client' ? 'clients' : 'workers';

    try {
      print('🔐 ===== LOGIN ATTEMPT =====');
      print('👤 Role: $_userRole');
      print('📧 Email: $email');

      // Verify user exists in Firestore
      final querySnapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .where('personalInfo.email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception('This email is not registered as a $_userRole.');
      }

      // Get the correct Firebase app for this user role
      print('🔧 Getting Firebase app for role: $_userRole');
      final firebaseApp = Firebase.app(_userRole!);
      final auth = FirebaseAuth.instanceFor(app: firebaseApp);
      print('✅ Using Firebase app: ${firebaseApp.name}');

      final userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('✅ Firebase Auth successful');

      // Verify account status
      final docData = querySnapshot.docs.first.data();
      if (docData['account']?['accountStatus'] != 'active') {
        await auth.signOut(); // Use the correct auth instance
        throw FirebaseAuthException(
          code: 'user-disabled',
          message: 'This account has been disabled or is not yet active.',
        );
      }

      // Extract user name
      String userName = _extractUserName(docData, email, _userRole!);

      // Save session data with role-specific keys
      final prefs = await SharedPreferences.getInstance();

      // Save global session data
      await prefs.setString('user_email', email);
      await prefs.setString('user_uid', userCredential.user!.uid);
      await prefs.setString('user_role', _userRole!);
      await prefs.setString('user_name', userName);

      // Save role-specific session data
      final uidKey = _getRoleSpecificKey('user_uid', _userRole!);
      final nameKey = _getRoleSpecificKey('user_name', _userRole!);
      final emailKeySession = _getRoleSpecificKey('user_email', _userRole!);

      await prefs.setString(uidKey, userCredential.user!.uid);
      await prefs.setString(nameKey, userName);
      await prefs.setString(emailKeySession, email);

      print('💾 Session data saved');
      print('👤 Name: $userName');
      print('🆔 UID: ${userCredential.user!.uid}');
      print('🎯 Role: $_userRole');

      // Save login credentials (this is the key part!)
      await _saveCredentials();

      print('✅ LOGIN COMPLETE - Navigating to dashboard');

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          _userRole == 'client' ? AppRoutes.clientDashboard : AppRoutes.workerDashboard,
              (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error: ${e.code}');
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        _showErrorMessage('Invalid email or password. Please try again.');
      } else if (e.code == 'user-disabled') {
        _showErrorMessage('Your account is not active or has been disabled by an admin.');
      } else {
        _showErrorMessage('An error occurred during login. Please try again.');
      }
    } on Exception catch (e) {
      print('❌ Login Error: $e');
      _showErrorMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _extractUserName(Map<String, dynamic> docData, String email, String userRole) {
    String userName = email.split('@').first;

    final possibleNameFields = [
      docData['name'],
      docData['fullName'],
      docData['displayName'],
      docData['firstName'],
    ];

    if (docData['personalInfo'] is Map) {
      final personalInfo = docData['personalInfo'] as Map<String, dynamic>;
      possibleNameFields.addAll([
        personalInfo['name'],
        personalInfo['fullName'],
        personalInfo['firstName'],
      ]);
    }

    if (docData['userInfo'] is Map) {
      final userInfo = docData['userInfo'] as Map<String, dynamic>;
      possibleNameFields.addAll([
        userInfo['name'],
        userInfo['fullName'],
      ]);
    }

    for (var name in possibleNameFields) {
      if (name != null && name.toString().isNotEmpty) {
        userName = name.toString();
        break;
      }
    }

    return userName;
  }

  @override
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    if (!_credentialsLoaded) {
      return Scaffold(
        backgroundColor: isDark ? CColors.dark : CColors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: CColors.primary),
              SizedBox(height: 20),
              Text('Loading saved credentials...'),
            ],
          ),
        ),
      );
    }

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

                        // Remember me toggle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  onChanged: (value) {
                                    setState(() {
                                      _rememberMe = value ?? true;
                                    });
                                  },
                                  activeColor: CColors.primary,
                                  checkColor: CColors.white,
                                ),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _rememberMe = !_rememberMe;
                                    });
                                  },
                                  child: Text(
                                    'Remember me',
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: isDark ? CColors.lightGrey : CColors.darkGrey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_emailController.text.isNotEmpty)
                              TextButton(
                                onPressed: _clearSavedCredentials,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(50, 30),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Clear saved',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: CColors.error,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                          ],
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
            onPressed: () => _navigateToRoleBasedSignup(),
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

  Future<void> _debugCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList()..sort();

    print('=== DEBUG CREDENTIALS ===');
    print('All keys: $keys');

    // Show all key-value pairs
    for (var key in keys) {
      final value = prefs.get(key);
      print('$key: $value');
    }

    // Show role-specific credentials
    print('\n=== ROLE-SPECIFIC CREDENTIALS ===');
    print('📧 client_saved_email: ${prefs.getString('client_saved_email')}');
    print('🔐 client_saved_password exists: ${prefs.getString('client_saved_password') != null}');
    print('📧 worker_saved_email: ${prefs.getString('worker_saved_email')}');
    print('🔐 worker_saved_password exists: ${prefs.getString('worker_saved_password') != null}');

    print('\n=== CURRENT STATE ===');
    print('Email controller: ${_emailController.text}');
    print('Password controller: ${_passwordController.text}');
    print('Remember me: $_rememberMe');
    print('User role: $_userRole');
    print('========================');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Debug Info - $_userRole'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('SharedPreferences:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              for (var key in keys)
                Text('• $key: ${prefs.get(key)?.toString() ?? "null"}'),
              SizedBox(height: 20),
              Text('UI State:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Email: ${_emailController.text}'),
              Text('Password: ${"*" * _passwordController.text.length}'),
              Text('Remember me: $_rememberMe'),
              Text('User role: $_userRole'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
}