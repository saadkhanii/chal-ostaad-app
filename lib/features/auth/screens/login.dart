import 'package:flutter/material.dart';
import 'package:chal_ostaad/core/constants/colors.dart';
import 'package:chal_ostaad/shared/logo/logo.dart';

import '../../../core/constants/sizes.dart';
import '../../../shared/widgets/Cbutton.dart';
import '../../../shared/widgets/Ccontainer.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CColors.light,
      body: Column(
        children: [
          CustomShapeContainer(
            height: CSizes.C_HeightL,
            padding: const EdgeInsets.only(top: 60),
            child: AppLogo(maxWidth: 220),
          ),
          const SizedBox(height: 20),
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: 30),
              CButton(
                text: "Login",
                onPressed: () {
                  // Perform login
                },
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  // Navigate to signup or forgot password
                },
                child: const Text("Don't have an account? Sign Up"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
