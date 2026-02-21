// lib/core/services/location_service.dart
//
// 100% FREE — uses:
//   • geolocator      → device GPS (no key)
//   • Nominatim API   → OSM geocoding (no key, just a User-Agent header)
//   • Haversine math  → distance calculation (offline)
// ─────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/worker_model.dart';

class LocationService {
  // ── Singleton ────────────────────────────────────────────────────
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // ── Constants ────────────────────────────────────────────────────
  static const double _earthRadiusKm = 6371.0;

  // Nominatim requires a User-Agent identifying your app.
  // Format: "AppName/version (contact@email.com)"
  static const String _nominatimUserAgent =
      'ChalOstaad/1.0 (support@chalostaad.pk)';

  static const String _nominatimBaseUrl =
      'https://nominatim.openstreetmap.org';

  // Nominatim fair-use: max 1 request/second. We add a small delay.
  static const Duration _nominatimDelay = Duration(milliseconds: 1100);
  DateTime? _lastNominatimCall;

  // ── Permission handling ──────────────────────────────────────────

  /// Check and request location permissions.
  /// Returns true if permission is granted.
  Future<bool> requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('LocationService: Device location services are disabled.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('LocationService: Permission denied by user.');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('LocationService: Permission permanently denied.');
      return false;
    }

    return true;
  }

  /// Check permission status without requesting.
  Future<LocationPermissionStatus> getPermissionStatus() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return LocationPermissionStatus.serviceDisabled;

    final permission = await Geolocator.checkPermission();
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.granted;
      case LocationPermission.denied:
        return LocationPermissionStatus.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.deniedForever;
      default:
        return LocationPermissionStatus.denied;
    }
  }

  /// Opens device app settings so user can manually grant permission.
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  // ── Get current position ─────────────────────────────────────────

  /// Returns the device's current GPS position.
  /// Throws [LocationException] if permission not granted.
  Future<Position> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    final hasPermission = await requestLocationPermission();
    if (!hasPermission) {
      throw LocationException(
          'Location permission not granted. Cannot get current position.');
    }
    try {
      return await Geolocator.getCurrentPosition(
          desiredAccuracy: accuracy);
    } catch (e) {
      throw LocationException('Failed to get current position: $e');
    }
  }

  /// Returns current position as a Firestore [GeoPoint].
  Future<GeoPoint> getCurrentGeoPoint() async {
    final position = await getCurrentPosition();
    return GeoPoint(position.latitude, position.longitude);
  }

  /// Returns current position as a [LatLng] (flutter_map type).
  Future<LatLng> getCurrentLatLng() async {
    final position = await getCurrentPosition();
    return LatLng(position.latitude, position.longitude);
  }

  // ── Live location stream ─────────────────────────────────────────

  /// Stream of position updates for live worker tracking.
  /// Only emits when worker moves more than [distanceFilterMeters].
  ///
  /// Usage:
  /// ```dart
  /// LocationService().positionStream().listen((pos) {
  ///   workerService.updateCurrentLocation(workerId, pos.latitude, pos.longitude);
  /// });
  /// ```
  Stream<Position> positionStream({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilterMeters = 50,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
      ),
    );
  }

  // ── Nominatim Geocoding (FREE — OpenStreetMap) ───────────────────

  /// Convert an address string into [GeoPoint] using Nominatim.
  ///
  /// Returns null if address cannot be resolved.
  /// Example: "Blue Area, Islamabad" → GeoPoint(33.72, 73.09)
  Future<GeoPoint?> addressToGeoPoint(String address) async {
    await _respectNominatimRateLimit();

    try {
      final uri = Uri.parse('$_nominatimBaseUrl/search').replace(
        queryParameters: {
          'q': address,
          'format': 'json',
          'limit': '1',
          'countrycodes': 'pk', // bias to Pakistan — remove if not needed
        },
      );

      final response = await http.get(uri, headers: {
        'User-Agent': _nominatimUserAgent,
        'Accept-Language': 'en',
      });

      if (response.statusCode != 200) {
        debugPrint('Nominatim search failed: ${response.statusCode}');
        return null;
      }

      final List<dynamic> results = jsonDecode(response.body);
      if (results.isEmpty) return null;

      final lat = double.tryParse(results[0]['lat'].toString());
      final lon = double.tryParse(results[0]['lon'].toString());

      if (lat == null || lon == null) return null;
      return GeoPoint(lat, lon);
    } catch (e) {
      debugPrint('LocationService.addressToGeoPoint error: $e');
      return null;
    }
  }

  /// Convert [GeoPoint] into a human-readable address using Nominatim reverse geocoding.
  ///
  /// Returns null if reverse geocoding fails.
  Future<String?> geoPointToAddress(GeoPoint point) async {
    await _respectNominatimRateLimit();

    try {
      final uri = Uri.parse('$_nominatimBaseUrl/reverse').replace(
        queryParameters: {
          'lat': point.latitude.toString(),
          'lon': point.longitude.toString(),
          'format': 'json',
        },
      );

      final response = await http.get(uri, headers: {
        'User-Agent': _nominatimUserAgent,
        'Accept-Language': 'en',
      });

      if (response.statusCode != 200) {
        debugPrint('Nominatim reverse failed: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      return data['display_name'] as String?;
    } catch (e) {
      debugPrint('LocationService.geoPointToAddress error: $e');
      return null;
    }
  }

  /// Extract just the city name from a [GeoPoint].
  Future<String?> getCityFromGeoPoint(GeoPoint point) async {
    await _respectNominatimRateLimit();

    try {
      final uri = Uri.parse('$_nominatimBaseUrl/reverse').replace(
        queryParameters: {
          'lat': point.latitude.toString(),
          'lon': point.longitude.toString(),
          'format': 'json',
          'zoom': '10', // city-level zoom
        },
      );

      final response = await http.get(uri, headers: {
        'User-Agent': _nominatimUserAgent,
        'Accept-Language': 'en',
      });

      if (response.statusCode != 200) return null;

      final data    = jsonDecode(response.body);
      final address = data['address'] as Map<String, dynamic>?;

      // Nominatim uses different keys depending on the location
      return address?['city']        as String? ??
          address?['town']        as String? ??
          address?['village']     as String? ??
          address?['county']      as String?;
    } catch (e) {
      debugPrint('LocationService.getCityFromGeoPoint error: $e');
      return null;
    }
  }

  /// Convert a Position to address string.
  Future<String?> positionToAddress(Position position) async {
    return geoPointToAddress(GeoPoint(position.latitude, position.longitude));
  }

  // ── Distance calculation (Haversine — fully offline) ─────────────

  /// Straight-line distance in km between two [GeoPoint]s.
  double distanceBetween(GeoPoint from, GeoPoint to) {
    final lat1 = _toRad(from.latitude);
    final lat2 = _toRad(to.latitude);
    final dLat = _toRad(to.latitude  - from.latitude);
    final dLng = _toRad(to.longitude - from.longitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
            math.sin(dLng / 2) * math.sin(dLng / 2);

    return _earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Distance between two [LatLng] points (flutter_map type).
  double distanceBetweenLatLng(LatLng from, LatLng to) {
    return distanceBetween(
      GeoPoint(from.latitude, from.longitude),
      GeoPoint(to.latitude, to.longitude),
    );
  }

  /// Distance using raw doubles.
  double distanceBetweenCoords(
      double lat1, double lng1, double lat2, double lng2) {
    return distanceBetween(GeoPoint(lat1, lng1), GeoPoint(lat2, lng2));
  }

  /// Returns true if [target] is within [radiusKm] of [origin].
  bool isWithinRadius(GeoPoint origin, GeoPoint target, double radiusKm) {
    return distanceBetween(origin, target) <= radiusKm;
  }

  /// Human-friendly distance: "2.4 km" or "850 m".
  String formatDistance(double distanceKm) {
    if (distanceKm < 1.0) return '${(distanceKm * 1000).round()} m';
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  // ── Conversions between GeoPoint and LatLng ───────────────────────
  //
  // flutter_map uses LatLng from the latlong2 package.
  // Firestore uses GeoPoint.
  // These helpers let you move between both without repetition.

  /// Convert Firestore [GeoPoint] → flutter_map [LatLng].
  LatLng geoPointToLatLng(GeoPoint point) =>
      LatLng(point.latitude, point.longitude);

  /// Convert flutter_map [LatLng] → Firestore [GeoPoint].
  GeoPoint latLngToGeoPoint(LatLng latLng) =>
      GeoPoint(latLng.latitude, latLng.longitude);

  /// Convert a list of [GeoPoint]s to [LatLng]s.
  List<LatLng> geoPointsToLatLngs(List<GeoPoint> points) =>
      points.map(geoPointToLatLng).toList();

  // ── Proximity filtering ──────────────────────────────────────────

  /// Filter a list of [WorkerModel]s to only those within [radiusKm]
  /// of [jobLocation]. Uses each worker's effectiveLocation.
  /// Workers with no location are excluded.
  List<WorkerModel> filterWorkersByRadius({
    required List<WorkerModel> workers,
    required GeoPoint jobLocation,
    required double radiusKm,
  }) {
    return workers.where((w) {
      final loc = w.effectiveLocation;
      if (loc == null) return false;
      return isWithinRadius(jobLocation, loc, radiusKm);
    }).toList();
  }

  /// Filter worker IDs by proximity — fetches location data from Firestore
  /// in batches of 10 and returns only IDs within [radiusKm].
  ///
  /// Plug this into [JobService.createJob()] to narrow notification targets.
  Future<List<String>> filterWorkerIdsByRadius({
    required List<String> workerIds,
    required GeoPoint jobLocation,
    required double radiusKm,
  }) async {
    if (workerIds.isEmpty) return [];

    final firestore  = FirebaseFirestore.instance;
    final nearbyIds  = <String>[];

    for (int i = 0; i < workerIds.length; i += 10) {
      final batch = workerIds.sublist(i, math.min(i + 10, workerIds.length));

      try {
        final snapshot = await firestore
            .collection('workers')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final doc in snapshot.docs) {
          final locationInfo =
          doc.data()['locationInfo'] as Map<String, dynamic>?;

          final workerLocation =
              locationInfo?['currentLocation'] as GeoPoint? ??
                  locationInfo?['homeLocation']    as GeoPoint?;

          if (workerLocation != null &&
              isWithinRadius(jobLocation, workerLocation, radiusKm)) {
            nearbyIds.add(doc.id);
          }
        }
      } catch (e) {
        debugPrint('filterWorkerIdsByRadius batch error: $e');
      }
    }

    return nearbyIds;
  }

  // ── Map camera helpers ────────────────────────────────────────────

  /// Returns SW and NE corners around a center at [radiusKm].
  /// Use this to set the initial map camera to fit all markers.
  MapBounds boundsFromCenterAndRadius(GeoPoint center, double radiusKm) {
    final latDelta = radiusKm / _earthRadiusKm * (180 / math.pi);
    final lngDelta = latDelta / math.cos(_toRad(center.latitude));

    return MapBounds(
      southwest: LatLng(center.latitude  - latDelta,
          center.longitude - lngDelta),
      northeast: LatLng(center.latitude  + latDelta,
          center.longitude + lngDelta),
    );
  }

  /// Returns a zoom level appropriate for a given radius in km.
  /// Useful for setting initial flutter_map zoom.
  double zoomForRadius(double radiusKm) {
    if (radiusKm <= 1)   return 15.0;
    if (radiusKm <= 5)   return 13.0;
    if (radiusKm <= 10)  return 12.0;
    if (radiusKm <= 25)  return 11.0;
    if (radiusKm <= 50)  return 10.0;
    return 9.0;
  }

  // ── Private helpers ───────────────────────────────────────────────

  double _toRad(double deg) => deg * math.pi / 180;

  /// Nominatim fair-use policy: max 1 request per second.
  Future<void> _respectNominatimRateLimit() async {
    final now = DateTime.now();
    if (_lastNominatimCall != null) {
      final elapsed = now.difference(_lastNominatimCall!);
      if (elapsed < _nominatimDelay) {
        await Future.delayed(_nominatimDelay - elapsed);
      }
    }
    _lastNominatimCall = DateTime.now();
  }
}

// ── Supporting types ──────────────────────────────────────────────────

enum LocationPermissionStatus {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

/// Bounding box used for flutter_map camera fitting.
class MapBounds {
  final LatLng southwest;
  final LatLng northeast;
  const MapBounds({required this.southwest, required this.northeast});
}

/// Thrown when a location operation fails.
class LocationException implements Exception {
  final String message;
  const LocationException(this.message);

  @override
  String toString() => 'LocationException: $message';
}