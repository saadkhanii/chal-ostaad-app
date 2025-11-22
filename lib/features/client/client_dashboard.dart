// lib/features/client/client_dashboard.dart

import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import 'client_dashboard_header.dart';
import 'dashboard_drawer.dart';

class ClientDashboard extends StatelessWidget {
  const ClientDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // The endDrawer is the slide-out menu from the right. The key is managed by the Scaffold.
      endDrawer: const DashboardDrawer(),
      backgroundColor: isDark ? CColors.dark : CColors.light,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. The custom header you designed
            const ClientDashboardHeader(),

            // 2. The main content area of the dashboard
            Padding(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // "Post a Job" Card
                  _buildPostJobCard(context),
                  const SizedBox(height: CSizes.spaceBtwSections),

                  // "Active Jobs" Section
                  Text('Your Active Jobs', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildActiveJobsList(),
                  const SizedBox(height: CSizes.spaceBtwSections),

                  // "Browse Categories" Section
                  Text('Browse By Category', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildCategoryGrid(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET BUILDER HELPERS ---
  // These are the private helper methods to build parts of the UI.

  Widget _buildPostJobCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        color: CColors.primary,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need something done?',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: CColors.white),
                ),
                Text(
                  'Post a job and get offers from skilled workers.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: CColors.light),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Navigate to Post Job Screen
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.white,
              foregroundColor: CColors.primary,
            ),
            child: const Text('Post a Job'),
          )
        ],
      ),
    );
  }

  Widget _buildActiveJobsList() {
    // Placeholder for now. In the future, this will be a ListView.builder from Firestore data.
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: CColors.grey),
            SizedBox(height: CSizes.sm),
            Text('You have no active jobs.', style: TextStyle(color: CColors.darkGrey)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    final categories = {
      'Plumber': Icons.plumbing_outlined,
      'Electrician': Icons.electrical_services_outlined,
      'Painter': Icons.format_paint_outlined,
      'Carpenter': Icons.carpenter_outlined,
      'Mechanic': Icons.car_repair_outlined,
      'More': Icons.more_horiz_outlined,
    };

    return GridView.builder(
      itemCount: categories.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: CSizes.md,
        mainAxisSpacing: CSizes.md,
      ),
      itemBuilder: (context, index) {
        final title = categories.keys.elementAt(index);
        final icon = categories.values.elementAt(index);
        return InkWell(
          onTap: () {
            // TODO: Navigate to category screen
          },
          borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
              color: Theme.of(context).brightness == Brightness.dark
                  ? CColors.darkContainer
                  : CColors.lightContainer,
              border: Border.all(color: CColors.borderPrimary),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 36, color: CColors.primary),
                const SizedBox(height: CSizes.sm),
                Text(title, textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      },
    );
  }
}
