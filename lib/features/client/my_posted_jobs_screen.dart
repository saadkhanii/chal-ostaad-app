// lib/features/client/my_posted_jobs_screen.dart (NEW FILE)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/colors.dart';
import '../../shared/widgets/common_header.dart';
import 'jobs_list_widget.dart';

class MyPostedJobsScreen extends ConsumerStatefulWidget {
  final ScrollController? scrollController;

  const MyPostedJobsScreen({
    super.key,
    this.scrollController,
  });

  @override
  ConsumerState<MyPostedJobsScreen> createState() => _MyPostedJobsScreenState();
}

class _MyPostedJobsScreenState extends ConsumerState<MyPostedJobsScreen> {
  String _clientId = '';

  @override
  void initState() {
    super.initState();
    _loadClientId();
  }

  Future<void> _loadClientId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _clientId = prefs.getString('user_uid') ?? '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          const CommonHeader(
            title: 'My Posted Jobs', // Add translation key
            showBackButton: false, // No back button in bottom nav
          ),
          Expanded(
            child: JobsListWidget(
              clientId: _clientId,
              scrollController: widget.scrollController,
              showFilters: true,
              // Uses default navigation to job details
            ),
          ),
        ],
      ),
    );
  }
}