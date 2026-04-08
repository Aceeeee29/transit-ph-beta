import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:math' as math;
import '../models/ors_route_result.dart';
import '../repositories/route_cache_repository.dart';
import '../services/route_metrics_service.dart';

/// Displays an ORS-generated route on an interactive map.
/// Shows the road-snapped polyline, start/end markers, current location,
/// and a draggable bottom sheet with distance, duration, and turn-by-turn steps.
class OrsRouteMapScreen extends StatefulWidget {
  final OrsRouteResult result;
  final String originName;
  final String destinationName;
  final bool showDownloadButton;

  const OrsRouteMapScreen({
    super.key,
    required this.result,
    required this.originName,
    required this.destinationName,
    this.showDownloadButton = true,
  });

  @override
  State<OrsRouteMapScreen> createState() => _OrsRouteMapScreenState();
}

class _OrsRouteMapScreenState extends State<OrsRouteMapScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  LatLng? _displayPosition;
  double _displayHeading = 0;
  LatLng? _lastCameraTarget;
  DateTime? _lastCameraMoveAt;
  bool _isLocating = false;
  bool _isNavigationStarted = false;
  bool _isAutoFollowEnabled = false;
  bool _isDownloaded = false;
  bool _isDownloading = false;

  static const _cacheMode = 'Auto';
  static const _cacheProfile = 'supabase-gtfs-v9';

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadDownloadState();
  }

  Future<void> _loadDownloadState() async {
    final cached = await RouteCacheRepository.get(
      widget.originName,
      widget.destinationName,
      _cacheMode,
      _cacheProfile,
    );
    if (!mounted) return;
    setState(() => _isDownloaded = cached != null);
  }

  Future<void> _downloadGeneratedRoute() async {
    if (!widget.showDownloadButton) return;
    if (_isDownloading || _isDownloaded) return;

    setState(() => _isDownloading = true);
    try {
      await RouteCacheRepository.put(
        widget.originName,
        widget.destinationName,
        _cacheMode,
        _cacheProfile,
        widget.result,
      );
      if (!mounted) return;
      setState(() => _isDownloaded = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generated route downloaded for offline mode.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download route: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _initLocation() async {
    setState(() => _isLocating = true);
    final permission = await Permission.location.request();
    if (permission.isGranted) {
      try {
        _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        _displayPosition =
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
        _displayHeading = _normalizeHeading(_currentPosition!.heading);
        _startLocationTracking();
      } catch (_) {}
    }
    setState(() => _isLocating = false);
  }

  void _startLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 2,
      ),
    ).listen(
      (position) {
        _handleLocationUpdate(position);
      },
      onError: (_) {},
    );
  }

  void _handleLocationUpdate(Position position) {
    if (!mounted) return;
    if (position.accuracy > 45) return;

    final raw = LatLng(position.latitude, position.longitude);
    final nextDisplay = _displayPosition == null
        ? raw
        : LatLng(
            _lerp(_displayPosition!.latitude, raw.latitude, 0.28),
            _lerp(_displayPosition!.longitude, raw.longitude, 0.28),
          );
    final nextHeading = _smoothHeading(_displayHeading, position.heading);

    final hasMoved = _displayPosition == null ||
        const Distance().as(LengthUnit.Meter, _displayPosition!, nextDisplay) >=
            0.8;
    final headingChanged = _angularDifference(_displayHeading, nextHeading) >= 2;

    if (!hasMoved && !headingChanged) return;

    setState(() {
      _currentPosition = position;
      _displayPosition = nextDisplay;
      _displayHeading = nextHeading;
    });

    if (_isNavigationStarted && _isAutoFollowEnabled) {
      _maybeMoveCamera(nextDisplay);
    }
  }

  void _maybeMoveCamera(LatLng target) {
    final now = DateTime.now();
    if (_lastCameraMoveAt != null &&
        now.difference(_lastCameraMoveAt!).inMilliseconds < 450) {
      return;
    }
    if (_lastCameraTarget != null &&
        const Distance().as(LengthUnit.Meter, _lastCameraTarget!, target) < 2.5) {
      return;
    }

    final zoom = _mapController.camera.zoom < 15 ? 15.0 : _mapController.camera.zoom;
    _lastCameraMoveAt = now;
    _lastCameraTarget = target;
    _mapController.move(target, zoom);
  }

  double _lerp(double from, double to, double factor) => from + (to - from) * factor;

  double _normalizeHeading(double heading) {
    if (!heading.isFinite || heading < 0) return _displayHeading;
    final value = heading % 360;
    return value < 0 ? value + 360 : value;
  }

  double _smoothHeading(double current, double incoming) {
    final target = _normalizeHeading(incoming);
    final delta = ((target - current + 540) % 360) - 180;
    return (current + (delta * 0.25) + 360) % 360;
  }

  double _angularDifference(double a, double b) {
    final diff = (a - b).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _centerOnRoute() {
    if (widget.result.polyline.isEmpty) return;
    final points = widget.result.polyline;
    final center = LatLng(
      (points.first.latitude + points.last.latitude) / 2,
      (points.first.longitude + points.last.longitude) / 2,
    );
    _mapController.move(center, 13.0);
  }

  void _centerOnMe() {
    if (_displayPosition == null) return;
    if (_isNavigationStarted && !_isAutoFollowEnabled) {
      setState(() => _isAutoFollowEnabled = true);
    }
    _mapController.move(
      _displayPosition!,
      15.0,
    );
  }

  void _startNavigation() {
    if (_displayPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for live location...')),
      );
      return;
    }

    setState(() {
      _isNavigationStarted = true;
      _isAutoFollowEnabled = true;
    });
    _centerOnMe();
  }

  LatLng get _mapCenter {
    final points = widget.result.polyline;
    if (points.isEmpty) return const LatLng(14.5995, 120.9842); // Manila
    return LatLng(
      (points.first.latitude + points.last.latitude) / 2,
      (points.first.longitude + points.last.longitude) / 2,
    );
  }

  /// Builds one colored polyline per step, sliced from the full ORS geometry
  /// using the way_point indices. Each segment color matches the transit mode.
  List<Polyline> get _polylines {
    final allPoints = widget.result.polyline;
    if (allPoints.length < 2) return [];

    final steps = widget.result.steps;

    // Fallback — if no steps or no waypoint data, draw single blue line
    if (steps.isEmpty || steps.every((s) => s.wayPointEnd == 0)) {
      return [
        Polyline(
          points: allPoints,
          color: Colors.white,
          strokeWidth: 8.0,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        Polyline(
          points: allPoints,
          color: Colors.blue.shade700,
          strokeWidth: 5.5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      ];
    }

    final polylines = <Polyline>[];

    for (final step in steps) {
      final start = step.wayPointStart.clamp(0, allPoints.length - 1);
      final end = step.wayPointEnd.clamp(0, allPoints.length - 1);

      if (end <= start) continue;

      final segmentPoints = allPoints.sublist(start, end + 1);
      if (segmentPoints.length < 2) continue;

      final color = _modeColor(step.suggestedMode);

      // White outline for contrast against the map
      polylines.add(Polyline(
        points: segmentPoints,
        color: Colors.white,
        strokeWidth: 8.0,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      ));

      // Colored segment
      polylines.add(Polyline(
        points: segmentPoints,
        color: color,
        strokeWidth: 5.5,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      ));
    }

    return polylines;
  }

  List<Marker> get _markers {
    final markers = <Marker>[];
    final points = widget.result.polyline;

    // Origin marker
    if (points.isNotEmpty) {
      markers.add(
        Marker(
          point: points.first,
          width: 44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.my_location, color: Colors.white, size: 22),
          ),
        ),
      );
    }

    // Destination marker
    if (points.length > 1) {
      markers.add(
        Marker(
          point: points.last,
          width: 44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.flag, color: Colors.white, size: 22),
          ),
        ),
      );
    }

    // Current GPS position
    if (_displayPosition != null) {
      markers.add(
        Marker(
          point: _displayPosition!,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.shade400,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Transform.rotate(
              angle: _displayHeading * (math.pi / 180),
              child: const Icon(Icons.navigation, color: Colors.white, size: 20),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.destinationName,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          if (widget.showDownloadButton)
            IconButton(
              icon: _isDownloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _isDownloaded
                          ? Icons.download_done_rounded
                          : Icons.download_rounded,
                    ),
              tooltip: _isDownloaded
                  ? 'Downloaded'
                  : 'Download for offline',
              onPressed: (_isDownloading || _isDownloaded)
                  ? null
                  : _downloadGeneratedRoute,
            ),
          IconButton(
            icon: const Icon(Icons.fit_screen),
            tooltip: 'Fit route',
            onPressed: _centerOnRoute,
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: 12.0,
              minZoom: 5.0,
              maxZoom: 18.0,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && _isAutoFollowEnabled) {
                  setState(() => _isAutoFollowEnabled = false);
                }
              },
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(
                  const LatLng(4.5, 116.0),
                  const LatLng(21.5, 127.0),
                ),
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app.transitph_beta',
              ),
              PolylineLayer(polylines: _polylines),
              MarkerLayer(markers: _markers),
            ],
          ),

          // ── Summary chips (top overlay) ────────────────────────────────────
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(
              children: [
                _summaryChip(
                  Icons.straighten,
                  RouteMetricsService.formatDistanceMeters(
                    widget.result.distanceMeters,
                  ),
                  Colors.green.shade700,
                ),
                const SizedBox(width: 8),
                _summaryChip(
                  Icons.timer_outlined,
                  widget.result.durationLabel,
                  Colors.orange.shade700,
                ),
                const Spacer(),
                // Routing attribution badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Text(
                    '© OSRM\n© OpenStreetMap',
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            left: 12,
            right: 12,
            bottom: 290,
            child: Center(child: _buildStartControl()),
          ),

          // ── My location FAB ────────────────────────────────────────────────
          Positioned(
            right: 12,
            bottom: 240,
            child: FloatingActionButton.small(
              heroTag: 'locate',
              onPressed: _isLocating ? null : _centerOnMe,
              backgroundColor: Colors.white,
              child: _isLocating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.my_location, color: Colors.blue.shade700),
            ),
          ),

          // ── Mode legend (bottom-left) ──────────────────────────────────────
          Positioned(
            left: 12,
            bottom: 240,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.93),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: _activeModes().map((mode) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 18,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _modeColor(mode),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(_modeIcon(mode),
                            size: 13, color: _modeColor(mode)),
                        const SizedBox(width: 4),
                        Text(
                          mode,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _modeColor(mode),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Draggable bottom sheet: turn-by-turn steps ─────────────────────
          DraggableScrollableSheet(
            initialChildSize: 0.28,
            minChildSize: 0.12,
            maxChildSize: 0.65,
            snap: true,
            snapSizes: const [0.12, 0.28, 0.65],
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.turn_right_outlined,
                            color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Turn-by-turn  •  ${widget.result.steps.length} steps',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        // Total fare badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.green.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.payments_outlined,
                                  size: 13,
                                  color: Colors.green.shade700),
                              const SizedBox(width: 4),
                              Text(
                                _totalFareLabel(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Steps list
                  Expanded(
                    child: widget.result.steps.isEmpty
                        ? Center(
                            child: Text(
                              'No step data available',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: widget.result.steps.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, indent: 56),
                            itemBuilder: (context, index) {
                              final step = widget.result.steps[index];
                              final modeColor = _modeColor(step.suggestedMode);
                              return ListTile(
                                dense: true,
                                leading: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: modeColor.withOpacity(0.15),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: modeColor, width: 1.5),
                                      ),
                                      child: Icon(
                                        _modeIcon(step.suggestedMode),
                                        size: 16,
                                        color: modeColor,
                                      ),
                                    ),
                                  ],
                                ),
                                title: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: modeColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        step.suggestedMode,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        step.instruction,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (step.distanceMeters > 0)
                                      Text(
                                        _formatStepDistance(step.distanceMeters),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    if (step.estimatedFare > 0)
                                      Text(
                                        '₱${step.estimatedFare.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartControl() {
    if (!_isNavigationStarted) {
      return ElevatedButton.icon(
        onPressed: _startNavigation,
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: const Text('Start'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _isAutoFollowEnabled = !_isAutoFollowEnabled),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isAutoFollowEnabled
                ? Colors.blue.shade300
                : Colors.grey.shade300,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isAutoFollowEnabled
                  ? Icons.gps_fixed_rounded
                  : Icons.gps_not_fixed_rounded,
              size: 16,
              color: _isAutoFollowEnabled
                  ? Colors.blue.shade700
                  : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              _isAutoFollowEnabled ? 'Following' : 'Follow paused',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _isAutoFollowEnabled
                    ? Colors.blue.shade700
                    : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatStepDistance(double meters) {
    return RouteMetricsService.formatDistanceMeters(meters);
  }

  String _totalFareLabel() {
    final total = widget.result.steps
        .fold(0.0, (sum, s) => sum + s.estimatedFare);
    if (total == 0) return 'Free';
    final low = (total * 0.9).round();
    final high = (total * 1.15).round();
    return '₱$low–$high est.';
  }

  /// Returns only the distinct modes actually used in this route,
  /// preserving the order they first appear — for the legend.
  List<String> _activeModes() {
    final seen = <String>{};
    final modes = <String>[];
    for (final step in widget.result.steps) {
      if (seen.add(step.suggestedMode)) {
        modes.add(step.suggestedMode);
      }
    }
    return modes;
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'Walk':     return Icons.directions_walk;
      case 'Jeepney':  return Icons.directions_bus;
      case 'Bus':      return Icons.directions_bus_filled;
      case 'Train':    return Icons.train;
      case 'Tricycle': return Icons.two_wheeler;
      case 'FX/Van':   return Icons.airport_shuttle;
      case 'Ferry':    return Icons.directions_boat;
      default:         return Icons.directions_bus;
    }
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'Walk':     return Colors.green.shade600;
      case 'Jeepney':  return Colors.blue.shade600;
      case 'Bus':      return Colors.red.shade600;
      case 'Train':    return Colors.purple.shade600;
      case 'Tricycle': return Colors.orange.shade600;
      case 'FX/Van':   return Colors.amber.shade700;
      case 'Ferry':    return Colors.lightBlue.shade600;
      default:         return Colors.blue.shade600;
    }
  }
}