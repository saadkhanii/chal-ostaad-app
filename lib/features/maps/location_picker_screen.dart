// lib/features/maps/location_picker_screen.dart
// Full-screen map picker — tap to pin a job location.
// ...

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/location_service.dart';
import '../../../core/services/map_service.dart';
import '../../../shared/widgets/common_header.dart';

class LocationPickerScreen extends StatefulWidget {
  final void Function(GeoPoint point, String? address) onLocationSelected;
  final GeoPoint? initialLocation;
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
  final _mapService = MapService();
  final _locationService = LocationService();
  late final MapController _mapController;

  LatLng? _pickedPoint;
  String? _resolvedAddress;
  bool _resolvingAddress = false;
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    if (widget.initialLocation != null) {
      _pickedPoint = _locationService.geoPointToLatLng(widget.initialLocation!);
      // Resolve address for initial location if provided
      _resolveAddressForPoint(_pickedPoint!);
    } else {
      _fetchCurrentLocation();
    }
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final position = await _locationService.getCurrentPosition();
      if (mounted) {
        final point = LatLng(position.latitude, position.longitude);
        setState(() {
          _pickedPoint = point;
          _isLoadingLocation = false;
        });
        // Resolve address for the current location
        _resolveAddressForPoint(point);
        // Move map after frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.move(_pickedPoint!, 15.0);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get current location. Using default.'),
            backgroundColor: Colors.orange,
          ),
        );
        _pickedPoint = MapService.defaultCenter;
        // Optionally resolve address for default? Not needed.
      }
    }
  }

  Future<void> _resolveAddressForPoint(LatLng point) async {
    setState(() {
      _resolvingAddress = true;
      _resolvedAddress = null;
    });
    final geoPoint = GeoPoint(point.latitude, point.longitude);
    final address = await _locationService.geoPointToAddress(geoPoint);
    if (mounted) {
      setState(() {
        _resolvedAddress = address;
        _resolvingAddress = false;
      });
    }
  }

  Future<void> _onMapTap(TapPosition tapPosition, LatLng point) async {
    setState(() {
      _pickedPoint = point;
    });
    // Resolve address for tapped point
    await _resolveAddressForPoint(point);
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
    final initialCenter = _pickedPoint ?? MapService.defaultCenter;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 13.0,
              onTap: _onMapTap,
            ),
            children: [
              _mapService.osmTileLayer(),
              if (_pickedPoint != null)
                _mapService.selectedPinLayer(_pickedPoint!),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: CommonHeader(
              title: 'Job Location',
              showBackButton: true,
            ),
          ),
          Positioned(
            top: 240,
            left: 20,
            right: 20,
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
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  if (_isLoadingLocation)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Getting current location...',
                              style: TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                    )
                  else if (_pickedPoint != null) ...[
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded,
                            color: theme.colorScheme.primary, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _resolvingAddress
                              ? const Text(
                            'Resolving address...',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
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
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _pickedPoint != null && !_isLoadingLocation
                          ? _confirm
                          : null,
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
                  final point = LatLng(pos.latitude, pos.longitude);
                  _mapController.move(point, 15.0);
                  setState(() {
                    _pickedPoint = point;
                  });
                  await _resolveAddressForPoint(point);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not get current location')),
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