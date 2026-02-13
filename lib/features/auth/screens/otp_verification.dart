import 'package:chal_ostaad/core/providers/auth_provider.dart';
import 'package:chal_ostaad/features/auth/screens/set_password.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../shared/widgets/common_header.dart';
import '../../../shared/widgets/Cbutton.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String email;

  const OTPVerificationScreen({
    super.key,
    required this.email,
  });

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final List<TextEditingController> _otpControllers =
  List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
  List.generate(6, (_) => FocusNode());

  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();

    for (int i = 0; i < _otpControllers.length - 1; i++) {
      _otpControllers[i].addListener(() {
        if (_otpControllers[i].text.length == 1) {
          _focusNodes[i + 1].requestFocus();
        }
      });
    }
  }

  Future<void> _handleVerify(WidgetRef ref) async {
    if (!_isOTPComplete()) return;

    ref.read(authProvider.notifier).state =
    const AuthState(isLoading: true);

    final otp = _getOTP();
    _logger.i('Verifying OTP: $otp');

    try {
      final prefs = await SharedPreferences.getInstance();
      final userRole = prefs.getString('user_role') ?? 'client';
      final collectionName =
      userRole == 'client' ? 'clients' : 'workers';

      final querySnapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .where('personalInfo.email', isEqualTo: widget.email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception('errors.user_not_found'.tr());
      }

      final userData = querySnapshot.docs.first.data();
      final String storedOtp = userData['verification']['otp'];
      final Timestamp storedExpiry =
      userData['verification']['otpExpiry'];

      if (DateTime.now().isAfter(storedExpiry.toDate())) {
        throw Exception('errors.otp_expired'.tr());
      }

      if (otp != storedOtp) {
        throw Exception('errors.otp_invalid'.tr());
      }

      _showSuccessMessage('auth.verification_successful'.tr());

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                SetPasswordScreen(email: widget.email),
          ),
        );
      }
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      _logger.e(message);
      _showErrorMessage(message);
    } finally {
      if (mounted) {
        ref.read(authProvider.notifier).state =
        const AuthState(isLoading: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final authState = ref.watch(authProvider);
        final isDark =
            Theme.of(context).brightness == Brightness.dark;
        final textTheme = Theme.of(context).textTheme;

        return Scaffold(
          backgroundColor:
          isDark ? CColors.dark : CColors.white,
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                CommonHeader(
                  title: 'auth.otp_verification'.tr(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CSizes.xl,
                    CSizes.sm,
                    CSizes.xl,
                    CSizes.xl,
                  ),
                  child: Column(
                    children: [
                      Text(
                        'auth.email_verification'.tr(),
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: CSizes.xs),
                      Text(
                        'auth.enter_otp'
                            .tr(args: [widget.email]),
                        style: textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          color: isDark
                              ? CColors.lightGrey
                              : CColors.darkGrey,
                        ),
                      ),
                      const SizedBox(height: CSizes.xl),
                      _buildOTPInputFields(isDark, textTheme),
                      const SizedBox(height: CSizes.xl),
                      _buildVerifyButton(authState, ref),
                      const SizedBox(height: CSizes.md),
                      _buildResendRow(textTheme, isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOTPInputFields(
      bool isDark, TextTheme textTheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            width: 50,
            height: 50,
            child: TextFormField(
              controller: _otpControllers[index],
              focusNode: _focusNodes[index],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark
                    ? CColors.white
                    : CColors.textPrimary,
              ),
              decoration: InputDecoration(
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(CSizes.borderRadiusMd),
                ),
              ),
              onChanged: (value) {
                if (value.length == 1 && index < 5) {
                  _focusNodes[index + 1].requestFocus();
                } else if (value.isEmpty && index > 0) {
                  _focusNodes[index - 1].requestFocus();
                }
              },
            ),
          ),
        );
      }),
    );
  }

  Widget _buildVerifyButton(
      AuthState authState, WidgetRef ref) {
    return CButton(
      text: 'auth.verify_and_proceed'.tr(),
      isLoading: authState.isLoading,
      width: double.infinity,
      onPressed: () => _handleVerify(ref),
    );
  }

  Widget _buildResendRow(
      TextTheme textTheme, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'auth.no_code_received'.tr(),
          style: textTheme.bodyMedium?.copyWith(
            fontSize: 12,
            color:
            isDark ? CColors.lightGrey : CColors.darkGrey,
          ),
        ),
        TextButton(
          onPressed: () {},
          child: Text(
            'auth.resend'.tr(),
            style: textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              color: CColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  bool _isOTPComplete() =>
      _otpControllers.every((c) => c.text.length == 1);

  String _getOTP() =>
      _otpControllers.map((c) => c.text).join();

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CColors.success,
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CColors.error,
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }
}
