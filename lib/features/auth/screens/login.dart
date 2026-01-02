// lib/features/auth/screens/login.dart

import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/role_provider.dart';
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
  bool _obscurePassword = true;
  bool _rememberMe = true;

  // Helper method to get role-specific key names
  String _getRoleSpecificKey(String baseKey, String userRole) {
    return '${userRole}_$baseKey';
  }

  Future<void> _saveCredentials(String userRole) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Explicitly set the bool and sync to ensure it's written
      await prefs.setBool('remember_me', _rememberMe);
      await prefs.setString('user_role', userRole);

      if (_rememberMe) {
        final email = _emailController.text.trim();
        final password = _passwordController.text;

        if (email.isNotEmpty) {
          final emailKey = _getRoleSpecificKey('saved_email', userRole);
          await prefs.setString(emailKey, email);
        }

        if (password.isNotEmpty) {
          final passwordKey = _getRoleSpecificKey('saved_password', userRole);
          await prefs.setString(passwordKey, password);
        }
      } else {
        // Clear role-specific credentials
        final emailKey = _getRoleSpecificKey('saved_email', userRole);
        final passwordKey = _getRoleSpecificKey('saved_password', userRole);
        await prefs.remove(emailKey);
        await prefs.remove(passwordKey);
      }
    } catch (e) {
      debugPrint('Error saving credentials: $e');
    }
  }

  Future<void> _clearSavedCredentials(String userRole) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final emailKey = _getRoleSpecificKey('saved_email', userRole);
      final passwordKey = _getRoleSpecificKey('saved_password', userRole);

      await prefs.remove(emailKey);
      await prefs.remove(passwordKey);
      await prefs.setBool('remember_me', false);

      _emailController.clear();
      _passwordController.clear();

      setState(() {
        _rememberMe = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved credentials cleared'),
            backgroundColor: CColors.success,
          ),
        );
      }
    } catch (e) {
      _showErrorMessage('Failed to clear credentials');
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
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        // Use addPostFrameCallback to handle initial load safely
        WidgetsBinding.instance.addPostFrameCallback((_) {
            // Only try to load if controllers are empty to avoid overwriting user input
            if (_emailController.text.isEmpty && _passwordController.text.isEmpty) {
               final userRole = widget.userRole ?? ref.read(selectedRoleProvider);
               if (userRole != null) {
                 _loadCredentialsForRole(userRole);
               }
            }
        });

        final authState = ref.watch(authProvider);
        final userRole = widget.userRole ?? ref.read(selectedRoleProvider) ?? 'user';
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
                    backgroundColor: CColors.primary, 
                    textColor: CColors.secondary,
                    heightFactor: 0.25,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(CSizes.xl, CSizes.sm, CSizes.xl, CSizes.xl),
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
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: CSizes.xs),
                          Text(
                            'We\'re happy to see you. Log in as a $userRole.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: isDark ? CColors.lightGrey : CColors.darkGrey,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: CSizes.md),
                          CTextField(
                            label: 'Email',
                            hintText: 'Enter your email address',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            prefixIcon: Icon(
                              Icons.email_outlined,
                              color: isDark ? CColors.lightGrey : CColors.darkGrey,
                              size: 20,
                            ),
                            isRequired: true,
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: CSizes.md),
                          CTextField(
                            label: 'Password',
                            hintText: 'Enter your password',
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
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: isDark ? CColors.lightGrey : CColors.darkGrey,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            isRequired: true,
                            validator: _validatePassword,
                          ),
                          const SizedBox(height: CSizes.md),

                          // Remember me toggle
                          Transform.translate(
                            offset: const Offset(-10, 0),
                            child: Row(
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
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
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
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_emailController.text.isNotEmpty)
                                  TextButton(
                                    onPressed: () => _clearSavedCredentials(userRole),
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
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(height: CSizes.sm),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _handleForgotPassword,
                              child: Text(
                                'Forgot Password?',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: CColors.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: CSizes.sm),
                          _buildLoginButton(authState, userRole, ref),
                          const SizedBox(height: CSizes.lg),
                          _buildSignUpSection(context, textTheme, isDark, userRole),
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

  Future<void> _loadCredentialsForRole(String userRole) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load remember_me first
      if (mounted) {
         setState(() {
            _rememberMe = prefs.getBool('remember_me') ?? true;
         });
      }

      if (_rememberMe) {
          final emailKey = _getRoleSpecificKey('saved_email', userRole);
          final passwordKey = _getRoleSpecificKey('saved_password', userRole);

          final savedEmail = prefs.getString(emailKey);
          final savedPassword = prefs.getString(passwordKey);

          if (savedEmail != null && savedEmail.isNotEmpty && _emailController.text.isEmpty) {
            _emailController.text = savedEmail;
          }

          if (savedPassword != null && savedPassword.isNotEmpty && _passwordController.text.isEmpty) {
            _passwordController.text = savedPassword;
          }
      }
    } catch (e) {
      debugPrint('Error loading credentials: $e');
    }
  }

  Future<void> _handleLogin(String userRole, WidgetRef ref) async {
    if (!_formKey.currentState!.validate()) return;

    if (userRole == null) {
      _showErrorMessage('Please select a role first.');
      return;
    }

    final authNotifier = ref.read(authProvider.notifier);

    // Update loading state
    ref.read(authProvider.notifier).state = const AuthState(isLoading: true);

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final collectionName = userRole == 'client' ? 'clients' : 'workers';

    try {
      // Verify user exists in Firestore
      final querySnapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .where('personalInfo.email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception('This email is not registered as a $userRole.');
      }

      // Get the correct Firebase app for this user role
      final firebaseApp = Firebase.app(userRole);
      final auth = FirebaseAuth.instanceFor(app: firebaseApp);

      final userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Verify account status
      final docData = querySnapshot.docs.first.data();
      if (docData['account']?['accountStatus'] != 'active') {
        await auth.signOut();
        throw FirebaseAuthException(
          code: 'user-disabled',
          message: 'This account has been disabled or is not yet active.',
        );
      }

      // Extract user name
      final userName = _extractUserName(docData, email, userRole);

      // Save credentials if remember me is checked
      await _saveCredentials(userRole);
      
      // Also save user name to SharedPreferences for other parts of the app
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', userName);
      await prefs.setString('user_email', email);
      await prefs.setString('user_uid', userCredential.user!.uid);

      // Update auth state through provider
      authNotifier.state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        userId: userCredential.user!.uid,
        userRole: userRole,
        email: email,
      );

      // Navigate to dashboard
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          userRole == 'client' ? AppRoutes.clientDashboard : AppRoutes.workerDashboard,
              (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        _showErrorMessage('Invalid email or password. Please try again.');
      } else if (e.code == 'user-disabled') {
        _showErrorMessage('Your account is not active or has been disabled by an admin.');
      } else {
        _showErrorMessage('An error occurred during login. Please try again.');
      }
      authNotifier.state = const AuthState(isLoading: false);
    } on Exception catch (e) {
      _showErrorMessage(e.toString());
      authNotifier.state = const AuthState(isLoading: false);
    }
  }

  Widget _buildLoginButton(AuthState authState, String userRole, WidgetRef ref) {
    return authState.isLoading
        ? const Center(child: CircularProgressIndicator(color: CColors.primary))
        : CButton(
      text: 'Login',
      onPressed: () => _handleLogin(userRole, ref),
      width: double.infinity,
    );
  }

  Widget _buildSignUpSection(BuildContext context, TextTheme textTheme, bool isDark, String userRole) {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Don't have an account? ",
            style: textTheme.bodyMedium?.copyWith(
              color: isDark ? CColors.lightGrey : CColors.darkGrey,
              fontSize: 12,
            ),
          ),
          TextButton(
            onPressed: () => _navigateToRoleBasedSignup(userRole),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(50, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Sign Up!',
              style: textTheme.bodyMedium?.copyWith(
                color: CColors.primary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToRoleBasedSignup(String userRole) {
    if (userRole == 'client') {
      Navigator.pushNamed(context, AppRoutes.clientSignUp);
    } else if (userRole == 'worker') {
      Navigator.pushNamed(context, AppRoutes.workerLogin);
    } else {
      _showErrorMessage('Please select a role first.');
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.role,
            (route) => false,
      );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: CColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
      ),
    );
  }
}
