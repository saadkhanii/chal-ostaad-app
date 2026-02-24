import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../shared/widgets/Cbutton.dart';
import '../../core/providers/role_provider.dart';
import '../../core/services/localization_service.dart';
import '../../shared/widgets/language_switch.dart';

class RoleSelection extends ConsumerWidget {
  const RoleSelection({super.key});

  Future<void> _saveUserRoleAndNavigate(String role, BuildContext context, WidgetRef ref) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', role);

      ref.read(selectedRoleProvider.notifier).state = role;

      Navigator.pushNamed(
        context,
        '/login',
        arguments: role,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('errors.save_role_failed'.tr()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUrdu = LocalizationService.isUrdu(context);

    return Scaffold(
      backgroundColor: CColors.primary,
      body: SafeArea(
        child: Stack(
          children: [
            // Language Toggle Button - Positioned at top right
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: const LanguageSwitch(),
              ),
            ),

            // Main Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Illustration
                  SizedBox(
                    height: 300,
                    child: Image.asset(
                      "assets/images/welcome_image.png",
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tagline - Made bolder and bigger
                  Text(
                    'role.tagline'.tr(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: CColors.secondary,
                      fontWeight: FontWeight.w300, // Increased from w800 to w900
                      fontSize: isUrdu ? 28 : 22, // Increased from default to 26
                      height: 1.3,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Client Role
                  _roleSection(
                    context,
                    label: 'role.need_help'.tr(),
                    button: CButton(
                      text: 'role.find_worker'.tr(),
                      onPressed: () {
                        _saveUserRoleAndNavigate('client', context, ref);
                      },
                      backgroundColor: CColors.secondary,
                      foregroundColor: CColors.white,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Worker Role
                  _roleSection(
                    context,
                    label: 'role.looking_for_work'.tr(),
                    button: CButton(
                      text: 'role.find_work'.tr(),
                      onPressed: () {
                        _saveUserRoleAndNavigate('worker', context, ref);
                      },
                      backgroundColor: CColors.secondary,
                      foregroundColor: CColors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleSection(
      BuildContext context, {
        required String label,
        required Widget button,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: CColors.black,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: button),
      ],
    );
  }
}