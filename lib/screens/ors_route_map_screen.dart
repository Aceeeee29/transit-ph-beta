import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import '../models/ors_route_result.dart';
import '../repositories/route_cache_repository.dart';
import '../services/offline_tile_service.dart';
import '../services/route_metrics_service.dart';
import '../widgets/fare_discount_toggle.dart';

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

// FIX: Added SingleTickerProviderStateMixin for smooth camera animation
class _OrsRouteMapScreenState extends State<OrsRouteMapScreen>
    with SingleTickerProviderStateMixin {
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
  String? _offlineTileTemplate;
  bool _isDiscountFareEnabled = false;
  bool _hasManualFareDiscountOverride = false;

  // FIX: Smooth camera animation fields
  late final AnimationController _cameraAnimController;
  late final CurvedAnimation _cameraAnim;
  LatLng? _animStartCenter;
  double _animStartZoom = 12.0;
  double _animStartRotation = 0.0;
  LatLng? _animTargetCenter;
  double _animTargetZoom = 12.0;
  double _animTargetRotation = 0.0;

  static const _cacheMode = 'Auto';

  @override
  void initState() {
    super.initState();

    // FIX: Initialise animation controller for buttery-smooth camera moves
    _cameraAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _cameraAnim = CurvedAnimation(
      parent: _cameraAnimController,
      curve: Curves.easeOutCubic,
    );
    _cameraAnimController.addListener(_onCameraAnimTick);

    _initLocation();
    _loadFareProfile();
    _loadDownloadState();
    _loadOfflineTileTemplate();
  }

  Future<void> _loadFareProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snapshot.data();
      if (data == null || !mounted || _hasManualFareDiscountOverride) return;

      final category =
          (data['userCategory'] as String?)?.toLowerCase().trim() ?? '';
      if (!_isStudentCategory(category)) return;
      setState(() => _isDiscountFareEnabled = true);
    } catch (_) {}
  }

  bool _isStudentCategory(String category) =>
      category.replaceAll('_', ' ') == 'student';

  double get _fareDiscountMultiplier => _isDiscountFareEnabled ? 0.8 : 1.0;

  double _applyFareDiscount(double fare) => fare * _fareDiscountMultiplier;

  void _setDiscountEnabled(bool value) {
    setState(() {
      _isDiscountFareEnabled = value;
      _hasManualFareDiscountOverride = true;
    });
  }

  // FIX: Camera animation tick — interpolates lat, lng, zoom, and bearing
  void _onCameraAnimTick() {
    if (_animStartCenter == null || _animTargetCenter == null) return;
    final t = _cameraAnim.value;

    final lat = _lerpDouble(
        _animStartCenter!.latitude, _animTargetCenter!.latitude, t);
    final lng = _lerpDouble(
        _animStartCenter!.longitude, _animTargetCenter!.longitude, t);
    final zoom = _lerpDouble(_animStartZoom, _animTargetZoom, t);
    final rotation = _lerpRotation(_animStartRotation, _animTargetRotation, t);

    _mapController.moveAndRotate(LatLng(lat, lng), zoom, rotation);
  }

  double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  // FIX: Shortest-path rotation lerp — handles wrap-around (e.g. 350° → 10°)
  double _lerpRotation(double a, double b, double t) {
    final diff = (b - a + 540) % 360 - 180;
    return (a + diff * t) % 360;
  }

  // FIX: Smooth animated camera move with bearing support
  void _smoothMoveCamera(
    LatLng target, {
    required double zoom,
    double rotation = 0,
  }) {
    _animStartCenter = _mapController.camera.center;
    _animStartZoom = _mapController.camera.zoom;
    _animStartRotation = _mapController.camera.rotation;
    _animTargetCenter = target;
    _animTargetZoom = zoom;
    _animTargetRotation = rotation;

    _cameraAnimController.stop();
    _cameraAnimController.reset();
    _cameraAnimController.forward();
  }

  Future<void> _loadOfflineTileTemplate() async {
    final template = await OfflineTileService.getLocalTileTemplatePath();
    if (!mounted) return;
    setState(() => _offlineTileTemplate = template);
  }

  Future<void> _loadDownloadState() async {
    final cached = await RouteCacheRepository.get(
      widget.originName,
      widget.destinationName,
      _cacheMode,
      RouteCacheRepository.generatedRouteProfile,
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
        RouteCacheRepository.generatedRouteProfile,
        widget.result,
      );
      await OfflineTileService.cacheRouteTiles(widget.result.polyline);
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
    if (mounted) setState(() => _isLocating = false);
  }

  // FIX: Platform-aware stream settings — Android gets intervalDuration to
  // suppress jitter callbacks; distanceFilter raised 2 → 3 m to further
  // reduce spurious updates while keeping movement feeling live.
  void _startLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 3,
              intervalDuration: const Duration(milliseconds: 800),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 3,
            ),
    ).listen(
      _handleLocationUpdate,
      onError: (_) {},
    );
  }

  // FIX: Replaced undefined `nextDisplay` with `raw`.
  // FIX: Passes heading to _maybeMoveCamera for map bearing rotation.
  void _handleLocationUpdate(Position position) {
    if (!mounted) return;
    // FIX: Slightly relaxed accuracy gate (45 → 50) to keep updates flowing
    // in challenging environments while still rejecting wild outliers.
    if (position.accuracy > 50) return;

    final raw = LatLng(position.latitude, position.longitude);
    final nextHeading = _normalizeHeading(position.heading);

    setState(() {
      _currentPosition = position;
      _displayPosition = raw;
      _displayHeading = nextHeading;
    });

    if (_isNavigationStarted && _isAutoFollowEnabled) {
      // FIX: Was `nextDisplay` (undefined) — now correctly passes `raw`
      _maybeMoveCamera(raw, heading: nextHeading);
    }
  }

  // FIX: Throttle 450 ms → 120 ms, dead zone 2.5 m → 1.0 m.
  // FIX: Accepts heading so the map rotates to keep travel direction up,
  //      matching Google Maps / Waze behaviour.
  void _maybeMoveCamera(LatLng target, {double heading = 0}) {
    final now = DateTime.now();

    if (_lastCameraMoveAt != null &&
        now.difference(_lastCameraMoveAt!).inMilliseconds < 120) {
      return;
    }
    if (_lastCameraTarget != null &&
        const Distance().as(LengthUnit.Meter, _lastCameraTarget!, target) <
            1.0) {
      return;
    }

    _lastCameraMoveAt = now;
    _lastCameraTarget = target;

    final targetZoom =
        _mapController.camera.zoom < 16 ? 16.0 : _mapController.camera.zoom;
    // Negate heading: rotating the map -heading° puts travel direction at top
    final targetRotation = -heading;

    _smoothMoveCamera(target, zoom: targetZoom, rotation: targetRotation);
  }

  double _normalizeHeading(double heading) {
    if (!heading.isFinite || heading < 0) return _displayHeading;
    final value = heading % 360;
    return value < 0 ? value + 360 : value;
  }

  @override
  void dispose() {
    _cameraAnim.dispose();
    _cameraAnimController.dispose();
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
    // FIX: Smooth animated move, reset bearing to north when fitting route
    _smoothMoveCamera(center, zoom: 13.0, rotation: 0);
  }

  void _centerOnMe() {
    if (_displayPosition == null) return;
    if (_isNavigationStarted && !_isAutoFollowEnabled) {
      setState(() => _isAutoFollowEnabled = true);
    }
    // FIX: Smooth move + apply current heading as bearing
    _smoothMoveCamera(
      _displayPosition!,
      zoom: 16.0,
      rotation: -_displayHeading,
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
    if (points.isEmpty) return const LatLng(14.5995, 120.9842);
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

      polylines.add(Polyline(
        points: segmentPoints,
        color: Colors.white,
        strokeWidth: 8.0,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      ));

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
              tooltip:
                  _isDownloaded ? 'Downloaded' : 'Download for offline',
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
          // ── Map ──────────────────────────────────────────────────────────────
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
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName:
                    'com.example.app.transitph_beta',
              ),
              if (_offlineTileTemplate != null)
                TileLayer(
                  urlTemplate: _offlineTileTemplate!,
                  tileProvider: FileTileProvider(),
                ),
              PolylineLayer(polylines: _polylines),
              MarkerLayer(markers: _markers),
            ],
          ),

          // ── Summary chips (top overlay) ──────────────────────────────────────
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
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
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
                    style: TextStyle(
                        fontSize: 9, color: Colors.grey.shade700),
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

          // ── My location FAB ──────────────────────────────────────────────────
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

          // ── Mode legend (bottom-left) ────────────────────────────────────────
          Positioned(
            left: 12,
            bottom: 240,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
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

          // ── Draggable bottom sheet: turn-by-turn steps ───────────────────────
          DraggableScrollableSheet(
            initialChildSize: 0.28,
            minChildSize: 0.12,
            maxChildSize: 0.65,
            snap: true,
            snapSizes: const [0.12, 0.28, 0.65],
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20)),
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
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.green.shade300),
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
                  if (_hasFareSteps) ...[
                    const SizedBox(height: 8),
                    FareDiscountToggle(
                      value: _isDiscountFareEnabled,
                      onChanged: _setDiscountEnabled,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      labelStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                      iconColor: Colors.grey,
                      iconSize: 15,
                      activeColor: Colors.blue.shade700,
                    ),
                  ],
                  const Divider(height: 1),
                  Expanded(
                    child: widget.result.steps.isEmpty
                        ? Center(
                            child: Text(
                              'No step data available',
                              style: TextStyle(
                                  color: Colors.grey.shade500),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                                vertical: 8),
                            itemCount: widget.result.steps.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, indent: 56),
                            itemBuilder: (context, index) {
                              final step =
                                  widget.result.steps[index];
                              final modeColor =
                                  _modeColor(step.suggestedMode);
                              return ListTile(
                                dense: true,
                                leading: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: modeColor
                                            .withOpacity(0.15),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: modeColor,
                                            width: 1.5),
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
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2),
                                      decoration: BoxDecoration(
                                        color: modeColor,
                                        borderRadius:
                                            BorderRadius.circular(4),
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
                                        style: const TextStyle(
                                            fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    if (step.distanceMeters > 0)
                                      Text(
                                        _formatStepDistance(
                                            step.distanceMeters),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    if (step.estimatedFare > 0)
                                      Text(
                                        '₱${_applyFareDiscount(step.estimatedFare).toStringAsFixed(0)}',
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
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      );
    }

    return GestureDetector(
      onTap: () =>
          setState(() => _isAutoFollowEnabled = !_isAutoFollowEnabled),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
    final baseTotal =
        widget.result.steps.fold(0.0, (sum, s) => sum + s.estimatedFare);
    if (baseTotal == 0) return 'Free';
    final total = _applyFareDiscount(baseTotal);
    final low = (total * 0.9).round();
    final high = (total * 1.15).round();
    return '₱$low–$high est.';
  }

  bool get _hasFareSteps => widget.result.steps
      .any((step) => step.estimatedFare > 0 && step.suggestedMode != 'Walk');

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
      case 'Walk':
        return Icons.directions_walk;
      case 'Jeepney':
        return Icons.directions_bus;
      case 'Bus':
        return Icons.directions_bus_filled;
      case 'Train':
        return Icons.train;
      case 'Tricycle':
        return Icons.two_wheeler;
      case 'FX/Van':
        return Icons.airport_shuttle;
      case 'Ferry':
        return Icons.directions_boat;
      default:
        return Icons.directions_bus;
    }
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'Walk':
        return Colors.green.shade600;
      case 'Jeepney':
        return Colors.blue.shade600;
      case 'Bus':
        return Colors.red.shade600;
      case 'Train':
        return Colors.purple.shade600;
      case 'Tricycle':
        return Colors.orange.shade600;
      case 'FX/Van':
        return Colors.amber.shade700;
      case 'Ferry':
        return Colors.lightBlue.shade600;
      default:
        return Colors.blue.shade600;
    }
  }
}