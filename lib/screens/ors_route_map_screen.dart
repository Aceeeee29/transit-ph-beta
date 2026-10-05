import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../models/ors_route_result.dart';
import '../repositories/route_cache_repository.dart';
import '../services/active_navigation_service.dart';
import '../services/offline_tile_service.dart';
import '../services/route_follow_engine.dart';
import '../services/route_follow_guidance.dart';
import '../services/route_metrics_service.dart';
import '../widgets/community_route_badge.dart';
import '../widgets/fare_discount_toggle.dart';
import '../widgets/location_permission_notice.dart';
import '../widgets/route_map/follow_guidance_card.dart';
import '../widgets/route_map/follow_route_layers.dart';
import '../widgets/route_map/follow_simulator_sheet.dart';
import '../widgets/route_map/ride_correction_flow.dart';
import '../widgets/route_map/user_location_layer.dart';
import '../widgets/translated_text.dart';

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
      // About one GPS interval, linear, so back-to-back follow moves blend
      // into continuous motion instead of stop-start hops.
      duration: const Duration(milliseconds: 900),
    );
    _cameraAnim = CurvedAnimation(
      parent: _cameraAnimController,
      curve: Curves.linear,
    );
    _cameraAnimController.addListener(_onCameraAnimTick);

    final navigation = ActiveNavigationService.instance;
    navigation.addListener(_onNavigationSessionChanged);
    navigation.followUpdates.addListener(_onNavigationPosition);
    if (_isNavigationStarted) {
      _isAutoFollowEnabled = true;
      // Reopening a session that paused itself for being idle resumes it.
      navigation.resumeTracking();
    }

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

  String get _followId => FollowTarget.generatedId(
    widget.result,
    widget.originName,
    widget.destinationName,
  );

  /// True while this route is the active follow session; the session (GPS,
  /// progress, guidance, arrival) lives in [ActiveNavigationService].
  bool get _isNavigationStarted =>
      ActiveNavigationService.instance.isFollowing(_followId);

  RouteFollowSnapshot? get _followSnapshot =>
      _isNavigationStarted
          ? ActiveNavigationService.instance.followSnapshot
          : null;

  bool get _hasArrived => _followSnapshot?.hasArrived ?? false;

  FollowGuidance get _guidance =>
      _isNavigationStarted
          ? ActiveNavigationService.instance.guidance
          : FollowGuidance.none;

  Future<void> _initLocation() async {
    setState(() => _isLocating = true);
    final hasAccess = await ensureLocationAccess(
      context,
      reason: 'show where you are on the route',
    );
    if (hasAccess) {
      if (_isNavigationStarted &&
          ActiveNavigationService.instance.lastPosition != null) {
        // Resuming an active session: its stream already tracks the user.
        _onNavigationPosition();
      } else {
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );
          if (mounted) {
            _applyPosition(position, _rawLatLng(position));
            if (!_isNavigationStarted) _startLocationTracking();
          }
        } catch (_) {}
      }
    }
    if (mounted) setState(() => _isLocating = false);
  }

  /// Preview-only stream for showing the user's location before Start.
  /// While following, positions come from the navigation session instead.
  void _startLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: ActiveNavigationService.trackingSettings,
    ).listen(_handleLocationUpdate, onError: (_) {});
  }

  void _stopLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _handleLocationUpdate(Position position) {
    if (!mounted) return;
    if (position.accuracy >
        ActiveNavigationService.maxAcceptedAccuracyMeters) {
      return;
    }
    setState(() => _applyPosition(position, _rawLatLng(position)));
  }

  void _onNavigationPosition() {
    if (!mounted || !_isNavigationStarted) return;
    final position = ActiveNavigationService.instance.lastPosition;
    if (position == null) {
      setState(() {});
      return;
    }
    final display = _followSnapshot?.displayPosition ?? _rawLatLng(position);
    setState(() => _applyPosition(position, display));
    if (_isAutoFollowEnabled && !_hasArrived) {
      _maybeMoveCamera(display, heading: _displayHeading);
    }
  }

  void _onNavigationSessionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  LatLng _rawLatLng(Position position) =>
      LatLng(position.latitude, position.longitude);

  static const _minHeadingSpeedMps = 1.0;

  /// How close the camera follows: street level on foot, a little wider at
  /// vehicle speed so more of the road ahead shows.
  double get _followZoom =>
      (_currentPosition?.speed ?? 0) > _vehicleZoomSpeedMps ? 16.5 : 17.5;
  static const _vehicleZoomSpeedMps = 6.0;

  void _applyPosition(Position position, LatLng display) {
    _currentPosition = position;
    _displayPosition = display;
    // GPS heading is noise when barely moving; keep the last good heading.
    if (position.speed >= _minHeadingSpeedMps) {
      _displayHeading = _normalizeHeading(position.heading);
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
        _followZoom;
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
    final navigation = ActiveNavigationService.instance;
    navigation.removeListener(_onNavigationSessionChanged);
    navigation.followUpdates.removeListener(_onNavigationPosition);
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
      zoom: _followZoom,
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

    // The session's stream takes over from the preview stream.
    _stopLocationTracking();
    _isAutoFollowEnabled = true;
    ActiveNavigationService.instance.start(
      FollowTarget.generated(
        widget.result,
        originName: widget.originName,
        destinationName: widget.destinationName,
      ),
      initialPosition: _currentPosition,
      enableRouteIntegrity: false,
      showDownloadButton: widget.showDownloadButton,
    );
    _onNavigationPosition();
    _centerOnMe();
  }

  Future<void> _stopNavigation() async {
    final shouldStop = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const TranslatedText('Stop this route?'),
            content: const TranslatedText(
              'Your progress along the route will be cleared. You can start again anytime.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const TranslatedText('Keep Going'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const TranslatedText('Stop Route'),
              ),
            ],
          ),
    );
    if (!mounted || shouldStop != true) return;
    await _endNavigationAndOfferCorrection();
  }

  /// Ends the session, then — if the vehicle went a different way than this
  /// route — offers to save the ride as a new route.
  Future<void> _endNavigationAndOfferCorrection() async {
    final deviations = ActiveNavigationService.instance.finishDeviations();
    _endNavigation();
    if (!mounted) return;
    await RideCorrectionFlow.offer(
      context,
      deviations: deviations,
      followedPath: widget.result.polyline,
      generated: widget.result,
      originName: widget.originName,
      destinationName: widget.destinationName,
    );
  }

  void _endNavigation() {
    ActiveNavigationService.instance.stop();
    setState(() {
      _isAutoFollowEnabled = false;
      final position = _currentPosition;
      if (position != null) _displayPosition = _rawLatLng(position);
    });
    _startLocationTracking();
  }

  LatLng get _mapCenter {
    final points = widget.result.polyline;
    if (points.isEmpty) return const LatLng(14.5995, 120.9842);
    return LatLng(
      (points.first.latitude + points.last.latitude) / 2,
      (points.first.longitude + points.last.longitude) / 2,
    );
  }

  /// One colored range per step, sliced from the full geometry using the
  /// way_point indices; the whole line in blue when steps carry none.
  List<({int start, int end, Color color})> get _stepRanges {
    final last = widget.result.polyline.length - 1;
    final steps = widget.result.steps;
    if (steps.isEmpty || steps.every((s) => s.wayPointEnd == 0)) {
      return [(start: 0, end: last, color: Colors.blue.shade700)];
    }
    return [
      for (final step in steps)
        (
          start: step.wayPointStart,
          end: step.wayPointEnd,
          color: _modeColor(step.suggestedMode),
        ),
    ];
  }

  /// The route (travelled part grey while following) plus, when the
  /// traveler is off it, the dashed temporary path back to it.
  List<Polyline> get _polylines {
    return [
      ...FollowRouteLayers.routeLines(
        path: widget.result.polyline,
        ranges: _stepRanges,
        snapshot: _followSnapshot,
        outline: Colors.white,
        fillWidth: 5.5,
      ),
      if (_isNavigationStarted) ...[
        ...FollowRouteLayers.connectorLines(
          ActiveNavigationService.instance.connectorPath,
        ),
        ...FollowRouteLayers.detourLines(
          ActiveNavigationService.instance.detourPath,
        ),
      ],
    ];
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

    final targetMarker = FollowRouteLayers.targetMarker(_guidance);
    if (targetMarker != null) markers.add(targetMarker);

    return markers;
  }

  /// The traveler's dot, drawn above every other layer.
  Widget get _userLocationLayer => UserLocationLayer(
    position: _displayPosition,
    accuracyMeters: _currentPosition?.accuracy ?? 0,
    headingDegrees: _displayHeading,
    speedMps: _currentPosition?.speed ?? 0,
  );

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
              _userLocationLayer,
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

          // Same layout as a saved route's map: guidance above the controls,
          // Start/Stop bottom-left, GPS bottom-right, legend top-right.
          if (_guidance.kind != FollowGuidanceKind.none)
            Positioned(
              left: 12,
              right: 64,
              bottom: 342,
              child: FollowGuidanceCard(
                guidance: _guidance,
                remainingMeters:
                    ActiveNavigationService.instance.connectorRemainingMeters,
                isRerouting: ActiveNavigationService.instance.isRerouting,
                routeStartLabel: widget.originName,
              ),
            ),

          Positioned(
            left: 12,
            bottom: 290,
            child: _buildStartControl(),
          ),

          if (kDebugMode && _isNavigationStarted && !_hasArrived)
            Positioned(
              right: 12,
              bottom: 342,
              child: FollowSimulatorButton(path: widget.result.polyline),
            ),

          // ── My location: re-centres, and resumes following ────────────────
          Positioned(right: 12, bottom: 290, child: _buildCenterButton()),

          // ── Mode legend (top-right) ──────────────────────────────────────────
          Positioned(
            right: 12,
            top: 60,
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
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            step.instruction,
                                            style: const TextStyle(
                                                fontSize: 13),
                                          ),
                                          if (step.isCommunity) ...[
                                            const SizedBox(height: 3),
                                            const CommunityRouteBadge(),
                                          ],
                                        ],
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
    if (_hasArrived) return _buildArrivalCard();
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

    // Re-centring and resuming follow is the GPS button on the right.
    return GestureDetector(
      onTap: _stopNavigation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.stop_rounded, size: 16, color: Colors.red.shade600),
            const SizedBox(width: 6),
            TranslatedText(
              'Stop',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Re-centres on the traveler; while following it also resumes the
  /// camera follow, and shows solid blue while the camera is following.
  Widget _buildCenterButton() {
    final following = _isNavigationStarted && _isAutoFollowEnabled;
    final accent = Colors.blue.shade700;
    return GestureDetector(
      onTap: _isLocating ? null : _centerOnMe,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: following ? accent : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: following ? accent : Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child:
            _isLocating
                ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Icon(
                  following ? Icons.navigation_rounded : Icons.my_location,
                  color: following ? Colors.white : accent,
                  size: 20,
                ),
      ),
    );
  }

  /// Shown in place of the follow controls once the end is reached.
  Widget _buildArrivalCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: Colors.green.shade600),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const TranslatedText(
                  "You've arrived",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                Text(
                  widget.destinationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _endNavigationAndOfferCorrection,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 36),
            ),
            child: const TranslatedText('Done'),
          ),
        ],
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