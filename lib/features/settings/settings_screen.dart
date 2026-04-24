// lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/routes/app_routes.dart';
import '../../shared/widgets/common_header.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title: 'drawer.settings'.tr(),
            showBackButton: true,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              children: [

                // ── ACCOUNT ────────────────────────────────────────
                _sectionLabel('ACCOUNT', isDark, isUrdu, context),

                _settingsTile(
                  context,
                  icon:     Icons.photo_camera_outlined,
                  title:    'Change Profile Picture',
                  subtitle: 'Update your display photo',
                  isDark:   isDark,
                  onTap:    () => _comingSoon(context, 'Profile picture update coming soon.'),
                ),

                _settingsTile(
                  context,
                  icon:     Icons.lock_outline_rounded,
                  title:    'Change Password',
                  subtitle: 'Update your account password',
                  isDark:   isDark,
                  onTap:    () => _comingSoon(context, 'Change password coming soon.'),
                ),

                _settingsTile(
                  context,
                  icon:     Icons.person_outline_rounded,
                  title:    'Edit Profile',
                  subtitle: 'Update your name and personal info',
                  isDark:   isDark,
                  onTap:    () => Navigator.pop(context), // goes back to profile
                ),

                const SizedBox(height: CSizes.spaceBtwItems),

                // ── NOTIFICATIONS ──────────────────────────────────
                _sectionLabel('NOTIFICATIONS', isDark, isUrdu, context),

                _settingsTile(
                  context,
                  icon:     Icons.notifications_active_outlined,
                  title:    'Notification Settings',
                  subtitle: 'Manage push notification preferences',
                  isDark:   isDark,
                  onTap:    () => Navigator.pushNamed(
                      context, AppRoutes.notificationSettings),
                ),

                const SizedBox(height: CSizes.spaceBtwItems),

                // ── PRIVACY ────────────────────────────────────────
                _sectionLabel('PRIVACY', isDark, isUrdu, context),

                _settingsTile(
                  context,
                  icon:     Icons.privacy_tip_outlined,
                  title:    'Privacy Settings',
                  subtitle: 'Control who sees your information',
                  isDark:   isDark,
                  onTap:    () => _comingSoon(context, 'Privacy settings coming soon.'),
                ),

                _settingsTile(
                  context,
                  icon:     Icons.block_outlined,
                  title:    'Blocked Users',
                  subtitle: 'Manage your blocked list',
                  isDark:   isDark,
                  onTap:    () => _comingSoon(context, 'Blocked users coming soon.'),
                ),

                const SizedBox(height: CSizes.spaceBtwItems),

                // ── DANGER ZONE ────────────────────────────────────
                _sectionLabel('DANGER ZONE', isDark, isUrdu, context),

                _settingsTile(
                  context,
                  icon:          Icons.delete_outline_rounded,
                  title:         'Delete Account',
                  subtitle:      'Permanently remove your account and data',
                  isDark:        isDark,
                  isDestructive: true,
                  onTap:         () => _showDeleteConfirm(context, isDark, isUrdu),
                ),

                const SizedBox(height: CSizes.spaceBtwSections),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, bool isDark, bool isUrdu, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize:      isUrdu ? 14 : 11,
          fontWeight:    FontWeight.bold,
          letterSpacing: 1.2,
          color:         isDark ? CColors.lightGrey : CColors.darkGrey,
        ),
      ),
    );
  }

  Widget _settingsTile(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required bool isDark,
        required VoidCallback onTap,
        bool isDestructive = false,
      }) {
    final color = isDestructive ? CColors.error : CColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
        leading: Container(
          padding:    const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:        color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title,
            style: TextStyle(
              fontSize:   14,
              fontWeight: FontWeight.w600,
              color:      isDestructive
                  ? CColors.error
                  : (isDark ? CColors.white : CColors.textPrimary),
            )),
        subtitle: Text(subtitle,
            style: TextStyle(
              fontSize: 12,
              color:    isDark ? CColors.lightGrey : CColors.darkGrey,
            )),
        trailing: Icon(Icons.chevron_right_rounded,
            color: isDark ? CColors.darkGrey : CColors.lightGrey, size: 20),
        onTap: onTap,
      ),
    );
  }

  void _comingSoon(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:  Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showDeleteConfirm(BuildContext context, bool isDark, bool isUrdu) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? CColors.dark : CColors.white,
        title: const Text('Delete Account',
            style: TextStyle(color: CColors.error)),
        content: const Text(
          'This action is permanent and cannot be undone. '
              'All your data, jobs, and bids will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _comingSoon(context, 'Account deletion coming soon.');
            },
            style: TextButton.styleFrom(foregroundColor: CColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}