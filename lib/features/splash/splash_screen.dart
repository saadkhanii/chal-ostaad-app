import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/routes/app_routes.dart';
import '../../shared/logo/logo.dart';

final splashScreenProvider = FutureProvider<void>((ref) async {
  await Future.delayed(const Duration(seconds: 2));
});

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<void>>(splashScreenProvider, (previous, next) {
      next.whenData((_) {
        // Ensure the widget is still mounted before navigating
        if (ModalRoute.of(context)?.isCurrent ?? false) {
          Navigator.pushReplacementNamed(context, AppRoutes.role);
        }
      });
    });

    return const Scaffold(
      backgroundColor: CColors.primary,
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 30.0),
          child: AppLogo(),
        ),
      ),
    );
  }
}
