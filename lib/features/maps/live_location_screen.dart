// lib/features/maps/live_location_screen.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

class _WorkerLiveLocationScreenState extends State<WorkerLiveLocationScreen> {
  final MapService _mapService = MapService();
  final MapController _mapController = MapController();

  LatLng? _workerLocation;
  LatLng? _jobLocation;               // <-- Job location pin
  bool _loading = true;
  String? _error;
  bool _isConfirming = false;
  DateTime? _lastUpdate;

  bool _isLiveSharing = false;
  double? _heading;
  double? _accuracyMeters;

  bool _workerReachedLocation = false;
  String _jobStatus = '';

  // Flag to know if map is ready for controller actions
  bool _mapReady = false;

  String get _displayName {
    final name = widget.workerName.trim();
    final parts = name.split(' ');
    if (parts.isEmpty) return 'Worker';
    if (parts.first.toLowerCase() == 'muhammad' && parts.length > 1) {
      return parts[1];
    }
    return parts.first;
  }

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

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([_loadInitialLocation(), _loadJobData()]);
  }

  Future<void> _loadInitialLocation() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(widget.workerId)
          .get();

      if (doc.exists) {
        final locationInfo = doc.data()?['locationInfo'] as Map<String, dynamic>?;
        GeoPoint? geoPoint = locationInfo?['liveLocation'] as GeoPoint?;
        if (geoPoint == null) {
          geoPoint = locationInfo?['currentLocation'] as GeoPoint?;
        }

        final isSharing = locationInfo?['isLiveSharing'] as bool? ?? false;
        final heading = (locationInfo?['heading'] as num?)?.toDouble();
        final accuracy = (locationInfo?['accuracy'] as num?)?.toDouble();

        if (geoPoint != null && mounted) {
          final lat = geoPoint.latitude;
          final lng = geoPoint.longitude;
          setState(() {
            _workerLocation = LatLng(lat, lng);
            _isLiveSharing = isSharing;
            _heading = heading;
            _accuracyMeters = accuracy;
            _loading = false;
            _lastUpdate = DateTime.now();
          });
          _moveMapToLocation(LatLng(lat, lng));
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

  void _moveMapToLocation(LatLng location, {double zoom = 14.0}) {
    if (!_mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapReady) {
          _mapController.move(location, zoom);
        }
      });
    } else {
      _mapController.move(location, zoom);
    }
  }

  void _centerOnWorker() {
    final loc = _workerLocation;
    if (loc != null && _mapReady) {
      _mapController.move(loc, 15.0);
    } else if (loc != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapReady) {
          _mapController.move(loc, 15.0);
        }
      });
    }
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
          _workerReachedLocation = data['workerReachedLocation'] as bool? ?? false;
        });

        // Fetch job location (if present)
        final jobGeo = data['location'] as GeoPoint?;
        if (jobGeo != null) {
          final jobLoc = LatLng(jobGeo.latitude, jobGeo.longitude);
          if (_jobLocation != jobLoc) {
            setState(() {
              _jobLocation = jobLoc;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading job data: $e');
    }
  }

  Future<void> _confirmWorkerArrival() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Worker Arrival'),
        content: const Text(
          'Has the worker reached the job location? '
              'This will mark the job as In Progress.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not Yet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: CColors.success),
            child: const Text(
              'Yes, Arrived',
              style: TextStyle(color: Colors.white),
            ),
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
        'status': 'in-progress',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          _workerReachedLocation = true;
          _jobStatus = 'in-progress';
          _isConfirming = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Worker arrival confirmed! Job is now in progress.'),
            backgroundColor: CColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
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

  Widget _buildWorkerMarker() {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (_accuracyMeters != null && _accuracyMeters! < 200)
          Container(
            width: math.min(_accuracyMeters! * 0.6, 80),
            height: math.min(_accuracyMeters! * 0.6, 80),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
          ),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.blue.shade700,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
          ),
        ),
        if (_heading != null && _isLiveSharing)
          Transform.rotate(
            angle: (_heading! * math.pi) / 180,
            child: const Icon(
              Icons.navigation_rounded,
              color: Colors.white,
              size: 14,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bool canConfirm =
        (_jobStatus == 'in-progress' ||
            _jobStatus == 'active' ||
            _jobStatus == 'scheduled') &&
            !_workerReachedLocation;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Stack(
        children: [
          // Map fills entire screen including behind the header
          Positioned.fill(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : StreamBuilder<DocumentSnapshot>(
              stream: _workerLocationStream(),
              builder: (context, workerSnap) {
                if (workerSnap.hasData && workerSnap.data!.exists) {
                  final raw = workerSnap.data!.data() as Map<String, dynamic>?;
                  final locInfo = raw?['locationInfo'] as Map<String, dynamic>?;
                  GeoPoint? geoPoint = locInfo?['liveLocation'] as GeoPoint?;
                  if (geoPoint == null) {
                    geoPoint = locInfo?['currentLocation'] as GeoPoint?;
                  }
                  final isSharing = locInfo?['isLiveSharing'] as bool? ?? false;
                  final heading = (locInfo?['heading'] as num?)?.toDouble();
                  final accuracy = (locInfo?['accuracy'] as num?)?.toDouble();

                  if (geoPoint != null) {
                    final newLoc = LatLng(geoPoint.latitude, geoPoint.longitude);
                    final oldLoc = _workerLocation;
                    if (oldLoc != newLoc || _isLiveSharing != isSharing) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        if (_mapReady) {
                          _mapController.move(newLoc, 14.0);
                        }
                        setState(() {
                          _workerLocation = newLoc;
                          _isLiveSharing = isSharing;
                          _heading = heading;
                          _accuracyMeters = accuracy;
                          _lastUpdate = DateTime.now();
                        });
                      });
                    }
                  }
                }

                return StreamBuilder<DocumentSnapshot>(
                  stream: _jobStream(),
                  builder: (context, jobSnap) {
                    if (jobSnap.hasData && jobSnap.data!.exists) {
                      final jData = jobSnap.data!.data() as Map<String, dynamic>?;
                      final reached = jData?['workerReachedLocation'] as bool? ?? false;
                      final status = (jData?['status'] as String?)?.trim() ?? _jobStatus;
                      if (reached != _workerReachedLocation || status != _jobStatus) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {
                              _workerReachedLocation = reached;
                              _jobStatus = status;
                            });
                          }
                        });
                      }
                      // Update job location if it changed (unlikely)
                      final jobGeo = jData?['location'] as GeoPoint?;
                      if (jobGeo != null) {
                        final jobLoc = LatLng(jobGeo.latitude, jobGeo.longitude);
                        if (_jobLocation != jobLoc) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() {
                                _jobLocation = jobLoc;
                              });
                            }
                          });
                        }
                      }
                    }

                    return Stack(
                      children: [
                        // Full map
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _workerLocation ?? MapService.defaultCenter,
                            initialZoom: 14,
                            onMapReady: () {
                              if (mounted && !_mapReady) {
                                setState(() {
                                  _mapReady = true;
                                });
                                if (_workerLocation != null) {
                                  _moveMapToLocation(_workerLocation!);
                                }
                              }
                            },
                          ),
                          children: [
                            _mapService.osmTileLayer(),
                            // Job location pin (red)
                            if (_jobLocation != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _jobLocation!,
                                    width: 40,
                                    height: 40,
                                    child: const Icon(
                                      Icons.location_pin,
                                      color: Colors.red,
                                      size: 40,
                                    ),
                                  ),
                                ],
                              ),
                            // Worker marker (blue)
                            if (_workerLocation != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _workerLocation!,
                                    width: 80,
                                    height: 80,
                                    child: _buildWorkerMarker(),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        // "Not sharing" banner (top)
                        if (!_isLiveSharing && !_loading && _error == null)
                          Positioned(
                            top: 12,
                            left: 16,
                            right: 16,
                            child: _NotSharingBanner(workerName: _displayName),
                          ),
                        // Center on worker FAB (bottom right)
                        Positioned(
                          bottom: 20,
                          right: 20,
                          child: FloatingActionButton.small(
                            onPressed: _centerOnWorker,
                            backgroundColor: CColors.primary,
                            foregroundColor: Colors.white,
                            child: const Icon(Icons.my_location),
                          ),
                        ),
                        // Last update timestamp (bottom left)
                        if (_lastUpdate != null)
                          Positioned(
                            bottom: 20,
                            left: 20,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _isLiveSharing
                                    ? Colors.black54
                                    : Colors.orange.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isLiveSharing
                                        ? Icons.location_on_rounded
                                        : Icons.location_off_rounded,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isLiveSharing
                                        ? 'Live · ${DateFormat('HH:mm:ss').format(_lastUpdate!)}'
                                        : 'Last known · ${DateFormat('HH:mm').format(_lastUpdate!)}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Confirm arrival button (floating at bottom, above map)
                        Positioned(
                          bottom: 80, // above FAB and timestamp
                          left: 16,
                          right: 16,
                          child: ElevatedButton.icon(
                            onPressed: canConfirm && !_isConfirming ? _confirmWorkerArrival : null,
                            icon: _isConfirming
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                                : Icon(
                              _workerReachedLocation ? Icons.check_circle : Icons.where_to_vote_rounded,
                              size: 24,
                            ),
                            label: Text(
                              _isConfirming
                                  ? 'Confirming...'
                                  : _workerReachedLocation
                                  ? 'Worker Already Arrived ✓'
                                  : 'Confirm Worker Arrival',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _workerReachedLocation ? CColors.grey : CColors.success,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: _workerReachedLocation
                                  ? CColors.grey
                                  : CColors.grey.withValues(alpha: 0.5),
                              disabledForegroundColor: Colors.white70,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              minimumSize: const Size(double.infinity, 50),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          // Original CommonHeader overlaid on top — completely unchanged
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: CommonHeader(
              title: 'Live Location: $_displayName',
              showBackButton: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotSharingBanner extends StatelessWidget {
  final String workerName;
  const _NotSharingBanner({required this.workerName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade700.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$workerName has not enabled live location sharing. Showing last known position.',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}