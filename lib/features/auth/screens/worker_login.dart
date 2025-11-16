import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../shared/logo/logo.dart';
import '../../../shared/widgets/Cbutton.dart';
import '../../../shared/widgets/Ccontainer.dart';
import '../../../shared/widgets/CtextField.dart';

class WorkerLoginScreen extends StatefulWidget {
  const WorkerLoginScreen({super.key});

  @override
  State<WorkerLoginScreen> createState() => _WorkerLoginScreenState();
}

class _WorkerLoginScreenState extends State<WorkerLoginScreen> {
  final TextEditingController _cnicController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // CNIC validation regex (Pakistani format: XXXXX-XXXXXXX-X)
  final RegExp _cnicRegex = RegExp(r'^\d{5}-\d{7}-\d{1}$');

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
        backgroundColor: isDark ? CColors.darkGrey : CColors.white,
        body: SingleChildScrollView(
          child: Column(
            children: [
              // Header Section with Custom Shape
              CustomShapeContainer(
                height: size.height * 0.25,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppLogo(
                      fontSize: 24,
                      minWidth: 300,
                      maxWidth: 400,
                    ),
                    const SizedBox(height: CSizes.md),
                    Text(
                      'Worker Portal',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: CColors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Login Form Section
              Padding(
                padding: const EdgeInsets.all(CSizes.lg),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const SizedBox(height: CSizes.xl),

                      // Title
                      Text(
                        'Worker Login',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? CColors.white : CColors.textPrimary,
                        ),
                      ),

                      const SizedBox(height: CSizes.sm),

                      Text(
                        'Enter your CNIC and phone number to login',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? CColors.lightGrey : CColors.darkGrey,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: CSizes.xl),

                      // CNIC Field
                      CTextField(
                        label: 'CNIC Number',
                        hintText: 'XXXXX-XXXXXXX-X',
                        controller: _cnicController,
                        keyboardType: TextInputType.text,
                        prefixIcon: Icon(
                          Icons.credit_card,
                          color: isDark ? CColors.white : CColors.textPrimary,
                        ),
                        isRequired: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your CNIC';
                          }
                          if (!_cnicRegex.hasMatch(value)) {
                            return 'Please enter valid CNIC format (XXXXX-XXXXXXX-X)';
                          }
                          return null;
                        },
                        onChanged: (value) {
                          // Auto-format CNIC as user types
                          if (value.length == 5 && !value.contains('-')) {
                            _cnicController.text = '$value-';
                            _cnicController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _cnicController.text.length),
                            );
                          } else if (value.length == 13 && value.endsWith('-')) {
                            _cnicController.text = '${value.substring(0, 12)}-';
                            _cnicController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _cnicController.text.length),
                            );
                          }
                        },
                      ),

                      const SizedBox(height: CSizes.lg),

                      // Phone Field
                      CTextField(
                        label: 'Phone Number',
                        hintText: '03XX-XXXXXXX',
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        prefixIcon: Icon(
                          Icons.phone,
                          color: isDark ? CColors.white : CColors.textPrimary,
                        ),
                        isRequired: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your phone number';
                          }
                          if (value.length < 11) {
                            return 'Please enter a valid phone number';
                          }
                          // Remove any non-digit characters and check
                          final cleanPhone = value.replaceAll(RegExp(r'[^\d]'), '');
                          if (cleanPhone.length != 11 || !cleanPhone.startsWith('03')) {
                            return 'Please enter a valid Pakistani phone number';
                          }
                          return null;
                        },
                        onChanged: (value) {
                          // Auto-format phone number
                          if (value.length == 4 && !value.contains('-')) {
                            _phoneController.text = '$value-';
                            _phoneController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _phoneController.text.length),
                            );
                          }
                        },
                      ),

                      const SizedBox(height: CSizes.xl),

                      // Login Button - FIXED: Handle null case properly
                      _isLoading
                          ? SizedBox(
                        width: double.infinity,
                        height: CSizes.buttonHeight,
                        child: ElevatedButton(
                          onPressed: null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CColors.primary.withOpacity(0.6),
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
                        text: 'LOGIN AS WORKER',
                        onPressed: _handleWorkerLogin,
                        width: double.infinity,
                      ),

                      const SizedBox(height: CSizes.lg),

                      // Help Text
                      TextButton(
                        onPressed: _handleForgotCredentials,
                        child: Text(
                          'Forgot your login details?',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: CColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          ),
        );
    }

  void _handleWorkerLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Clean the input data
        final cleanCnic = _cnicController.text.trim();
        final cleanPhone = _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');

        // Query Firestore for worker with matching CNIC and phone
        final workersRef = FirebaseFirestore.instance.collection('workers');
        final querySnapshot = await workersRef
            .where('personalInfo.cnic', isEqualTo: cleanCnic)
            .where('personalInfo.phone', isEqualTo: cleanPhone)
            .limit(1)
            .get();

        if (querySnapshot.docs.isEmpty) {
          throw Exception('No worker found with these credentials');
        }

        final workerDoc = querySnapshot.docs.first;
        final workerData = workerDoc.data();

        // Check verification status
        final verificationStatus = workerData['verification']?['status'] ?? 'pending';

        if (verificationStatus != 'verified') {
          throw Exception(
              'Your account is ${verificationStatus.toUpperCase()}. Please contact admin.');
        }

        // Success - Navigate to worker dashboard
        _showSuccessMessage('Login successful!');

        // TODO: Navigate to worker dashboard
        // Navigator.pushReplacement(
        //   context,
        //   MaterialPageRoute(builder: (context) => WorkerDashboard(workerId: workerDoc.id)),
        // );
      } catch (e) {
        _showErrorMessage('Login failed: ${e.toString()}');
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleForgotCredentials() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Forgot Login Details?',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).brightness == Brightness.dark
                ? CColors.white
                : CColors.textPrimary,
          ),
        ),
        content: Text(
          'Please contact your admin to recover your CNIC and phone number credentials.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          CButton(
            text: 'OK',
            onPressed: () => Navigator.pop(context),
            width: 100,
          ),
        ],
      ),
    );
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _cnicController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}