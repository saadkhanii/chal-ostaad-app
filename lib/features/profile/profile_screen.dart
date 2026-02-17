// lib/features/profile/profile_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../shared/widgets/common_header.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const ProfileScreen({super.key, this.showAppBar = true});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final user = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title: 'profile.title'.tr(),
            showBackButton: true,
            onBackPressed: () => Navigator.pop(context),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Column(
                children: [
                  // Profile Avatar
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: CColors.primary,
                    child: Text(
                      user?.email?[0].toUpperCase() ?? 'U',
                      style: const TextStyle(fontSize: 40, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: CSizes.md),

                  // User Email
                  Text(
                    user?.email ?? '',
                    style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      fontSize: isUrdu ? 22 : 20,
                    ),
                  ),
                  const SizedBox(height: CSizes.spaceBtwSections),

                  // Profile Options
                  _buildProfileOption(
                    icon: Icons.person_outline,
                    title: 'profile.personal_info'.tr(),
                    onTap: () {},
                  ),
                  _buildProfileOption(
                    icon: Icons.settings_outlined,
                    title: 'profile.settings'.tr(),
                    onTap: () {},
                  ),
                  _buildProfileOption(
                    icon: Icons.language_outlined,
                    title: 'profile.language'.tr(),
                    onTap: () {},
                  ),
                  _buildProfileOption(
                    icon: Icons.logout_outlined,
                    title: 'profile.logout'.tr(),
                    onTap: () {
                      // Handle logout
                    },
                    color: CColors.error,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color color = CColors.textPrimary,
  }) {
    final isUrdu = context.locale.languageCode == 'ur';

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          fontSize: isUrdu ? 18 : 16,
          color: color,
        ),
      ),
      trailing: Icon(Icons.arrow_forward_ios, size: 16, color: color),
      onTap: onTap,
    );
  }
}