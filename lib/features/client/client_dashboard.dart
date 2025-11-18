import 'package:flutter/material.dart';
import 'package:chal_ostaad/core/constants/colors.dart';
import 'package:chal_ostaad/core/constants/sizes.dart';
import 'package:chal_ostaad/shared/logo/logo.dart';

class ClientDashboard extends StatelessWidget {
  const ClientDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: isDark ? CColors.darkGrey : CColors.white,
      appBar: AppBar(
        title: const Text('Client Dashboard'),
        backgroundColor: CColors.primary,
        foregroundColor: CColors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppLogo(
              fontSize: 32,
              minWidth: 200,
              maxWidth: 300,
            ),
            const SizedBox(height: CSizes.xl),
            Text(
              'Welcome to Client Dashboard!',
              style: textTheme.headlineSmall?.copyWith(
                color: isDark ? CColors.white : CColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: CSizes.md),
            Text(
              'You can now post jobs and hire workers',
              style: textTheme.bodyMedium?.copyWith(
                color: isDark ? CColors.lightGrey : CColors.darkGrey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: CSizes.xl),
            ElevatedButton(
              onPressed: () {
                // TODO: Navigate to job posting screen
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: CColors.primary,
                foregroundColor: CColors.white,
              ),
              child: const Text('Post a Job'),
            ),
          ],
        ),
      ),
    );
  }
}