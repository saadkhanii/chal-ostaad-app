import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../shared/widgets/Cbutton.dart';

class RoleSelection extends StatelessWidget {
  const RoleSelection({super.key});

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
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 40),

              // Client Role
              _roleSection(
                context,
                label: "Need help with work?",
                button: CButton(
                  text: "Find Worker",
                  onPressed: () {
                    Navigator.pushNamed(context, '/login');
                  },
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
                    Navigator.pushNamed(context, '/worker-login');
                  },
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
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: button),
      ],
    );
  }
}
