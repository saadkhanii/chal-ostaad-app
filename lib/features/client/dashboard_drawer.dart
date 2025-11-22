// lib/features/client/widgets/dashboard_drawer.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/routes/app_routes.dart';

class DashboardDrawer extends StatefulWidget {
  const DashboardDrawer({super.key});

  @override
  State<DashboardDrawer> createState() => _DashboardDrawerState();
}

class _DashboardDrawerState extends State<DashboardDrawer> {
  String _userName = 'User';
  String _userEmail = 'user@example.com';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    // Fetch stored user data. You might want to get this from Firestore in the future.
    setState(() {
      _userName = prefs.getString('user_name') ?? 'Client';
      _userEmail = prefs.getString('user_email') ?? 'no-email@found.com';
    });
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    // Clear all session data
    await prefs.remove('user_uid');
    await prefs.remove('user_role');
    await prefs.remove('user_email');
    await prefs.remove('user_name');

    if (mounted) {
      // Navigate to the login screen and remove all previous routes
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Drawer(
      backgroundColor: isDark ? CColors.darkerGrey : CColors.light,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Drawer Header
          DrawerHeader(
            decoration: const BoxDecoration(
              color: CColors.primary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: CColors.white,
                  child: Icon(Icons.person, size: 35, color: CColors.primary),
                ),
                const SizedBox(height: CSizes.sm),
                Text(
                  _userName,
                  style: textTheme.titleMedium?.copyWith(color: CColors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  _userEmail,
                  style: textTheme.bodySmall?.copyWith(color: CColors.lightGrey),
                ),
              ],
            ),
          ),
          // Menu List Tiles
          _buildDrawerItem(icon: Icons.person_outline, text: 'My Profile', onTap: () {}),
          _buildDrawerItem(icon: Icons.history, text: 'Job History', onTap: () {}),
          _buildDrawerItem(icon: Icons.payment_outlined, text: 'Payment Methods', onTap: () {}),
          _buildDrawerItem(icon: Icons.settings_outlined, text: 'Settings', onTap: () {}),
          const Divider(color: CColors.grey, indent: 16, endIndent: 16),
          // Logout Button
          _buildDrawerItem(
            icon: Icons.logout,
            text: 'Logout',
            onTap: _handleLogout,
            color: CColors.error,
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({required IconData icon, required String text, required VoidCallback onTap, Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? (Theme.of(context).brightness == Brightness.dark ? CColors.light : CColors.dark)),
      title: Text(text, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }
}
