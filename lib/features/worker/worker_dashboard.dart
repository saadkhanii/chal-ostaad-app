import 'package:flutter/material.dart';
import 'package:chal_ostaad/core/constants/colors.dart';
import 'package:chal_ostaad/core/constants/sizes.dart';
import 'package:chal_ostaad/shared/logo/logo.dart';

class WorkerDashboard extends StatelessWidget {
  const WorkerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: isDark ? CColors.darkGrey : CColors.white,
      appBar: AppBar(
        title: const Text('Worker Dashboard'),
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
              'Welcome to Worker Dashboard!',
              style: textTheme.headlineSmall?.copyWith(
                color: isDark ? CColors.white : CColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: CSizes.md),
            Text(
              'Browse available jobs and start working',
              style: textTheme.bodyMedium?.copyWith(
                color: isDark ? CColors.lightGrey : CColors.darkGrey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: CSizes.xl),
            ElevatedButton(
              onPressed: () {
                // TODO: Navigate to jobs browsing screen
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: CColors.primary,
                foregroundColor: CColors.white,
              ),
              child: const Text('Browse Jobs'),
            ),
          ],
        ),
      ),
    );
  }
}