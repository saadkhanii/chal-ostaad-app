// lib/shared/widgets/dashboard_drawer.dart

import 'package:chal_ostaad/core/providers/auth_provider.dart';
import 'package:chal_ostaad/core/providers/theme_provider.dart';
import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';

class DashboardDrawer extends ConsumerStatefulWidget {
  const DashboardDrawer({super.key});

  @override
  ConsumerState<DashboardDrawer> createState() => _DashboardDrawerState();
}

class _DashboardDrawerState extends ConsumerState<DashboardDrawer> {
  Map<String, String> _userInfo = {
    'name': 'Loading...',
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
            'name': prefs.getString('user_name') ?? 'User',
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

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final isDark = themeState.isDark;
    
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
      child: Column(
        children: [
          // Header Section
          _buildDrawerHeader(context, userName, userEmail, userRole),

          // Navigation Items
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildDrawerItems(context, userRole, isDark),
          ),

          // Footer Section
          _buildDrawerFooter(context, isDark),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader(
      BuildContext context,
      String userName,
      String userEmail,
      String userRole,
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
                userRole.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CColors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: CSizes.sm),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItems(BuildContext context, String userRole, bool isDark) {
    final bool isWorker = userRole == 'worker';
    final bool isClient = userRole == 'client';

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: CSizes.sm),
      children: [
        // Common Items for Both Roles
        _buildDrawerItem(
          context,
          icon: Icons.dashboard_outlined,
          title: 'Dashboard',
          isDark: isDark,
          onTap: () {
            Navigator.pop(context);
            // Already on dashboard
          },
          isSelected: true,
        ),

        _buildDrawerItem(
          context,
          icon: Icons.person_outline,
          title: 'Profile',
          isDark: isDark,
          onTap: () {
            Navigator.pop(context);
            _showComingSoon(context, 'Profile feature coming soon!');
          },
        ),

        _buildDrawerItem(
          context,
          icon: Icons.settings_outlined,
          title: 'Settings',
          isDark: isDark,
          onTap: () {
            Navigator.pop(context);
            _showComingSoon(context, 'Settings feature coming soon!');
          },
        ),

        _buildThemeSwitchItem(context, isDark),

        // Divider
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CSizes.defaultSpace,
            vertical: CSizes.sm,
          ),
          child: Divider(height: 1, color: isDark ? CColors.darkGrey : CColors.grey),
        ),

        // Role-Specific Items
        if (isWorker) ..._buildWorkerSpecificItems(context, isDark),
        if (isClient) ..._buildClientSpecificItems(context, isDark),

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
          title: 'Help & Support',
          isDark: isDark,
          onTap: () {
            Navigator.pop(context);
            _showComingSoon(context, 'Help & Support coming soon!');
          },
        ),

        _buildDrawerItem(
          context,
          icon: Icons.info_outline,
          title: 'About',
          isDark: isDark,
          onTap: () {
            Navigator.pop(context);
            _showComingSoon(context, 'About section coming soon!');
          },
        ),
      ],
    );
  }

  Widget _buildThemeSwitchItem(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.sm),
      child: ListTile(
        leading: Icon(
          isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          color: isDark ? CColors.white : CColors.darkGrey,
          size: 24,
        ),
        title: Text(
          isDark ? 'Light Mode' : 'Dark Mode',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isDark ? CColors.white : CColors.textPrimary,
            fontWeight: FontWeight.w400,
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
    );
  }

  List<Widget> _buildWorkerSpecificItems(BuildContext context, bool isDark) {
    return [
      _buildSectionLabel(context, 'WORKER TOOLS', isDark),
      _buildDrawerItem(
        context,
        icon: Icons.work_outline,
        title: 'My Bids',
        isDark: isDark,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'My Bids feature coming soon!');
        },
      ),
      _buildDrawerItem(
        context,
        icon: Icons.assignment_turned_in_outlined,
        title: 'Active Projects',
        isDark: isDark,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'Active Projects feature coming soon!');
        },
      ),
      _buildDrawerItem(
        context,
        icon: Icons.history_outlined,
        title: 'Bid History',
        isDark: isDark,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'Bid History feature coming soon!');
        },
      ),
      _buildDrawerItem(
        context,
        icon: Icons.analytics_outlined,
        title: 'Performance',
        isDark: isDark,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'Performance analytics coming soon!');
        },
      ),
    ];
  }

  List<Widget> _buildClientSpecificItems(BuildContext context, bool isDark) {
    return [
      _buildSectionLabel(context, 'CLIENT TOOLS', isDark),
      _buildDrawerItem(
        context,
        icon: Icons.add_circle_outline,
        title: 'Post New Job',
        isDark: isDark,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'Post Job feature coming soon!');
        },
      ),
      _buildDrawerItem(
        context,
        icon: Icons.list_alt_outlined,
        title: 'My Jobs',
        isDark: isDark,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'My Jobs feature coming soon!');
        },
      ),
      _buildDrawerItem(
        context,
        icon: Icons.gavel_outlined,
        title: 'Received Bids',
        isDark: isDark,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'Received Bids feature coming soon!');
        },
      ),
      _buildDrawerItem(
        context,
        icon: Icons.assignment_outlined,
        title: 'Active Contracts',
        isDark: isDark,
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'Active Contracts feature coming soon!');
        },
      ),
    ];
  }

  Widget _buildSectionLabel(BuildContext context, String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isDark ? CColors.lightGrey : CColors.darkGrey,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
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
        bool isSelected = false,
      }) {
    final Color itemColor = isSelected 
        ? CColors.primary 
        : (isDark ? CColors.white : CColors.textPrimary);
        
    final Color iconColor = isSelected 
        ? CColors.primary 
        : (isDark ? CColors.white : CColors.darkGrey);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.sm),
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

  Widget _buildDrawerFooter(BuildContext context, bool isDark) {
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
              onPressed: () => _showLogoutDialog(context, isDark),
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
                'Logout',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600, color: CColors.error),
              ),
            ),
          ),

          const SizedBox(height: CSizes.sm),

          // App Version
          Text(
            'Chal Ostaad v1.0.0',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: isDark ? CColors.lightGrey : CColors.darkGrey),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? CColors.dark : CColors.white,
        title: Text('Logout', style: TextStyle(color: isDark ? CColors.white : CColors.textPrimary)),
        content: Text('Are you sure you want to logout?', style: TextStyle(color: isDark ? CColors.lightGrey : CColors.textPrimary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: isDark ? CColors.white : CColors.primary)),
          ),
          TextButton(
            onPressed: () => _performLogout(context),
            style: TextButton.styleFrom(foregroundColor: CColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout(BuildContext context) async {
    Navigator.pop(context); // Close dialog

    try {
      // 1. Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('remember_me') ?? false;

      if (!rememberMe) {
        await prefs.clear();
      } else {
        await prefs.remove('user_uid');
        await prefs.remove('user_role');
      }
      
      await prefs.clear();

      // 3. Update Riverpod state
      ref.read(authProvider.notifier).logout();

      // 4. Navigate to Role Selection (CHANGED from Login)
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.role, // Changed to role selection
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Error during logout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: $e')),
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
