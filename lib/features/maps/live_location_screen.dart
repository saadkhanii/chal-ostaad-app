// lib/features/maps/live_location_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../core/services/map_service.dart';
import '../../../shared/widgets/common_header.dart';

class WorkerLiveLocationScreen extends StatefulWidget {
  final String jobId;
  final String workerId;
  final String workerName;

  const WorkerLiveLocationScreen({
    super.key,
    required this.jobId,
    required this.workerId,
    required this.workerName,
  });

  @override
  State<WorkerLiveLocationScreen> createState() =>
      _WorkerLiveLocationScreenState();
}

class _WorkerLiveLocationScreenState
    extends State<WorkerLiveLocationScreen> {
  final MapService _mapService = MapService();
  final MapController _mapController = MapController();

  LatLng? _workerLocation;
  bool _loading = true;
  String? _error;
  bool _isConfirming = false;

  // 'in-progress' = worker started but not yet arrived (button enabled)
  // 'arrived'     = workerReachedLocation == true  (button disabled, label updated)
  // anything else = still loading
  String _jobStatus = '';
  bool _workerReachedLocation = false;

  // ── Display name (strips leading "Muhammad") ──────────────────────
  String get _displayName {
    final name = widget.workerName.trim();
    final parts = name.split(' ');
    if (parts.isEmpty) return 'Worker';
    if (parts.first.toLowerCase() == 'muhammad' && parts.length > 1) {
      return parts[1];
    }
    return parts.first;
  }

  // ── Firestore streams ─────────────────────────────────────────────
  Stream<DocumentSnapshot> _workerLocationStream() =>
      FirebaseFirestore.instance
          .collection('workers')
          .doc(widget.workerId)
          .snapshots();

  Stream<DocumentSnapshot> _jobStream() =>
      FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .snapshots();

  // ── Lifecycle ─────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadInitialLocation(),
      _loadJobData(),
    ]);
  }

  Future<void> _loadJobData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _jobStatus = (data['status'] as String?)?.trim() ?? '';
          _workerReachedLocation =
              data['workerReachedLocation'] as bool? ?? false;
        });
      }
    } catch (e) {
      debugPrint('Error loading job data: $e');
    }
  }

  Future<void> _loadInitialLocation() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(widget.workerId)
          .get();
      if (doc.exists) {
        final locationInfo =
        doc.data()?['locationInfo'] as Map<String, dynamic>?;
        final geoPoint = locationInfo?['currentLocation'] as GeoPoint?;
        if (geoPoint != null && mounted) {
          setState(() {
            _workerLocation =
                LatLng(geoPoint.latitude, geoPoint.longitude);
            _loading = false;
          });
          _mapController.move(_workerLocation!, 14.0);
        } else {
          setState(() {
            _error = 'Worker location not available yet';
            _loading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading location: $e';
        _loading = false;
      });
    }
  }

  void _centerOnWorker() {
    if (_workerLocation != null) {
      _mapController.move(_workerLocation!, 15.0);
    }
  }

  // ── Confirm arrival ───────────────────────────────────────────────
  // Called when client taps the button.
  // Precondition: job is 'in-progress' and workerReachedLocation == false.
  Future<void> _confirmWorkerArrival() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Worker Arrival'),
        content: const Text(
            'Has the worker reached the job location? This will mark the job as In Progress.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not Yet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: CColors.success),
            child: const Text('Yes, Arrived',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isConfirming = true);
    try {
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .update({
        'workerReachedLocation': true,
        // Status stays 'in-progress'; this flag is what gates the next
        // phase on both client and worker detail screens.
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          _workerReachedLocation = true;
          _isConfirming = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Worker arrival confirmed! Job is now in progress.'),
            backgroundColor: CColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Return to job details after a short pause so the snackbar is seen.
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConfirming = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: CColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Button is active when the job is in-progress AND the worker hasn't
    // been confirmed as arrived yet.
    final bool canConfirm =
        _jobStatus == 'in-progress' && !_workerReachedLocation;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title: 'Live Location: $_displayName',
            showBackButton: true,
          ),

          // ── Map area ───────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : StreamBuilder<DocumentSnapshot>(
              // Listen to worker location updates
              stream: _workerLocationStream(),
              builder: (context, workerSnap) {
                if (workerSnap.hasData &&
                    workerSnap.data!.exists) {
                  final raw = workerSnap.data!.data()
                  as Map<String, dynamic>?;
                  final geoPoint = raw?['locationInfo']
                  ?['currentLocation'] as GeoPoint?;
                  if (geoPoint != null) {
                    final newLoc = LatLng(
                        geoPoint.latitude, geoPoint.longitude);
                    if (_workerLocation != newLoc) {
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) {
                        _mapController.move(newLoc, 14.0);
                      });
                      // ignore: invalid_use_of_protected_member
                      setState(() => _workerLocation = newLoc);
                    }
                  }
                }

                return StreamBuilder<DocumentSnapshot>(
                  // Also listen to job doc so the button
                  // reacts if another device confirms arrival.
                  stream: _jobStream(),
                  builder: (context, jobSnap) {
                    if (jobSnap.hasData &&
                        jobSnap.data!.exists) {
                      final jData = jobSnap.data!.data()
                      as Map<String, dynamic>?;
                      final reached = jData?[
                      'workerReachedLocation']
                      as bool? ??
                          false;
                      final status =
                          (jData?['status'] as String?)
                              ?.trim() ??
                              _jobStatus;
                      if (reached != _workerReachedLocation ||
                          status != _jobStatus) {
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {
                              _workerReachedLocation = reached;
                              _jobStatus = status;
                            });
                          }
                        });
                      }
                    }

                    return Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _workerLocation ??
                                MapService.defaultCenter,
                            initialZoom: 14,
                          ),
                          children: [
                            _mapService.osmTileLayer(),
                            if (_workerLocation != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _workerLocation!,
                                    width: 48,
                                    height: 48,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: Colors.blue
                                                .withValues(
                                                alpha: 0.2),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            color: Colors
                                                .blue.shade700,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),

                        // Center-on-worker FAB
                        Positioned(
                          bottom: 20,
                          right: 20,
                          child: FloatingActionButton.small(
                            onPressed: _centerOnWorker,
                            backgroundColor: CColors.primary,
                            foregroundColor: Colors.white,
                            child:
                            const Icon(Icons.my_location),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // ── Confirmation button — always visible below the map ─────
          SafeArea(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                isDark ? CColors.darkContainer : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: canConfirm && !_isConfirming
                    ? _confirmWorkerArrival
                    : null,
                icon: _isConfirming
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : Icon(
                  _workerReachedLocation
                      ? Icons.check_circle
                      : Icons.where_to_vote_rounded,
                  size: 24,
                ),
                label: Text(
                  _isConfirming
                      ? 'Confirming...'
                      : _workerReachedLocation
                      ? 'Worker Already Arrived ✓'
                      : 'Confirm Worker Arrival at Destination',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  // Green while actionable, grey once confirmed
                  backgroundColor: _workerReachedLocation
                      ? CColors.grey
                      : CColors.success,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _workerReachedLocation
                      ? CColors.grey
                      : CColors.grey.withValues(alpha: 0.5),
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}