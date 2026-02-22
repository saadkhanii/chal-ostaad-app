// lib/features/client/my_posted_jobs_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/colors.dart';
import '../../core/models/job_model.dart';
import '../../core/routes/app_routes.dart';
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

  // Fetch current jobs then open map view
  Future<void> _openMapView() async {
    if (_clientId.isEmpty) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('jobs')
          .where('clientId', isEqualTo: _clientId)
          .get();

      final jobs = snapshot.docs
          .map((doc) =>
              JobModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      if (mounted) {
        Navigator.pushNamed(
          context,
          AppRoutes.jobsMap,
          arguments: {
            'jobs': jobs, // client view — no worker
          },
        );
      }
    } catch (e) {
      debugPrint('Error fetching jobs for map: $e');
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
            title: 'My Posted Jobs',
            showBackButton: false,
          ),
          Expanded(
            child: JobsListWidget(
              clientId: _clientId,
              scrollController: widget.scrollController,
              showFilters: true,
              showMapButton: true, // FAB from JobsListWidget handles map
            ),
          ),
        ],
      ),
      // ── Map FAB (bottom right, above list FAB) ─────────────────
      floatingActionButton: FloatingActionButton(
        heroTag: 'posted_jobs_map',
        onPressed: _openMapView,
        backgroundColor: CColors.primary,
        tooltip: 'View on Map',
        child: const Icon(Icons.map_rounded, color: Colors.white),
      ),
    );
  }
}
