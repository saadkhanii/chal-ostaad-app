// lib/features/maps/jobs_map_screen.dart
//
// Drop-in screen showing all open jobs as pins on an OSM map.
// Works for both workers (sees their radius + nearby jobs)
// and clients (sees all their posted jobs).
// ─────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/job_model.dart';
import '../../../core/models/worker_model.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/map_service.dart';
import '../../../core/routes/app_routes.dart';

class JobsMapScreen extends StatefulWidget {
  /// Pass a worker to show their location + radius circle + nearby jobs.
  /// Pass null for client view (shows all jobs, no radius).
  final WorkerModel? worker;

  /// Pre-loaded list of jobs to display.
  /// If null, pass [jobStream] instead.
  final List<JobModel>? jobs;

  const JobsMapScreen({
    super.key,
    this.worker,
    this.jobs,
  });

  @override
  State<JobsMapScreen> createState() => _JobsMapScreenState();
}

class _JobsMapScreenState extends State<JobsMapScreen> {
  final _mapService      = MapService();
  final _locationService = LocationService();
  final _mapController   = MapController();

  LatLng?        _workerLatLng;
  bool           _loadingLocation = true;
  String?        _locationError;
  List<JobModel> _jobs = [];

  @override
  void initState() {
    super.initState();
    _jobs = widget.jobs ?? [];
    _initWorkerLocation();
  }

  Future<void> _initWorkerLocation() async {
    // If we have a worker with a known location, use that first (instant)
    if (widget.worker?.effectiveLocation != null) {
      setState(() {
        _workerLatLng   = _locationService
            .geoPointToLatLng(widget.worker!.effectiveLocation!);
        _loadingLocation = false;
      });
      return;
    }

    // Otherwise try to get live GPS
    try {
      final pos = await _locationService.getCurrentPosition();
      if (mounted) {
        setState(() {
          _workerLatLng    = LatLng(pos.latitude, pos.longitude);
          _loadingLocation = false;
        });
        _mapController.move(_workerLatLng!, 12.0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationError   = e.toString();
          _loadingLocation = false;
        });
      }
    }
  }

  void _onJobTapped(JobModel job) {
    _mapService.showJobInfoSheet(
      context,
      job,
      onViewDetails: () {
        Navigator.of(context).pop(); // close bottom sheet
        if (job.id != null && job.id!.isNotEmpty) {
          Navigator.pushNamed(
            context,
            AppRoutes.jobDetails,
            arguments: job.id,
          );
        }
      },
      onGetDirections: _workerLatLng == null || job.location == null
          ? null
          : () async {
        final workerGeo = GeoPoint(
            _workerLatLng!.latitude, _workerLatLng!.longitude);
        await _mapService.openDirections(
          from: workerGeo,
          to: job.location!,
          destinationLabel: job.title,
        );
      },
    );
  }

  void _centerOnWorker() {
    if (_workerLatLng != null) {
      _mapController.move(_workerLatLng!, 13.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme          = Theme.of(context);
    final worker         = widget.worker;
    final radiusKm       = (worker?.serviceRadius ?? 10).toDouble();
    final jobsWithLoc    = _jobs.where((j) => j.hasLocation).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jobs Map'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          // Job count badge
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$jobsWithLoc jobs',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _workerLatLng ?? MapService.defaultCenter,
              initialZoom:   MapService.defaultZoom,
            ),
            children: [
              // 1. OSM tiles
              _mapService.osmTileLayer(),

              // 2. Service radius circle (worker view only)
              if (worker != null && _workerLatLng != null)
                _mapService.serviceRadiusLayer(
                  center:   _workerLatLng!,
                  radiusKm: radiusKm,
                ),

              // 3. Job markers
              _mapService.jobMarkersLayer(
                jobs:     _jobs,
                onJobTap: _onJobTapped,
              ),

              // 4. Worker location dot
              if (_workerLatLng != null)
                _mapService.workerLocationLayer(
                  position:   _workerLatLng!,
                  workerName: worker?.firstName ?? 'You',
                ),
            ],
          ),

          // ── Loading overlay ────────────────────────────────────────
          if (_loadingLocation)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _InfoBanner(
                icon: Icons.location_searching_rounded,
                message: 'Getting your location...',
                color: theme.colorScheme.primary,
              ),
            ),

          // ── Location error banner ──────────────────────────────────
          if (_locationError != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _InfoBanner(
                icon: Icons.location_off_rounded,
                message: 'Location unavailable — showing all jobs',
                color: Colors.orange,
              ),
            ),

          // ── Legend (worker view) ───────────────────────────────────
          if (worker != null)
            Positioned(
              bottom: 100,
              left: 16,
              child: _Legend(radiusKm: radiusKm),
            ),
        ],
      ),

      // ── FABs ────────────────────────────────────────────────────────
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Center on worker
          if (_workerLatLng != null)
            FloatingActionButton.small(
              heroTag: 'center_worker',
              onPressed: _centerOnWorker,
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.my_location_rounded),
            ),
          const SizedBox(height: 8),
          // Center on all jobs
          if (_jobs.any((j) => j.hasLocation))
            FloatingActionButton.small(
              heroTag: 'center_jobs',
              onPressed: _fitAllJobs,
              backgroundColor: theme.colorScheme.surface,
              foregroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.zoom_out_map_rounded),
            ),
        ],
      ),
    );
  }

  void _fitAllJobs() {
    final points = _jobs
        .where((j) => j.hasLocation)
        .map((j) => LatLng(j.latitude!, j.longitude!))
        .toList();

    if (points.isEmpty) return;

    if (points.length == 1) {
      _mapController.move(points.first, 14.0);
      return;
    }

    // Calculate bounds
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final center = LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );

    // Rough zoom based on bounding box size
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

    double zoom = 13.0;
    if (maxDiff > 2)    zoom = 8.0;
    else if (maxDiff > 1)    zoom = 9.0;
    else if (maxDiff > 0.5)  zoom = 10.0;
    else if (maxDiff > 0.1)  zoom = 11.0;
    else if (maxDiff > 0.05) zoom = 12.0;

    _mapController.move(center, zoom);
  }
}

// ── Info Banner ────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _InfoBanner({
    required this.icon,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── Legend ─────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  final double radiusKm;
  const _Legend({required this.radiusKm});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendRow(
            color: const Color(0xFF2563EB),
            icon: Icons.work_rounded,
            label: 'Job',
          ),
          const SizedBox(height: 4),
          _LegendRow(
            color: Colors.blue.shade700,
            icon: Icons.circle,
            label: 'Your location',
          ),
          const SizedBox(height: 4),
          _LegendRow(
            color: const Color(0xFF2563EB),
            icon: Icons.radio_button_unchecked_rounded,
            label: '${radiusKm.toInt()} km radius',
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;

  const _LegendRow({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}