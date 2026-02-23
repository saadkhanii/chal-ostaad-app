import 'package:chal_ostaad/core/providers/auth_provider.dart';
import 'package:chal_ostaad/core/providers/theme_provider.dart';
import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:chal_ostaad/features/client/client_dashboard.dart'
    show clientPageIndexProvider;
import 'package:chal_ostaad/features/worker/worker_dashboard.dart'
    show workerPageIndexProvider;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import 'language_switch.dart';

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
  String _photoBase64 = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid  = prefs.getString('user_uid') ?? '';
      final role = prefs.getString('user_role') ?? 'user';

      String photoBase64 = '';

      if (uid.isNotEmpty) {
        try {
          final collection = role == 'worker' ? 'workers' : 'clients';
          final doc = await FirebaseFirestore.instance
              .collection(collection)
              .doc(uid)
              .get();
          if (doc.exists) {
            final info = doc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
            photoBase64 = info['photoBase64'] ?? '';
          }
        } catch (e) {
          debugPrint('Error fetching photoBase64: $e');
        }
      }

      if (mounted) {
        setState(() {
          _userInfo = {
            'name': prefs.getString('user_name') ?? 'drawer.user'.tr(),
            'email': prefs.getString('user_email') ?? '',
            'role': role,
          };
          _photoBase64 = photoBase64;
          _isLoading   = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user info: $e');
      if (mounted) setState(() => _isLoading = false);
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
    final currentUser = FirebaseAuth.instance.currentUser;

    final userName = _userInfo['name']!;
    final userEmail = _userInfo['email']!;
    final userRole = _userInfo['role']!;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.8,
      backgroundColor: isDark ? CColors.dark : CColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(CSizes.cardRadiusLg),
        ),
      ),
      child: Directionality(
        textDirection: isUrdu ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: Column(
          children: [
            // Header Section
            _buildDrawerHeader(context, userName, userEmail, userRole, isUrdu, _photoBase64),

            // Navigation Items
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildDrawerItems(context, userRole, isDark, isUrdu, currentUser),
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
      String photoBase64,
      ) {
    final ImageProvider? avatarImage = photoBase64.isNotEmpty
        ? MemoryImage(base64Decode(photoBase64))
        : null;

    final String initials = userName.trim().isNotEmpty
        ? userName.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : '?';
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
                backgroundImage: avatarImage,
                child: avatarImage == null
                    ? Text(
                  initials,
                  style: TextStyle(
                    color: CColors.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                )
                    : null,
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

  Widget _buildDrawerItems(BuildContext context, String userRole, bool isDark, bool isUrdu, User? currentUser) {
    final bool isWorker = userRole == 'worker';
    final bool isClient = userRole == 'client';

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: CSizes.sm),
      children: [

        // Dashboard
        _buildDrawerItem(
          context,
          icon: Icons.dashboard_outlined,
          title: 'drawer.dashboard'.tr(),
          isDark: isDark,
          isUrdu: isUrdu,
          onTap: () {
            Navigator.pop(context);
            if (isWorker) {
              ref.read(workerPageIndexProvider.notifier).state = 2;
            } else if (isClient) {
              ref.read(clientPageIndexProvider.notifier).state = 2;
            }
          },
          isSelected: true,
        ),

        // Profile
        _buildDrawerItem(
          context,
          icon: Icons.person_outline,
          title: 'drawer.profile'.tr(),
          isDark: isDark,
          isUrdu: isUrdu,
          onTap: () {
            Navigator.pop(context);
            if (isWorker) {
              ref.read(workerPageIndexProvider.notifier).state = 4;
            } else if (isClient) {
              ref.read(clientPageIndexProvider.notifier).state = 4;
            }
          },
        ),

        // 🔔 Notifications with Badge
        if (currentUser != null)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .collection('notifications')
                .where('isRead', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.hasData ? snapshot.data!.docs.length : 0;

              return _buildDrawerItem(
                context,
                icon: Icons.notifications_outlined,
                title: 'notification.notifications'.tr(),
                isDark: isDark,
                isUrdu: isUrdu,
                badgeCount: unreadCount,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, AppRoutes.notifications);
                },
              );
            },
          ),

        // Notification Settings
        _buildDrawerItem(
          context,
          icon: Icons.settings_outlined,
          title: 'notification.notifications_settings'.tr(),
          isDark: isDark,
          isUrdu: isUrdu,
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.notificationSettings);
          },
        ),

        // Settings
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

        // Language Section
        _buildLanguageSection(context, isDark, isUrdu),

        // Theme Toggle
        _buildThemeToggle(context, isDark, isUrdu),

        // Divider
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CSizes.defaultSpace,
            vertical: CSizes.sm,
          ),
          child: Divider(height: 1, color: isDark ? CColors.darkGrey : CColors.grey),
        ),

        // Worker Specific Items
        if (isWorker) ..._buildWorkerSpecificItems(context, isDark, isUrdu),

        // Client Specific Items
        if (isClient) ..._buildClientSpecificItems(context, isDark, isUrdu),

        // Divider
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CSizes.defaultSpace,
            vertical: CSizes.sm,
          ),
          child: Divider(height: 1, color: isDark ? CColors.darkGrey : CColors.grey),
        ),

        // Help & Support
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

        // About
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

  Widget _buildDrawerItem(
      BuildContext context, {
        required IconData icon,
        required String title,
        required VoidCallback onTap,
        required bool isDark,
        required bool isUrdu,
        bool isSelected = false,
        int badgeCount = 0,
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
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
            if (badgeCount > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: CColors.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: itemColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: isUrdu ? 16 : 14,
                ),
              ),
            ),
            if (badgeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: CColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
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

  Widget _buildLanguageSection(BuildContext context, bool isDark, bool isUrdu) {
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
                child: LanguageSwitch(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeToggle(BuildContext context, bool isDark, bool isUrdu) {
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
            'settings.${isDark ? "light_mode" : "dark_mode"}'.tr(),
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
          ref.read(workerPageIndexProvider.notifier).state = 1;
        },
      ),

      _buildDrawerItem(
        context,
        icon: Icons.search_outlined,
        title: 'drawer.find_jobs'.tr(),
        isDark: isDark,
        isUrdu: isUrdu,
        onTap: () {
          Navigator.pop(context);
          ref.read(workerPageIndexProvider.notifier).state = 0;
        },
      ),

      _buildDrawerItem(
        context,
        icon: Icons.notifications_outlined,
        title: 'notification.notifications'.tr(),
        isDark: isDark,
        isUrdu: isUrdu,
        onTap: () {
          Navigator.pop(context);
          ref.read(workerPageIndexProvider.notifier).state = 3;
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
          ref.read(clientPageIndexProvider.notifier).state = 1;
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
          ref.read(clientPageIndexProvider.notifier).state = 0;
        },
      ),

      _buildDrawerItem(
        context,
        icon: Icons.notifications_outlined,
        title: 'notification.notifications'.tr(),
        isDark: isDark,
        isUrdu: isUrdu,
        onTap: () {
          Navigator.pop(context);
          ref.read(clientPageIndexProvider.notifier).state = 3;
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