// lib/shared/widgets/dashboard_drawer.dart

import 'package:chal_ostaad/core/providers/auth_provider.dart';
import 'package:chal_ostaad/core/providers/locale_provider.dart';
import 'package:chal_ostaad/core/providers/theme_provider.dart';
import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import 'language_switch.dart';  // ← Import the existing LanguageSwitch

class DashboardDrawer extends ConsumerStatefulWidget {
  const DashboardDrawer({super.key});

  @override
  ConsumerState<DashboardDrawer> createState() => _DashboardDrawerState();
}

class _DashboardDrawerState extends ConsumerState<DashboardDrawer> {
  Map<String, String> _userInfo = {
    'name': 'drawer.loading'.tr(),
    'email': '',
    'role': 'user',
  };
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _userInfo = {
            'name': prefs.getString('user_name') ?? 'drawer.user'.tr(),
            'email': prefs.getString('user_email') ?? '',
            'role': prefs.getString('user_role') ?? 'user',
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user info: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getRoleDisplay(String role) {
    switch (role) {
      case 'worker':
        return 'drawer.worker'.tr();
      case 'client':
        return 'drawer.client'.tr();
      default:
        return 'drawer.user'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final isDark = themeState.isDark;
    final isUrdu = context.locale.languageCode == 'ur';
    final currentLocale = ref.watch(localeProvider);

    final userName = _userInfo['name']!;
    final userEmail = _userInfo['email']!;
    final userRole = _userInfo['role']!;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.8,
      backgroundColor: isDark ? CColors.dark : CColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(CSizes.cardRadiusLg),  // Round left side
        ),
      ),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,  // Force RTL for drawer content
        child: Column(
          children: [
            // Header Section
            _buildDrawerHeader(context, userName, userEmail, userRole, isUrdu),

            // Navigation Items
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildDrawerItems(context, userRole, isDark, isUrdu),
            ),

            // Footer Section
            _buildDrawerFooter(context, isDark, isUrdu),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerHeader(
      BuildContext context,
      String userName,
      String userEmail,
      String userRole,
      bool isUrdu,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.defaultSpace),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CColors.primary, CColors.secondary],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(CSizes.cardRadiusLg),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Circle
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: CColors.white, width: 2),
              ),
              child: CircleAvatar(
                radius: 30,
                backgroundColor: CColors.white,
                child: Icon(Icons.person, color: CColors.primary, size: 32),
              ),
            ),

            const SizedBox(height: CSizes.md),

            // User Name
            Text(
              userName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: CColors.white,
                fontWeight: FontWeight.bold,
                fontSize: isUrdu ? 20 : 18,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: CSizes.xs),

            // User Email
            Text(
              userEmail,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CColors.white.withOpacity(0.9),
                fontSize: isUrdu ? 14 : 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: CSizes.sm),

            // Role Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: CColors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CColors.white.withOpacity(0.3)),
              ),
              child: Text(
                _getRoleDisplay(userRole).toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CColors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  fontSize: isUrdu ? 12 : 10,
                ),
              ),
            ),
            const SizedBox(height: CSizes.sm),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItems(BuildContext context, String userRole, bool isDark, bool isUrdu) {
    final bool isWorker = userRole == 'worker';
    final bool isClient = userRole == 'client';

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: CSizes.sm),
      children: [

        _buildDrawerItem(
          context,
          icon: Icons.dashboard_outlined,
          title: 'drawer.dashboard'.tr(),
          isDark: isDark,
          isUrdu: isUrdu,
          onTap: () {
            Navigator.pop(context);

          },
          isSelected: true,
        ),

        _buildDrawerItem(
          context,
          icon: Icons.person_outline,
          title: 'drawer.profile'.tr(),
          isDark: isDark,
          isUrdu: isUrdu,
          onTap: () {
            Navigator.pop(context);
            _showComingSoon(context, 'drawer.coming_soon_profile'.tr());
          },
        ),

        _buildDrawerItem(
          context,
          icon: Icons.settings_outlined,
          title: 'drawer.settings'.tr(),
          isDark: isDark,
          isUrdu: isUrdu,
          onTap: () {
            Navigator.pop(context);
            _showComingSoon(context, 'drawer.coming_soon_settings'.tr());
          },
        ),

        // Language Switch Item
        _buildLanguageSwitchItem(context, isDark, isUrdu),

        // Theme Switch Item
        _buildThemeSwitchItem(context, isDark, isUrdu),

        // Divider
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CSizes.defaultSpace,
            vertical: CSizes.sm,
          ),
          child: Divider(height: 1, color: isDark ? CColors.darkGrey : CColors.grey),
        ),

        // Role-Specific Items
        if (isWorker) ..._buildWorkerSpecificItems(context, isDark, isUrdu),
        if (isClient) ..._buildClientSpecificItems(context, isDark, isUrdu),

        // Common Support Items
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CSizes.defaultSpace,
            vertical: CSizes.sm,
          ),
          child: Divider(height: 1, color: isDark ? CColors.darkGrey : CColors.grey),
        ),

        _buildDrawerItem(
          context,
          icon: Icons.help_outline,
          title: 'drawer.help_support'.tr(),
          isDark: isDark,
          isUrdu: isUrdu,
          onTap: () {
            Navigator.pop(context);
            _showComingSoon(context, 'drawer.coming_soon_help'.tr());
          },
        ),

        _buildDrawerItem(
          context,
          icon: Icons.info_outline,
          title: 'drawer.about'.tr(),
          isDark: isDark,
          isUrdu: isUrdu,
          onTap: () {
            Navigator.pop(context);
            _showComingSoon(context, 'drawer.coming_soon_about'.tr());
          },
        ),
      ],
    );
  }

  Widget _buildLanguageSwitchItem(BuildContext context, bool isDark, bool isUrdu) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.sm, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? CColors.darkContainer : CColors.softGrey,
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'drawer.language'.tr(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isDark ? CColors.lightGrey : CColors.darkGrey,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontSize: isUrdu ? 12 : 10,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: LanguageSwitch(),  // ← Using the existing widget
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeSwitchItem(BuildContext context, bool isDark, bool isUrdu) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.sm, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? CColors.darkContainer : CColors.softGrey,
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        ),
        child: ListTile(
          leading: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            color: isDark ? CColors.white : CColors.darkGrey,
            size: 24,
          ),
          title: Text(
            isDark ? 'drawer.light_mode'.tr() : 'drawer.dark_mode'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark ? CColors.white : CColors.textPrimary,
              fontWeight: FontWeight.w400,
              fontSize: isUrdu ? 16 : 14,
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
          ),
          onTap: () {
            ref.read(themeProvider.notifier).toggleTheme();
          },
          contentPadding: const EdgeInsets.symmetric(horizontal: CSizes.md),
          visualDensity: const VisualDensity(vertical: -1),
          trailing: Switch(
            value: isDark,
            onChanged: (val) {
              ref.read(themeProvider.notifier).toggleTheme();
            },
            activeColor: CColors.primary,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildWorkerSpecificItems(BuildContext context, bool isDark, bool isUrdu) {
    return [
      _buildSectionLabel(context, 'drawer.worker_tools'.tr(), isDark, isUrdu),
      _buildDrawerItem(
        context,
        icon: Icons.work_outline,
        title: 'drawer.my_bids'.tr(),
        isDark: isDark,
        isUrdu: isUrdu,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'drawer.coming_soon_bids'.tr());
        },
      ),
      _buildDrawerItem(
        context,
        icon: Icons.assignment_turned_in_outlined,
        title: 'drawer.active_projects'.tr(),
        isDark: isDark,
        isUrdu: isUrdu,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'drawer.coming_soon_projects'.tr());
        },
      ),
      _buildDrawerItem(
        context,
        icon: Icons.history_outlined,
        title: 'drawer.bid_history'.tr(),
        isDark: isDark,
        isUrdu: isUrdu,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'drawer.coming_soon_history'.tr());
        },
      ),
      _buildDrawerItem(
        context,
        icon: Icons.analytics_outlined,
        title: 'drawer.performance'.tr(),
        isDark: isDark,
        isUrdu: isUrdu,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'drawer.coming_soon_performance'.tr());
        },
      ),
    ];
  }

  List<Widget> _buildClientSpecificItems(BuildContext context, bool isDark, bool isUrdu) {
    return [
      _buildSectionLabel(context, 'drawer.client_tools'.tr(), isDark, isUrdu),
      _buildDrawerItem(
        context,
        icon: Icons.add_circle_outline,
        title: 'drawer.post_new_job'.tr(),
        isDark: isDark,
        isUrdu: isUrdu,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'drawer.coming_soon_post_job'.tr());
        },
      ),
      _buildDrawerItem(
        context,
        icon: Icons.list_alt_outlined,
        title: 'drawer.my_jobs'.tr(),
        isDark: isDark,
        isUrdu: isUrdu,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'drawer.coming_soon_my_jobs'.tr());
        },
      ),
      _buildDrawerItem(
        context,
        icon: Icons.gavel_outlined,
        title: 'drawer.received_bids'.tr(),
        isDark: isDark,
        isUrdu: isUrdu,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'drawer.coming_soon_received_bids'.tr());
        },
      ),
      _buildDrawerItem(
        context,
        icon: Icons.assignment_outlined,
        title: 'drawer.active_contracts'.tr(),
        isDark: isDark,
        isUrdu: isUrdu,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'drawer.coming_soon_contracts'.tr());
        },
      ),
    ];
  }

  Widget _buildSectionLabel(BuildContext context, String label, bool isDark, bool isUrdu) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isDark ? CColors.lightGrey : CColors.darkGrey,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          fontSize: isUrdu ? 14 : 12,
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
      BuildContext context, {
        required IconData icon,
        required String title,
        required VoidCallback onTap,
        required bool isDark,
        required bool isUrdu,
        bool isSelected = false,
      }) {
    final Color itemColor = isSelected
        ? CColors.primary
        : (isDark ? CColors.white : CColors.textPrimary);

    final Color iconColor = isSelected
        ? CColors.primary
        : (isDark ? CColors.white : CColors.darkGrey);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.sm, vertical: 2),
      child: ListTile(
        leading: Icon(
          icon,
          color: iconColor,
          size: 24,
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: itemColor,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            fontSize: isUrdu ? 16 : 14,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        ),
        selected: isSelected,
        selectedTileColor: CColors.primary.withOpacity(0.1),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: CSizes.md),
        visualDensity: const VisualDensity(vertical: -1),
      ),
    );
  }

  Widget _buildDrawerFooter(BuildContext context, bool isDark, bool isUrdu) {
    return Container(
      padding: const EdgeInsets.all(CSizes.defaultSpace),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: isDark ? CColors.darkGrey : CColors.borderPrimary)),
      ),
      child: Column(
        children: [
          // Logout Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showLogoutDialog(context, isDark, isUrdu),
              style: ElevatedButton.styleFrom(
                backgroundColor: CColors.error.withOpacity(0.1),
                foregroundColor: CColors.error,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: CSizes.md,
                  vertical: CSizes.sm,
                ),
              ),
              icon: const Icon(Icons.logout, size: 20),
              label: Text(
                'drawer.logout'.tr(),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: CColors.error,
                  fontSize: isUrdu ? 16 : 14,
                ),
              ),
            ),
          ),

          const SizedBox(height: CSizes.sm),

          // App Version
          Text(
            'drawer.app_version'.tr(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(
              color: isDark ? CColors.lightGrey : CColors.darkGrey,
              fontSize: isUrdu ? 12 : 10,
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, bool isDark, bool isUrdu) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? CColors.dark : CColors.white,
        title: Text(
          'drawer.logout'.tr(),
          style: TextStyle(
            color: isDark ? CColors.white : CColors.textPrimary,
            fontSize: isUrdu ? 20 : 18,
          ),
        ),
        content: Text(
          'drawer.confirm_logout'.tr(),
          style: TextStyle(
            color: isDark ? CColors.lightGrey : CColors.textPrimary,
            fontSize: isUrdu ? 16 : 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'drawer.cancel'.tr(),
              style: TextStyle(
                color: isDark ? CColors.white : CColors.primary,
                fontSize: isUrdu ? 16 : 14,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _performLogout(context),
            style: TextButton.styleFrom(foregroundColor: CColors.error),
            child: Text(
              'drawer.logout'.tr(),
              style: TextStyle(fontSize: isUrdu ? 16 : 14),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout(BuildContext context) async {
    Navigator.pop(context); // Close dialog

    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('remember_me') ?? false;

      if (!rememberMe) {
        await prefs.clear();
      } else {
        await prefs.remove('user_uid');
        await prefs.remove('user_role');
        await prefs.remove('user_name');
        await prefs.remove('user_email');
      }

      ref.read(authProvider.notifier).logout();

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.role,
              (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Error during logout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('drawer.logout_failed'.tr())),
        );
      }
    }
  }

  void _showComingSoon(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}