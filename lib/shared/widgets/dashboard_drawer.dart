// lib/shared/widgets/dashboard_drawer.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';

class DashboardDrawer extends StatelessWidget {
  const DashboardDrawer({super.key});

  Future<Map<String, String>> _getUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name': prefs.getString('user_name') ?? 'User',
      'email': prefs.getString('user_email') ?? '',
      'role': prefs.getString('user_role') ?? 'user',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.8,
      backgroundColor: CColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(CSizes.cardRadiusLg),
        ),
      ),
      child: FutureBuilder<Map<String, String>>(
        future: _getUserInfo(),
        builder: (context, snapshot) {
          final userInfo = snapshot.data ?? {'name': 'User', 'email': '', 'role': 'user'};
          final userName = userInfo['name']!;
          final userEmail = userInfo['email']!;
          final userRole = userInfo['role']!;

          return Column(
            children: [
              // Header Section
              _buildDrawerHeader(context, userName, userEmail, userRole),

              // Navigation Items
              Expanded(
                child: _buildDrawerItems(context, userRole),
              ),

              // Footer Section
              _buildDrawerFooter(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDrawerHeader(BuildContext context, String userName, String userEmail, String userRole) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.defaultSpace),
      decoration: BoxDecoration(
        color: CColors.primary,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(CSizes.cardRadiusLg),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Circle
            CircleAvatar(
              radius: 30,
              backgroundColor: CColors.white,
              child: Icon(
                Icons.person,
                color: CColors.primary,
                size: 32,
              ),
            ),

            const SizedBox(height: CSizes.md),

            // User Name
            Text(
              userName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: CColors.white,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: CSizes.xs),

            // User Email
            Text(
              userEmail,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CColors.white.withOpacity(0.8),
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
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                userRole.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CColors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItems(BuildContext context, String userRole) {
    final bool isWorker = userRole == 'worker';
    final bool isClient = userRole == 'client';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: CSizes.md),

        // Common Items for Both Roles
        _buildDrawerItem(
          context,
          icon: Icons.dashboard_outlined,
          title: 'Dashboard',
          onTap: () {
            Navigator.pop(context);
            // Already on dashboard, just close drawer
          },
          isSelected: true,
        ),

        _buildDrawerItem(
          context,
          icon: Icons.person_outline,
          title: 'Profile',
          onTap: () {
            Navigator.pop(context);
            _showComingSoon(context, 'Profile feature coming soon!');
          },
        ),

        _buildDrawerItem(
          context,
          icon: Icons.settings_outlined,
          title: 'Settings',
          onTap: () {
            Navigator.pop(context);
            _showComingSoon(context, 'Settings feature coming soon!');
          },
        ),

        // Divider
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: CSizes.defaultSpace, vertical: CSizes.sm),
          child: Divider(height: 1),
        ),

        // Role-Specific Items
        if (isWorker) ..._buildWorkerSpecificItems(context),
        if (isClient) ..._buildClientSpecificItems(context),

        // Common Support Items
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: CSizes.defaultSpace, vertical: CSizes.sm),
          child: Divider(height: 1),
        ),

        _buildDrawerItem(
          context,
          icon: Icons.help_outline,
          title: 'Help & Support',
          onTap: () {
            Navigator.pop(context);
            _showComingSoon(context, 'Help & Support coming soon!');
          },
        ),

        _buildDrawerItem(
          context,
          icon: Icons.info_outline,
          title: 'About',
          onTap: () {
            Navigator.pop(context);
            _showComingSoon(context, 'About section coming soon!');
          },
        ),
      ],
    );
  }

  List<Widget> _buildWorkerSpecificItems(BuildContext context) {
    return [
      _buildDrawerItem(
        context,
        icon: Icons.work_outline,
        title: 'My Bids',
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'My Bids feature coming soon!');
        },
      ),

      _buildDrawerItem(
        context,
        icon: Icons.assignment_turned_in_outlined,
        title: 'Active Projects',
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'Active Projects feature coming soon!');
        },
      ),

      _buildDrawerItem(
        context,
        icon: Icons.history_outlined,
        title: 'Bid History',
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'Bid History feature coming soon!');
        },
      ),

      _buildDrawerItem(
        context,
        icon: Icons.analytics_outlined,
        title: 'Performance',
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'Performance analytics coming soon!');
        },
      ),
    ];
  }

  List<Widget> _buildClientSpecificItems(BuildContext context) {
    return [
      _buildDrawerItem(
        context,
        icon: Icons.add_circle_outline,
        title: 'Post New Job',
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'Post Job feature coming soon!');
        },
      ),

      _buildDrawerItem(
        context,
        icon: Icons.list_alt_outlined,
        title: 'My Jobs',
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'My Jobs feature coming soon!');
        },
      ),

      _buildDrawerItem(
        context,
        icon: Icons.gavel_outlined,
        title: 'Received Bids',
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'Received Bids feature coming soon!');
        },
      ),

      _buildDrawerItem(
        context,
        icon: Icons.assignment_outlined,
        title: 'Active Contracts',
        onTap: () {
          Navigator.pop(context);
          _showComingSoon(context, 'Active Contracts feature coming soon!');
        },
      ),
    ];
  }

  Widget _buildDrawerItem(
      BuildContext context, {
        required IconData icon,
        required String title,
        required VoidCallback onTap,
        bool isSelected = false,
      }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? CColors.primary : CColors.darkGrey,
        size: 24,
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: isSelected ? CColors.primary : CColors.textPrimary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: isSelected
          ? Icon(
        Icons.circle,
        color: CColors.primary,
        size: 8,
      )
          : null,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
      visualDensity: const VisualDensity(vertical: -2),
    );
  }

  Widget _buildDrawerFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CSizes.defaultSpace),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: CColors.borderPrimary),
        ),
      ),
      child: Column(
        children: [
          // Logout Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showLogoutDialog(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: CColors.error.withOpacity(0.1),
                foregroundColor: CColors.error,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                ),
                padding: const EdgeInsets.symmetric(horizontal: CSizes.md, vertical: CSizes.sm),
              ),
              icon: const Icon(Icons.logout, size: 20),
              label: Text(
                'Logout',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: CSizes.sm),

          // App Version
          Text(
            'Chal Ostaad v1.0.0',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: CColors.darkGrey,
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close drawer
              await _performLogout(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.error,
              foregroundColor: CColors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout(BuildContext context) async {
    try {
      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Sign out from Firebase (if using multiple apps)
      // await FirebaseAuth.instanceFor(app: Firebase.app('worker')).signOut();
      // await FirebaseAuth.instanceFor(app: Firebase.app('client')).signOut();

      // Navigate to login screen
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/role', // Adjust this route to your role selection screen
            (route) => false,
      );
    } catch (e) {
      debugPrint('Logout error: $e');
      // Still navigate to login even if logout fails
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/role',
            (route) => false,
      );
    }
  }

  void _showComingSoon(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        ),
      ),
    );
  }
}