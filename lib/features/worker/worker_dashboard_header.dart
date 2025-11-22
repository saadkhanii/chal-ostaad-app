// lib/features/worker/widgets/worker_dashboard_header.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../shared/widgets/Ccontainer.dart';

class WorkerDashboardHeader extends StatefulWidget {
  const WorkerDashboardHeader({super.key});

  @override
  State<WorkerDashboardHeader> createState() => _WorkerDashboardHeaderState();
}

class _WorkerDashboardHeaderState extends State<WorkerDashboardHeader> {
  String _userName = 'Worker';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final fullName = prefs.getString('user_name');
    if (fullName != null && fullName.isNotEmpty) {
      if (mounted) {
        setState(() {
          _userName = fullName.split(' ').first;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomShapeContainer(
      height: 180,
      color: CColors.primary, // Using solid primary color, no gradient
      child: Padding(
        padding: const EdgeInsets.fromLTRB(CSizes.defaultSpace, 0, CSizes.defaultSpace, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Welcome Text
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Back,',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: CColors.white.withOpacity(0.8)),
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
            // Profile Icon
            InkWell(
              onTap: () => Scaffold.of(context).openEndDrawer(),
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
