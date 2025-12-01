import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/colors.dart';
import '../../shared/widgets/Cbutton.dart';

class RoleSelection extends StatelessWidget {
  const RoleSelection({super.key});

  // Temporary static variable to store role
  static String? tempUserRole;

  // Method to save user role and navigate to login
  Future<void> _saveUserRoleAndNavigate(String role, BuildContext context) async {
    try {
      print('💾 [DEBUG] Saving user role: $role');

      // Method 1: Try SharedPreferences first
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_role', role);
        final savedRole = prefs.getString('user_role');
        print('✅ [DEBUG] Role saved to SharedPreferences: $savedRole');
      } catch (e) {
        print('⚠️ [DEBUG] SharedPreferences failed, using temporary storage: $e');
      }

      // Method 2: Always use temporary storage as backup
      tempUserRole = role;
      print('✅ [DEBUG] Role saved to temporary storage: $tempUserRole');

      // Navigate to login page after saving role
      print('🚀 [DEBUG] Navigating to Login page with role: $role');
      Navigator.pushNamed(
          context,
          '/login',
          arguments: role // Pass the role as argument
      );

    } catch (e) {
      print('❌ [DEBUG] Error saving role: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CColors.primary,
      body: SafeArea(
        child: Padding(
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

              // Tagline
              Text(
                "Your trusted partner for\nfinding work and workers",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: CColors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 40),

              // Client Role
              _roleSection(
                context,
                label: "Need help with work?",
                button: CButton(
                  text: "Find Worker",
                  onPressed: () {
                    _saveUserRoleAndNavigate('client', context);
                  },
                  backgroundColor: CColors.secondary,
                  foregroundColor: CColors.white,
                ),
              ),
              const SizedBox(height: 20),

              // Worker Role
              _roleSection(
                context,
                label: "Looking for work?",
                button: CButton(
                  text: "Find Work",
                  onPressed: () {
                    _saveUserRoleAndNavigate('worker', context);
                  },
                  backgroundColor: CColors.secondary,
                  foregroundColor: CColors.white,
                ),
              ),
            ],
          ),
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
            )
        ),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: button),
      ],
    );
  }
}