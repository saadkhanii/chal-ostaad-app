// lib/features/maps/location_picker_screen.dart
//
// Full-screen map picker — tap to pin a job location.
// Extracted from MapService for use as a standalone named or pushed route.
// ─────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/location_service.dart';
import '../../../core/services/map_service.dart';
import '../../../shared/widgets/common_header.dart';

class LocationPickerScreen extends StatefulWidget {
  /// Called when the user confirms a location.
  final void Function(GeoPoint point, String? address) onLocationSelected;

  /// Pre-select a location when the screen opens (e.g. editing an existing job).
  final GeoPoint? initialLocation;

  /// Label on the confirm button.
  final String confirmLabel;

  const LocationPickerScreen({
    super.key,
    required this.onLocationSelected,
    this.initialLocation,
    this.confirmLabel = 'Confirm Location',
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _mapService      = MapService();
  final _locationService = LocationService();
  late final MapController _mapController;

  LatLng? _pickedPoint;
  String? _resolvedAddress;
  bool    _resolvingAddress = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    if (widget.initialLocation != null) {
      _pickedPoint = _locationService.geoPointToLatLng(widget.initialLocation!);
    }
  }

  Future<void> _onMapTap(TapPosition tapPosition, LatLng point) async {
    setState(() {
      _pickedPoint      = point;
      _resolvedAddress  = null;
      _resolvingAddress = true;
    });

    final geoPoint = GeoPoint(point.latitude, point.longitude);
    final address  = await _locationService.geoPointToAddress(geoPoint);

    if (mounted) {
      setState(() {
        _resolvedAddress  = address;
        _resolvingAddress = false;
      });
    }
  }

  void _confirm() {
    if (_pickedPoint == null) return;
    final geoPoint = GeoPoint(_pickedPoint!.latitude, _pickedPoint!.longitude);
    widget.onLocationSelected(geoPoint, _resolvedAddress);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // ── Map (full screen) ────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pickedPoint ??
                  (widget.initialLocation != null
                      ? _locationService.geoPointToLatLng(widget.initialLocation!)
                      : MapService.defaultCenter),
              initialZoom: 13.0,
              onTap: _onMapTap,
            ),
            children: [
              _mapService.osmTileLayer(),
              if (_pickedPoint != null)
                _mapService.selectedPinLayer(_pickedPoint!),
            ],
          ),

          // ── CommonHeader overlay ─────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: CommonHeader(
              title: 'Pick Job Location',
              showBackButton: true,
            ),
          ),

          // ── Tap hint banner ──────────────────────────────────────
          Positioned(
            top: 185,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.touch_app_rounded,
                      color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tap on the map to place the job location',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom panel ─────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Address display
                  if (_pickedPoint != null) ...[
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded,
                            color: theme.colorScheme.primary, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _resolvingAddress
                              ? const Text(
                            'Resolving address...',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey),
                          )
                              : Text(
                            _resolvedAddress ??
                                '${_pickedPoint!.latitude.toStringAsFixed(5)}, '
                                    '${_pickedPoint!.longitude.toStringAsFixed(5)}',
                            style: const TextStyle(fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    const Text(
                      'No location selected yet',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _pickedPoint != null ? _confirm : null,
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: Text(widget.confirmLabel),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── My location FAB ──────────────────────────────────────
          Positioned(
            bottom: 160,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'my_location',
              backgroundColor: theme.colorScheme.surface,
              foregroundColor: theme.colorScheme.primary,
              onPressed: () async {
                try {
                  final pos = await _locationService.getCurrentPosition();
                  _mapController.move(
                    LatLng(pos.latitude, pos.longitude),
                    15.0,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Could not get current location')),
                    );
                  }
                }
              },
              child: const Icon(Icons.my_location_rounded),
            ),
          ),
        ],
      ),
    );
  }
}