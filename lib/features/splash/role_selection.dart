import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/colors.dart';
import '../../shared/widgets/Cbutton.dart';
import '../../core/providers/role_provider.dart';

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
        const SnackBar(
          content: Text('Failed to save role. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: CColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Illustration - Keep your original size
              SizedBox(
                height: 300,
                child: Image.asset(
                  "assets/images/welcome_image.png",
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 20),

              // Tagline - Only made text smaller as requested
              Text(
                "Your trusted partner for finding work and workers",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: CColors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 40),

              // Client Role - Original layout
              _roleSection(
                context,
                label: "Need help with work?",
                button: CButton(
                  text: "Find Worker",
                  onPressed: () {
                    _saveUserRoleAndNavigate('client', context, ref);
                  },
                  backgroundColor: CColors.secondary,
                  foregroundColor: CColors.white,
                ),
              ),
              const SizedBox(height: 20),

              // Worker Role - Original layout
              _roleSection(
                context,
                label: "Looking for work?",
                button: CButton(
                  text: "Find Work",
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