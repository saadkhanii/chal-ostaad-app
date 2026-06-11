// lib/core/services/map_service.dart
//
// Provides ready-to-use flutter_map widgets and helpers:
//   • OSM tile layer            (free, no key)
//   • Job markers               (tap to see job details)
//   • Worker location marker    (current position)
//   • Service radius circle     (worker's coverage area)
//   • Location picker           (tap map to pin a job location)
//   • Directions launcher       (opens phone's maps app)
// ─────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/job_model.dart';
import '../models/worker_model.dart';
import 'location_service.dart';
import '../../features/maps/location_picker_screen.dart';

class MapService {
  // ── Singleton ────────────────────────────────────────────────────
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  final LocationService _locationService = LocationService();

  // ── Default center (Islamabad) ───────────────────────────────────
  // Used when no location is available yet.
  static const LatLng defaultCenter = LatLng(33.6844, 73.0479);
  static const double defaultZoom   = 12.0;

  // ── OSM Tile Layer ───────────────────────────────────────────────

  /// Standard OpenStreetMap tile layer.
  /// Drop this as the first layer inside FlutterMap's layers list.
  TileLayer osmTileLayer() {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'pk.chalostaad.app',
      maxZoom: 19,
    );
  }

  // ── Map Controllers ──────────────────────────────────────────────

  /// Create a MapController to programmatically move/zoom the map.
  /// Store this in your widget's state.
  MapController createController() => MapController();

  /// Animate the map to a new center + zoom.
  void moveTo(
      MapController controller,
      LatLng center, {
        double zoom = 14.0,
      }) {
    controller.move(center, zoom);
  }

  /// Move map to a GeoPoint (Firestore type → LatLng conversion included).
  void moveToGeoPoint(
      MapController controller,
      GeoPoint point, {
        double zoom = 14.0,
      }) {
    controller.move(
      _locationService.geoPointToLatLng(point),
      zoom,
    );
  }

  // ── Job Markers Layer ────────────────────────────────────────────

  /// Builds a [MarkerLayer] for a list of jobs.
  /// Only jobs that have a location are shown.
  ///
  /// [onJobTap] is called with the tapped [JobModel] — use it to show
  /// a bottom sheet or navigate to the job detail screen.
  MarkerLayer jobMarkersLayer({
    required List<JobModel> jobs,
    required void Function(JobModel job) onJobTap,
    Color markerColor = const Color(0xFF2563EB), // blue
    double markerSize = 40.0,
  }) {
    final markers = jobs
        .where((job) => job.hasLocation)
        .map((job) => _buildJobMarker(
      job: job,
      onTap: () => onJobTap(job),
      color: markerColor,
      size: markerSize,
    ))
        .toList();

    return MarkerLayer(markers: markers);
  }

  Marker _buildJobMarker({
    required JobModel job,
    required VoidCallback onTap,
    required Color color,
    required double size,
  }) {
    return Marker(
      point: LatLng(job.latitude!, job.longitude!),
      width: size,
      height: size,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: job.title,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.work_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  // ── Worker Location Marker ────────────────────────────────────────

  /// Builds a [MarkerLayer] showing the worker's current position.
  /// Shows a pulsing blue dot style marker.
  MarkerLayer workerLocationLayer({
    required LatLng position,
    String workerName = 'You',
  }) {
    return MarkerLayer(
      markers: [
        Marker(
          point: position,
          width: 48,
          height: 48,
          child: Tooltip(
            message: workerName,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer pulse ring
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                ),
                // Inner dot
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Service Radius Circle ─────────────────────────────────────────

  /// Builds a [CircleLayer] showing a worker's service radius.
  ///
  /// [radiusKm] comes from WorkerModel.serviceRadius.
  CircleLayer serviceRadiusLayer({
    required LatLng center,
    required double radiusKm,
    Color fillColor   = const Color(0x1A2563EB), // 10% blue fill
    Color borderColor = const Color(0xFF2563EB),
  }) {
    return CircleLayer(
      circles: [
        CircleMarker(
          point: center,
          radius: _kmToMeters(radiusKm),
          useRadiusInMeter: true,
          color: fillColor,
          borderColor: borderColor,
          borderStrokeWidth: 1.5,
        ),
      ],
    );
  }

  // ── Location Picker ───────────────────────────────────────────────

  /// Returns a full-screen location picker widget.
  ///
  /// The user taps the map to place a pin. When they confirm,
  /// [onLocationSelected] is called with the chosen [GeoPoint].
  ///
  /// Usage in job posting screen:
  /// ```dart
  /// final picked = await Navigator.push(
  ///   context,
  ///   MaterialPageRoute(
  ///     builder: (_) => MapService().locationPickerScreen(
  ///       onLocationSelected: (geoPoint, address) {
  ///         setState(() {
  ///           _jobLocation = geoPoint;
  ///           _addressController.text = address ?? '';
  ///         });
  ///       },
  ///     ),
  ///   ),
  /// );
  /// ```
  Widget locationPickerScreen({
    required void Function(GeoPoint point, String? address) onLocationSelected,
    GeoPoint? initialLocation,
    String confirmLabel = 'Confirm Location',
  }) {
    return LocationPickerScreen(
      onLocationSelected: onLocationSelected,
      initialLocation: initialLocation,
      confirmLabel: confirmLabel,
    );
  }

  // ── Selected Pin Marker ───────────────────────────────────────────

  /// A red pin marker for a selected/picked location.
  MarkerLayer selectedPinLayer(LatLng point) {
    return MarkerLayer(
      markers: [
        Marker(
          point: point,
          width: 40,
          height: 50,
          alignment: Alignment.topCenter,
          child: const Icon(
            Icons.location_pin,
            color: Colors.red,
            size: 48,
          ),
        ),
      ],
    );
  }

  // ── Directions ────────────────────────────────────────────────────

  /// Opens the phone's default maps app (Google Maps / Apple Maps)
  /// with directions from [from] to [to].
  ///
  /// Works on Android and iOS — completely free.
  Future<void> openDirections({
    required GeoPoint from,
    required GeoPoint to,
    String? destinationLabel,
  }) async {
    final label = Uri.encodeComponent(destinationLabel ?? 'Job Location');

    // Google Maps URL — works if Google Maps is installed
    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
          '&origin=${from.latitude},${from.longitude}'
          '&destination=${to.latitude},${to.longitude}'
          '&travelmode=driving',
    );

    // geo: URI — universal fallback for any maps app
    final geoUri = Uri.parse(
      'geo:${to.latitude},${to.longitude}?q=${to.latitude},${to.longitude}($label)',
    );

    // Skip canLaunchUrl — unreliable on many Android devices.
    // Directly try launching, catch failure and try next option.
    try {
      await launchUrl(googleMapsUrl,
          mode: LaunchMode.externalApplication);
      return;
    } catch (_) {
      debugPrint('MapService: Google Maps failed, trying geo: URI');
    }

    try {
      await launchUrl(geoUri,
          mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('MapService: Could not launch any maps app: \$e');
    }
  }

  // ── Job Info Bottom Sheet ─────────────────────────────────────────

  /// Shows a bottom sheet with job details when a marker is tapped.
  /// Call this from the [onJobTap] callback in [jobMarkersLayer].
  void showJobInfoSheet(
      BuildContext context,
      JobModel job, {
        VoidCallback? onViewDetails,
        Future<void> Function()? onGetDirections,
      }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _JobInfoSheet(
        job: job,
        onViewDetails: onViewDetails,
        onGetDirections: onGetDirections,
      ),
    );
  }

  // ── Distance badge helper ─────────────────────────────────────────

  /// Returns a formatted distance string from worker to job.
  /// Returns null if either location is missing.
  String? getDistanceLabel(WorkerModel worker, JobModel job) {
    final workerLoc = worker.effectiveLocation;
    final jobLoc    = job.location;
    if (workerLoc == null || jobLoc == null) return null;

    final distKm = _locationService.distanceBetween(workerLoc, jobLoc);
    return _locationService.formatDistance(distKm);
  }

  // ── Private helpers ───────────────────────────────────────────────

  double _kmToMeters(double km) => km * 1000;
}


// ── Job Info Bottom Sheet ─────────────────────────────────────────────

class _JobInfoSheet extends StatelessWidget {
  final JobModel job;
  final VoidCallback? onViewDetails;
  final Future<void> Function()? onGetDirections;

  const _JobInfoSheet({
    required this.job,
    this.onViewDetails,
    this.onGetDirections,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Status chip + title
            Row(
              children: [
                _StatusChip(status: job.status),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    job.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Location row
            Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    job.displayLocation,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Description preview
            Text(
              job.description,
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                if (onGetDirections != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onGetDirections,
                      icon: const Icon(Icons.directions_rounded, size: 18),
                      label: const Text('Directions'),
                      style: OutlinedButton.styleFrom(
                        padding:
                        const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                if (onGetDirections != null && onViewDetails != null)
                  const SizedBox(width: 10),
                if (onViewDetails != null)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onViewDetails,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('View Details'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding:
                        const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'open'       => Colors.green,
      'in_progress'=> Colors.orange,
      'completed'  => Colors.blue,
      'cancelled'  => Colors.red,
      _            => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}