// lib/features/jobs/job_details_router_screen.dart
//
// A thin wrapper used by notification taps and any named route that only has
// a jobId string.  It fetches the JobModel from Firestore, reads the user's
// role from SharedPreferences, then pushes the correct detail screen.
//
// Register in your router:
//   AppRoutes.jobDetails: (ctx) {
//     final jobId = ModalRoute.of(ctx)!.settings.arguments as String;
//     return JobDetailsRouterScreen(jobId: jobId);
//   },

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../core/constants/colors.dart';
import '../../core/models/job_model.dart';
import '../../features/client/client_job_details_screen.dart';
import '../../features/worker/worker_job_details_screen.dart';

class JobDetailsRouterScreen extends StatefulWidget {
  final String jobId;

  const JobDetailsRouterScreen({super.key, required this.jobId});

  @override
  State<JobDetailsRouterScreen> createState() => _JobDetailsRouterScreenState();
}

class _JobDetailsRouterScreenState extends State<JobDetailsRouterScreen> {
  // State
  bool    _loading = true;
  String? _error;

  // Loaded values
  JobModel? _job;
  String    _role           = 'client';
  String    _workerId       = '';
  String    _workerCategory = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });

    try {
      // 1. Read role + worker info from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _role           = prefs.getString('user_role')     ?? 'client';
      _workerId       = prefs.getString('user_uid')      ?? '';
      _workerCategory = prefs.getString('user_category') ?? '';

      // 2. Fetch the job document from Firestore
      final doc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .get();

      if (!doc.exists) {
        setState(() {
          _error   = 'notification.job_not_found'.tr();
          _loading = false;
        });
        return;
      }

      _job = JobModel.fromSnapshot(doc);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error   = '${'common.error'.tr()}: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Loading ──────────────────────────────────────────────────
    if (_loading) {
      return Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? CColors.dark
            : CColors.lightGrey,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // ── Error ────────────────────────────────────────────────────
    if (_error != null || _job == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? CColors.dark
            : CColors.lightGrey,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: CColors.error),
              const SizedBox(height: 16),
              Text(
                _error ?? 'notification.job_not_found'.tr(),
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text('common.go_back'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    // ── Route to correct screen based on role ────────────────────
    if (_role == 'worker') {
      return WorkerJobDetailsScreen(
        job:            _job!,
        workerId:       _workerId,
        workerCategory: _workerCategory,
        onBidPlaced:    () {
          // Pop back to notifications after bid placed from notification tap
          if (mounted) Navigator.pop(context);
        },
      );
    }

    // Default → client
    return ClientJobDetailsScreen(job: _job!);
  }
}