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
  State<WorkerLiveLocationScreen> createState() => _WorkerLiveLocationScreenState();
}

class _WorkerLiveLocationScreenState extends State<WorkerLiveLocationScreen> {
  final MapService _mapService = MapService();
  final MapController _mapController = MapController();
  LatLng? _workerLocation;
  bool _loading = true;
  String? _error;

  Stream<DocumentSnapshot> _workerLocationStream() {
    return FirebaseFirestore.instance
        .collection('workers')
        .doc(widget.workerId)
        .snapshots();
  }

  @override
  void initState() {
    super.initState();
    _loadInitialLocation();
  }

  Future<void> _loadInitialLocation() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(widget.workerId)
          .get();
      if (doc.exists) {
        final locationInfo = doc.data()?['locationInfo'] as Map<String, dynamic>?;
        final geoPoint = locationInfo?['currentLocation'] as GeoPoint?;
        if (geoPoint != null && mounted) {
          setState(() {
            _workerLocation = LatLng(geoPoint.latitude, geoPoint.longitude);
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title: 'Live Location: ${widget.workerName}',
            showBackButton: true,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : StreamBuilder<DocumentSnapshot>(
              stream: _workerLocationStream(),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.exists) {
                  final locationInfo = snapshot.data!.data() as Map<String, dynamic>?;
                  final geoPoint = locationInfo?['locationInfo']?['currentLocation'] as GeoPoint?;
                  if (geoPoint != null) {
                    final newLoc = LatLng(geoPoint.latitude, geoPoint.longitude);
                    if (_workerLocation != newLoc) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _mapController.move(newLoc, 14.0);
                      });
                      setState(() {
                        _workerLocation = newLoc;
                      });
                    }
                  }
                }
                return Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _workerLocation ?? MapService.defaultCenter,
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
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
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
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}