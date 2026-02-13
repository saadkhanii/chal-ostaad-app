// lib/features/auth/screens/login.dart

import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/role_provider.dart';
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
  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _credentialsLoaded = false;

  String? get _userRole {
    final args = ModalRoute.of(context)?.settings.arguments;
    return args as String?;
  }

  String _getRoleSpecificKey(String baseKey, String userRole) {
    return '${userRole}_$baseKey';
  }

  Future<void> _saveCredentials(String userRole) async {
    try {
      final prefs = await SharedPreferences.getInstance();

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
          SnackBar(
            content: Text('auth.credentials_cleared'.tr()),
            backgroundColor: CColors.success,
          ),
        );
      }
    } catch (e) {
      _showErrorMessage('errors.try_again'.tr());
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

  // Fixed translation method for login message
  String _getLoginMessage(String role) {
    final isUrdu = context.locale.languageCode == 'ur';
    final template = 'auth.login_as'.tr();

    if (isUrdu) {
      // For Urdu: replace {0} with role
      return template.replaceAll('{0}', role);
    } else {
      // For English: simple concatenation without parentheses
      return '$template $role.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final selectedRole = ref.watch(selectedRoleProvider);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_credentialsLoaded) {
            final userRole = _userRole ?? selectedRole;
            if (userRole != null && userRole.isNotEmpty) {
              _loadCredentialsForRole(userRole).then((_) {
                if (mounted) {
                  setState(() {
                    _credentialsLoaded = true;
                  });
                }
              });
            }
          }
        });

        final authState = ref.watch(authProvider);
        final rawRole = _userRole ?? selectedRole;
        final displayRole = rawRole == 'client' ? 'Client' : (rawRole == 'worker' ? 'Worker' : 'User');
        final userRole = rawRole ?? 'user';
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
                    title: 'auth.login'.tr(),
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
                          const SizedBox(height: CSizes.md),
                          Text(
                            'auth.welcome_back'.tr(),
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark ? CColors.white : CColors.textPrimary,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: CSizes.xs),

                          // Login message with role - FIXED
                          Text(
                            _getLoginMessage(displayRole),
                            style: textTheme.bodyMedium?.copyWith(
                              color: isDark ? CColors.lightGrey : CColors.darkGrey,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: CSizes.md),

                          CTextField(
                            label: 'auth.email'.tr(),
                            hintText: 'auth.email_hint'.tr(),
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
                            label: 'auth.password'.tr(),
                            hintText: 'auth.password_hint'.tr(),
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
                                      'auth.remember_me'.tr(),
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
                                    'auth.clear_saved'.tr(),
                                    style: textTheme.bodySmall?.copyWith(
                                      color: CColors.error,
                                      decoration: TextDecoration.underline,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(height: CSizes.sm),

                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _handleForgotPassword,
                              child: Text(
                                'auth.forgot_password'.tr(),
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

        if (savedEmail != null && savedEmail.isNotEmpty) {
          _emailController.text = savedEmail;
        }

        if (savedPassword != null && savedPassword.isNotEmpty) {
          _passwordController.text = savedPassword;
        }
      }
    } catch (e) {
      debugPrint('Error loading credentials: $e');
    }
  }

  Future<void> _handleLogin(String userRole, WidgetRef ref) async {
    if (!_formKey.currentState!.validate()) return;

    if (userRole.isEmpty || userRole == 'user') {
      _showErrorMessage('errors.role_required'.tr());
      return;
    }

    final authNotifier = ref.read(authProvider.notifier);
    ref.read(authProvider.notifier).state = const AuthState(isLoading: true);

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final collectionName = userRole == 'client' ? 'clients' : 'workers';

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .where('personalInfo.email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception('errors.email_not_registered'.tr(args: [userRole]));
      }

      final firebaseApp = Firebase.app(userRole);
      final auth = FirebaseAuth.instanceFor(app: firebaseApp);

      final userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final docData = querySnapshot.docs.first.data();
      if (docData['account']?['accountStatus'] != 'active') {
        await auth.signOut();
        throw FirebaseAuthException(
          code: 'user-disabled',
          message: 'errors.account_disabled'.tr(),
        );
      }

      final userName = _extractUserName(docData, email, userRole);

      await _saveCredentials(userRole);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', userName);
      await prefs.setString('user_email', email);
      await prefs.setString('user_uid', userCredential.user!.uid);

      authNotifier.state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        userId: userCredential.user!.uid,
        userRole: userRole,
        email: email,
      );

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          userRole == 'client' ? AppRoutes.clientDashboard : AppRoutes.workerDashboard,
              (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        _showErrorMessage('errors.invalid_credentials'.tr());
      } else if (e.code == 'user-disabled') {
        _showErrorMessage('errors.account_disabled'.tr());
      } else {
        _showErrorMessage('errors.login_failed'.tr());
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
      text: 'auth.login'.tr(),
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
            'auth.no_account'.tr(),
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
              'auth.sign_up_exclamation'.tr(),
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
      _showErrorMessage('errors.select_role_first'.tr());
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
    if (value == null || value.isEmpty) return 'auth.email_required'.tr();
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) return 'auth.email_invalid'.tr();
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'auth.password_required'.tr();
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