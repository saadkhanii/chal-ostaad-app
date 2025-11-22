// lib/features/client/widgets/client_dashboard_header.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/widgets/Ccontainer.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';

class ClientDashboardHeader extends StatefulWidget {
  const ClientDashboardHeader({super.key});

  @override
  State<ClientDashboardHeader> createState() => _ClientDashboardHeaderState();
}

class _ClientDashboardHeaderState extends State<ClientDashboardHeader> {
  String _userName = 'User';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    // We get the full name that we stored during the signup process.
    final fullName = prefs.getString('user_name');
    if (fullName != null && fullName.isNotEmpty) {
      if (mounted) {
        setState(() {
          // We split the full name by space and take only the first part.
          _userName = fullName.split(' ').first;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomShapeContainer(
      height: 180, // Sets the height of the curved header
      color: CColors.primary, // Sets the background color
      child: Padding(
        padding: const EdgeInsets.fromLTRB(CSizes.defaultSpace, 0, CSizes.defaultSpace, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Welcome Text on the left
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Back,',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: CColors.light),
                ),
                Text(
                  _userName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            // Profile Icon Button on the right
            InkWell(
              onTap: () {
                // This command finds the Scaffold in the widget tree and tells it to open its endDrawer.
                Scaffold.of(context).openEndDrawer();
              },
              borderRadius: BorderRadius.circular(30),
              child: const CircleAvatar(
                radius: 25,
                backgroundColor: CColors.white,
                child: Icon(
                  Icons.person,
                  color: CColors.primary,
                  size: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
