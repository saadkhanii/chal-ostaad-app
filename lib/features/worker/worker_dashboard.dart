// lib/features/worker/worker_dashboard.dart

import 'package:chal_ostaad/features/worker/worker_dashboard_header.dart';
import 'package:flutter/material.dart';
import 'package:chal_ostaad/core/constants/colors.dart';
import 'package:chal_ostaad/core/constants/sizes.dart';

import '../client/dashboard_drawer.dart';


class WorkerDashboard extends StatelessWidget {
  const WorkerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // Reuse the same drawer for a consistent user experience
      endDrawer: const DashboardDrawer(),
      backgroundColor: isDark ? CColors.dark : CColors.light,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. The clean, solid-color header
            const WorkerDashboardHeader(),

            // 2. The main content area, styled like the client dashboard
            Padding(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A primary action card, similar to the client's "Post a Job"
                  _buildFindJobCard(context),
                  const SizedBox(height: CSizes.spaceBtwSections),

                  // Stats Section, replacing "Active Jobs"
                  Text('Your Stats', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildStatsRow(context),
                  const SizedBox(height: CSizes.spaceBtwSections),

                  // Job Feed Section, replacing "Browse Categories"
                  Text('Available Jobs', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: CSizes.spaceBtwItems),
                  _buildJobFeedPlaceholder(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET BUILDER HELPERS (No Gradients) ---

  Widget _buildFindJobCard(BuildContext context) {
    // This card mirrors the client's "Post a Job" card design
    return Container(
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        color: CColors.primary, // Solid primary color
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
                  'Ready to work?',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: CColors.white),
                ),
                Text(
                  'Browse the job feed to find your next project.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: CColors.light),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Navigate to the job feed screen
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.white,
              foregroundColor: CColors.primary,
            ),
            child: const Text('Find Jobs'),
          )
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            context,
            icon: Icons.account_balance_wallet_outlined,
            label: 'Earnings',
            value: 'Rs. 0',
          ),
        ),
        const SizedBox(width: CSizes.spaceBtwItems),
        Expanded(
          child: _buildStatCard(
            context,
            icon: Icons.check_circle_outline,
            label: 'Jobs Done',
            value: '0',
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, {required IconData icon, required String label, required String value}) {
    // This is styled like the category cards in the client dashboard
    return Container(
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        color: Theme.of(context).brightness == Brightness.dark ? CColors.darkContainer : CColors.lightContainer,
        border: Border.all(color: CColors.borderPrimary.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 30, color: CColors.primary), // Solid color icon
          const SizedBox(height: CSizes.sm),
          Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildJobFeedPlaceholder(BuildContext context) {
    // Simple placeholder for the job feed
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        color: Theme.of(context).brightness == Brightness.dark ? CColors.darkContainer : CColors.lightContainer,
      ),
      child: const Center(
        child: Column(
          children: [
            Icon(Icons.explore_off_outlined, size: 40, color: CColors.grey),
            SizedBox(height: CSizes.sm),
            Text('No new jobs available right now.', style: TextStyle(color: CColors.darkGrey)),
          ],
        ),
      ),
    );
  }
}
