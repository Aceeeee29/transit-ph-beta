import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../widgets/map/map_pin_images.dart';
import '../widgets/map/transit_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../models/ors_route_result.dart';
import '../models/route_issue_report.dart';
import '../services/route_report_service.dart';
import '../widgets/route_map/route_report_banner.dart';
import '../widgets/route_map/route_report_dialog.dart';
import '../services/gamification_service.dart';
import '../repositories/route_cache_repository.dart';
import '../services/active_navigation_service.dart';
import '../services/fare_matrix.dart';
import '../services/fare_profile_service.dart';
import '../services/offline_tile_service.dart';
import '../services/route_guide.dart';
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
import '../services/osm_places.dart';
import '../services/facing.dart';
import '../widgets/translated_text.dart';
import '../data/camanava_places.dart';
import '../models/place.dart';
import '../services/map_tab_controller.dart';
import '../widgets/map_tab/map_drawer.dart';
import '../widgets/map_tab/map_side_button.dart';
import '../widgets/route_map/follow_leg_card.dart';
import '../widgets/route_map/route_modes.dart';
import '../widgets/map_tab/place_widgets.dart';
import '../widgets/map_tab/route_view_widgets.dart';
import '../theme/app_colors.dart';

/// Displays an ORS-generated route on an interactive map.
/// Shows the road-snapped polyline, start/end markers, current location,
/// and a draggable bottom sheet with distance, duration, and turn-by-turn steps.
class OrsRouteMapScreen extends StatefulWidget {
  final OrsRouteResult result;
  final String originName;
  final String destinationName;
  final bool showDownloadButton;

  /// Back to the map. Without it, back pops this page.
  final VoidCallback? onClose;

  const OrsRouteMapScreen({
    super.key,
    required this.result,
    required this.originName,
    required this.destinationName,
    this.showDownloadButton = true,
    this.onClose,
  });

  @override
  State<OrsRouteMapScreen> createState() => _OrsRouteMapScreenState();
}

class _OrsRouteMapScreenState extends State<OrsRouteMapScreen> {
  final _map = TransitMapController();

  /// Leaning into 3D: on by itself while following, or by the 2D/3D button.
  bool _tilted = false;

  /// Our places, then OpenStreetMap's once read.
  List<Place> _allPlaces = camanavaPlaces;
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  LatLng? _displayPosition;
  double _displayHeading = 0;

  /// Which way the traveler faces; turns the arrow and, while following,
  /// the map.
  final _facing = Facing();
  DateTime _lastTurnAt = DateTime(0);
  LatLng? _lastCameraTarget;
  DateTime? _lastCameraMoveAt;
  bool _isLocating = false;
  bool _isAutoFollowEnabled = false;
  bool _isDownloaded = false;
  bool _isDownloading = false;
  bool _isDiscountFareEnabled = false;
  bool _hasManualFareDiscountOverride = false;

  // ─── Map chrome (drawer, place pins) ──────────────────────────────────────
  final DraggableScrollableController _drawerController =
      DraggableScrollableController();
  Place? _selectedPlace;

  /// Taller before Start: the Start button and the guide's credit.
  double get _drawerPeekHeight => RouteDrawerHeader.peekHeight(
    showsButton: !_isNavigationStarted || _hasArrived,
    byline: !_isNavigationStarted,
  );

  /// Start pressed before the first GPS fix: following begins on the fix.
  bool _isStarting = false;
  Timer? _startTimeout;

  static const _cacheMode = 'Auto';

  @override
  void initState() {
    super.initState();

    final navigation = ActiveNavigationService.instance;
    navigation.addListener(_onNavigationSessionChanged);
    navigation.followUpdates.addListener(_onNavigationPosition);
    if (_isNavigationStarted) {
      _isAutoFollowEnabled = true;
      _tilted = true;
      // Reopening a session that paused itself for being idle resumes it.
      navigation.resumeTracking();
    }
    MapTabController.instance.placeCategories.addListener(_onSharedMapState);
    MapTabController.instance.showPins.addListener(_onSharedMapState);
    _facing
      ..start()
      ..addListener(_onFacingChanged);
    OsmPlaces.all().then((places) {
      if (mounted) setState(() => _allPlaces = places);
    });

    _initLocation();
    _loadFareProfile();
    _loadDownloadState();
    RouteReportService.affecting(widget.result.polyline).then((reports) {
      if (mounted && reports.isNotEmpty) {
        setState(() => _roadReports = reports);
      }
    });
  }

  /// Riders' reports on the roads this trip rides.
  List<RouteIssueReport> _roadReports = const [];

  void _showReportDialog() {
    showRouteReportDialog(context, onSubmit: _submitReport);
  }

  /// Same as on a community route: the report is filed on this trip's line,
  /// so it shows on every route sharing the road and their contributors
  /// are told.
  Future<void> _submitReport(String type, String description) async {
    final RouteIssueReport report;
    try {
      report = await RouteReportService.submit(
        routeId: 'generated',
        routeLabel: '${widget.originName} → ${widget.destinationName}',
        path: widget.result.polyline,
        type: type,
        description: description.isNotEmpty ? description : null,
      );
    } catch (e) {
      debugPrint('[RouteReports] Submit failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't send the report. Check your connection."),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _roadReports = [..._roadReports, report]);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report sent. Riders on this road will see it.'),
      ),
    );
    final user = await GamificationService.loadUser();
    await GamificationService.incrementReportsSubmitted(user);
  }

  Future<void> _loadFareProfile() async {
    final student = await FareProfileService.isStudent();
    if (!student || !mounted || _hasManualFareDiscountOverride) return;
    setState(() => _isDiscountFareEnabled = true);
  }

  /// Jeepney and bus rides only.
  double _applyFareDiscount(double fare, String mode) =>
      PhFareCalculator.rideFare(fare, mode, discount: _isDiscountFareEnabled);

  void _setDiscountEnabled(bool value) {
    setState(() {
      _isDiscountFareEnabled = value;
      _hasManualFareDiscountOverride = true;
    });
  }

  /// How far the camera leans in 3D, in degrees.
  static const _tilt3d = 55.0;

  /// Moves the camera to [target], turned so [bearing] is up. About one GPS
  /// interval at a constant speed, so back-to-back follow moves blend into
  /// continuous motion instead of stop-start hops.
  void _smoothMoveCamera(
    LatLng target, {
    required double zoom,
    double bearing = 0,
  }) {
    _map.follow(
      target,
      zoom: zoom,
      bearing: bearing,
      tilt: _tilted ? _tilt3d : 0,
    );
  }

  /// Where the traveler faces (compass on foot, road on a ride); the last
  /// GPS direction until the compass reports.
  double get _heading => _facing.value ?? _displayHeading;

  /// Turning on the spot turns the map too while following, a few times a
  /// second at most.
  void _onFacingChanged() {
    final heading = _facing.value;
    if (heading == null ||
        !_isNavigationStarted ||
        !_isAutoFollowEnabled ||
        _hasArrived) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastTurnAt).inMilliseconds < 200) return;
    final bearing = _map.camera?.bearing;
    if (bearing != null && Facing.difference(bearing, heading).abs() < 4) {
      return;
    }
    _lastTurnAt = now;
    _map.turnTo(heading);
  }

  /// The 2D/3D button.
  void _toggleTilt() {
    setState(() => _tilted = !_tilted);
    _map.tiltTo(_tilted ? _tilt3d : 0);
  }

  /// Keeps the 2D/3D button in step with a tilt by hand. Following sets
  /// the tilt itself, and a gesture stops following first.
  void _onMapCameraIdle(TransitMapCamera camera) {
    if (_isNavigationStarted) return;
    final tilted = camera.tilt > 5;
    if (tilted != _tilted && mounted) setState(() => _tilted = tilted);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to download route: $e')));
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
            _startIfWaiting();
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
    if (position.accuracy > ActiveNavigationService.maxAcceptedAccuracyMeters) {
      return;
    }
    setState(() => _applyPosition(position, _rawLatLng(position)));
    _startIfWaiting();
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
      _maybeMoveCamera(display, heading: _heading);
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
    _facing.onFix(position);
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

    // Turned so the travel direction is up.
    _smoothMoveCamera(target, zoom: _followZoom, bearing: heading);
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
    MapTabController.instance.placeCategories.removeListener(_onSharedMapState);
    MapTabController.instance.showPins.removeListener(_onSharedMapState);
    _drawerController.dispose();
    _startTimeout?.cancel();
    _facing.dispose();
    _positionSubscription?.cancel();
    super.dispose();
  }

  /// The whole route in view. While following, the camera stops tracking
  /// until the location button is pressed.
  void _showWholeRoute() {
    final points = widget.result.polyline;
    if (points.isEmpty) return;
    if (_isAutoFollowEnabled) setState(() => _isAutoFollowEnabled = false);
    _map.fitPoints(
      points,
      padding: EdgeInsets.fromLTRB(
        40,
        _isNavigationStarted ? 190 : 90,
        40,
        _drawerPeekHeight + 40,
      ),
      flat: true,
    );
  }

  void _centerOnMe() {
    if (_displayPosition == null) return;
    if (_isNavigationStarted && !_isAutoFollowEnabled) {
      setState(() => _isAutoFollowEnabled = true);
    }
    _smoothMoveCamera(_displayPosition!, zoom: _followZoom, bearing: _heading);
  }

  /// Start: right away with a location, otherwise as soon as one arrives.
  void _startNavigation() {
    if (_displayPosition == null) {
      _waitForLocationThenStart();
      return;
    }
    _beginFollowing();
  }

  void _waitForLocationThenStart() {
    if (_isStarting) return;
    setState(() => _isStarting = true);
    _startTimeout?.cancel();
    _startTimeout = Timer(const Duration(seconds: 30), () {
      if (!mounted || !_isStarting) return;
      setState(() => _isStarting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't get your location. Check that location is on, then "
            'press Start again.',
          ),
        ),
      );
    });
    if (_positionSubscription == null && !_isLocating) _initLocation();
  }

  /// A fix arrived while Start waits for one.
  void _startIfWaiting() {
    if (_isStarting && _displayPosition != null && !_isNavigationStarted) {
      _beginFollowing();
    }
  }

  void _beginFollowing() {
    _startTimeout?.cancel();
    _isStarting = false;
    // The session's stream takes over from the preview stream.
    _stopLocationTracking();
    _isAutoFollowEnabled = true;
    // Following leans the map into 3D, the road ahead in view.
    _tilted = true;
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
      _tilted = false;
      final position = _currentPosition;
      if (position != null) _displayPosition = _rawLatLng(position);
    });
    // Flat and north up again.
    final here = _displayPosition ?? _map.camera?.center;
    if (here != null) _map.moveTo(here, bearing: 0, tilt: 0);
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
          color: RouteModes.color(step.suggestedMode),
        ),
    ];
  }

  /// Indexes in [_stepRanges] of walks with no real path found.
  Set<int> get _estimatedWalkRanges {
    final steps = widget.result.steps;
    if (steps.every((s) => s.wayPointEnd == 0)) return const {};
    return {
      for (final (index, step) in steps.indexed)
        if (step.isEstimatedPath) index,
    };
  }

  /// The route (travelled part grey while following) plus, when the
  /// traveler is off it, the dashed temporary path back to it.
  List<MapLine> get _lines {
    return [
      ...FollowRouteLayers.routeLines(
        path: widget.result.polyline,
        ranges: _stepRanges,
        snapshot: _followSnapshot,
        outline: Colors.white,
        fillWidth: 5.5,
        estimated: _estimatedWalkRanges,
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

  /// The end pin.
  List<MapIcon> get _icons {
    final points = widget.result.polyline;
    return [
      if (points.length > 1)
        MapIcon(points.last, MapPinImages.tripEnd, anchorBottom: true),
    ];
  }

  /// The start, each mode switch, and the next point to reach while
  /// following.
  List<MapDot> get _dots {
    final points = widget.result.polyline;
    final target = FollowRouteLayers.targetDot(_guidance);
    return [
      if (points.isNotEmpty) FollowRouteLayers.startDot(points.first),
      ...FollowRouteLayers.modeSwitchDots(points, _stepRanges),
      if (target != null) target,
    ];
  }

  /// The traveler's arrow, drawn above every other layer. It turns with
  /// [_facing]; without a compass, with the GPS direction while moving
  /// (a dot when standing).
  MapUser? get _mapUser {
    final at = _displayPosition;
    if (at == null) return null;
    final speed = _currentPosition?.speed ?? 0;
    return MapUser(
      at,
      accuracyMeters: _currentPosition?.accuracy ?? 0,
      headingDegrees: speed >= _minHeadingSpeedMps ? _displayHeading : null,
      speedMps: speed,
    );
  }

  // ─── Map-tab chrome ────────────────────────────────────────────────────────

  /// The place pins: every place, the chips' categories highlighted.
  MapPlaces get _mapPlaces => MapPlaces(
    places: MapTabController.instance.showPins.value ? _allPlaces : const [],
    highlighted: MapTabController.instance.placeCategories.value,
    selected: _selectedPlace,
  );

  void _onPlaceTapped(Place place) {
    setState(() => _selectedPlace = place);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MapDrawer.open(_drawerController);
    });
  }

  void _clearSelectedPlace() {
    if (_selectedPlace != null) setState(() => _selectedPlace = null);
  }

  void _onSharedMapState() {
    if (mounted) setState(() {});
  }

  /// Back to the map (or out of this page when opened on its own).
  void _closeView() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  double? _distanceToPlace(Place place) {
    final here = _displayPosition;
    if (here == null) return null;
    return const Distance(
      roundResult: false,
    ).as(LengthUnit.Kilometer, here, LatLng(place.lat, place.lng));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            _buildMap(),
            _buildTopOverlay(),
            if (kDebugMode && _isNavigationStarted && !_hasArrived)
              Positioned(
                left: 12,
                bottom: _drawerPeekHeight + 12,
                child: FollowSimulatorButton(path: widget.result.polyline),
              ),
            _buildSideButtons(),
            _buildDrawer(),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    // Place pins sit under the route and its markers; the traveler's dot
    // on top of everything.
    return TransitMap(
      controller: _map,
      initialCenter: _mapCenter,
      initialZoom: 12.0,
      minZoom: 5.0,
      maxZoom: 18.0,
      bounds: (
        southWest: const LatLng(4.5, 116.0),
        northEast: const LatLng(21.5, 127.0),
      ),
      // Zooming out stops at Metro Manila (with all of the route and the
      // traveler), as on the Map tab.
      keepInside: TransitMap.areaWith(TransitMap.metroManila, [
        ...widget.result.polyline,
        _displayPosition,
      ]),
      keepInsidePadding: EdgeInsets.fromLTRB(
        16,
        120,
        16,
        _drawerPeekHeight + 16,
      ),
      places: _mapPlaces,
      lines: _lines,
      dots: _dots,
      icons: _icons,
      user: _mapUser,
      userHeading: _facing,
      onTap: (_) => _clearSelectedPlace(),
      onPlaceTap: _onPlaceTapped,
      onUserGesture: () {
        if (_isAutoFollowEnabled) {
          setState(() => _isAutoFollowEnabled = false);
        }
      },
      onCameraIdle: _onMapCameraIdle,
      // Below the top bar, or the taller step card while following.
      compassMargin: math.Point(16, _isFollowingNow ? 200 : 80),
      attributionMargin: math.Point(8, _drawerPeekHeight + 8),
    );
  }

  /// Following and not yet arrived: the step card and no tabs.
  bool get _isFollowingNow => _isNavigationStarted && !_hasArrived;

  /// The step being travelled, for the top card.
  FollowLegInfo _legInfo(int index) {
    final steps = widget.result.steps;
    final step = steps[index];
    final isLast = index == steps.length - 1;
    final to = step.toName ?? (isLast ? widget.destinationName : null);
    final isWalk = step.suggestedMode == 'Walk';
    final fare =
        isWalk || step.estimatedFare <= 0
            ? null
            : '₱${_applyFareDiscount(step.estimatedFare, step.suggestedMode).round()}';
    return FollowLegInfo(
      mode: step.suggestedMode,
      headline:
          to != null
              ? '${isWalk ? 'Walk' : 'Ride'} to $to'
              : step.instruction.replaceFirst('[Estimated] ', ''),
      from: step.fromName,
      fare: fare,
    );
  }

  /// The card while following; how to get back to the route replaces the
  /// step while off it.
  Widget? _buildLegCard() {
    final steps = widget.result.steps;
    if (steps.isEmpty) return null;
    final navigation = ActiveNavigationService.instance;
    final progress = navigation.legProgress;
    final index = progress?.index ?? 0;
    final next =
        index + 1 < steps.length
            ? _legInfo(index + 1).headline
            : 'Arrive at ${widget.destinationName}';
    final followSteps = navigation.activeTarget?.steps ?? const <FollowStep>[];
    return FollowLegCard(
      leg: _legInfo(index),
      metersLeft: progress?.metersLeft ?? steps[index].distanceMeters,
      next: next,
      getOffSoon:
          progress != null &&
          _guidance.kind == FollowGuidanceKind.none &&
          progress.isGetOffSoon(followSteps),
      getOffName: steps[index].toName,
      guidance:
          _guidance.kind == FollowGuidanceKind.none
              ? null
              : FollowGuidanceCard(
                guidance: _guidance,
                remainingMeters: navigation.connectorRemainingMeters,
                isRerouting: navigation.isRerouting,
                routeStartLabel: widget.originName,
              ),
    );
  }

  Widget _buildTopOverlay() {
    // Following: the step being travelled takes the top bar's place.
    final legCard = _isFollowingNow ? _buildLegCard() : null;
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child:
          legCard ??
          RouteTopBar(
            from: widget.originName,
            to: widget.destinationName,
            onBack: _closeView,
          ),
    );
  }

  Widget _buildSideButtons() {
    final pins = MapTabController.instance.showPins;
    final following = _isNavigationStarted && _isAutoFollowEnabled;
    const accent = Color(0xFF0B8FD6);
    return Positioned(
      right: 12,
      bottom: _drawerPeekHeight + 12,
      child: MapSideButtons(
        children: [
          MapSideButton(
            icon: Icons.report_problem_rounded,
            tooltip: 'Report a problem with this route',
            iconColor: const Color(0xFFE05C6A),
            onTap: _showReportDialog,
          ),
          MapSideButton(
            icon: Icons.view_in_ar_rounded,
            tooltip: _tilted ? 'Flat view' : '3D view',
            active: _tilted,
            iconColor: accent,
            onTap: _toggleTilt,
          ),
          MapSideButton(
            icon:
                pins.value
                    ? Icons.location_on_rounded
                    : Icons.location_off_rounded,
            tooltip: pins.value ? 'Hide pins' : 'Show pins',
            iconColor: pins.value ? accent : null,
            onTap: () => pins.value = !pins.value,
          ),
          MapSideButton(
            icon:
                following
                    ? Icons.navigation_rounded
                    : Icons.my_location_rounded,
            tooltip:
                following ? 'Following your location' : 'Center on my location',
            iconColor: accent,
            active: following,
            busy: _isLocating,
            onTap: _isLocating ? null : _centerOnMe,
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    final place = _selectedPlace;
    final snapshot = _followSnapshot;
    final int minutes;
    final double meters;
    if (snapshot != null && snapshot.hasProgress) {
      // Time left scales the route's estimate by the distance left.
      final total = widget.result.distanceMeters;
      final share = total > 0 ? snapshot.remainingMeters / total : 1.0;
      minutes = (widget.result.durationSeconds * share / 60).ceil().clamp(
        1,
        1 << 20,
      );
      meters = snapshot.remainingMeters;
    } else {
      minutes = math.max(1, (widget.result.durationSeconds / 60).ceil());
      meters = widget.result.distanceMeters;
    }
    final steps = widget.result.steps;

    return MapDrawer(
      controller: _drawerController,
      peekHeight: _drawerPeekHeight,
      header: RouteDrawerHeader(
        primary: RouteMetricsService.formatEta(minutes),
        secondary:
            '${RouteMetricsService.formatDistanceMeters(meters)}'
            ' · ${_totalFareLabel()}',
        byline:
            'Suggested by ${RouteGuide.nameFor('${widget.destinationName}|'
            '${widget.result.distanceMeters.round()}|'
            '${widget.result.durationSeconds.round()}')}',
        isFollowing: _isNavigationStarted,
        hasArrived: _hasArrived,
        isStarting: _isStarting,
        onStart: _startNavigation,
        onStop: _stopNavigation,
        onDone: _endNavigationAndOfferCorrection,
        onOverview: _showWholeRoute,
      ),
      children: [
        if (place != null) ...[
          PlaceDetailsSection(
            place: place,
            distanceKm: _distanceToPlace(place),
            onClose: _clearSelectedPlace,
          ),
          const Divider(height: 1),
        ],
        RouteReportBanner(reports: _roadReports),
        if (widget.showDownloadButton)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                RouteActionChip(
                  icon:
                      _isDownloaded
                          ? Icons.download_done_rounded
                          : Icons.download_rounded,
                  label: _isDownloaded ? 'Downloaded' : 'Download',
                  active: _isDownloaded,
                  activeColor: Colors.green.shade700,
                  busy: _isDownloading,
                  onTap:
                      (_isDownloading || _isDownloaded)
                          ? null
                          : _downloadGeneratedRoute,
                ),
              ],
            ),
          ),
        RouteModeLegend(modes: _activeModes()),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_hasFareSteps) ...[
                const SizedBox(height: 2),
                FareDiscountToggle(
                  value: _isDiscountFareEnabled,
                  onChanged: _setDiscountEnabled,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  iconColor: AppColors.textSecondary,
                  iconSize: 16,
                  activeColor: const Color(0xFF0B8FD6),
                ),
              ],
              const SizedBox(height: 16),
              RouteSectionLabel('Route Steps (${steps.length})'),
              if (steps.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No step data available',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                for (var i = 0; i < steps.length; i++)
                  _buildStepTile(i, steps[i], _isStepCompleted(i)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(
            '© OSRM · © OpenStreetMap contributors',
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  /// Whether the traveler has passed the end of step [index] while
  /// following (the same test that greys its part of the line).
  bool _isStepCompleted(int index) {
    final ranges = _stepRanges;
    if (ranges.length != widget.result.steps.length) return false;
    return FollowRouteLayers.isRangeCompleted(ranges[index], _followSnapshot);
  }

  Widget _buildStepTile(int index, OrsStep step, bool isCompleted) {
    final mode = step.suggestedMode;
    final fare = step.estimatedFare;
    final showsDiscount =
        _isDiscountFareEnabled && PhFareCalculator.givesDiscount(mode);
    return RouteStepCard(
      number: index + 1,
      mode: mode,
      instruction: step.instruction.replaceFirst('[Estimated] ', ''),
      isCompleted: isCompleted,
      distance:
          step.distanceMeters > 0
              ? RouteMetricsService.formatDistanceMeters(step.distanceMeters)
              : null,
      fare:
          mode == 'Walk' || fare <= 0
              ? null
              : 'Fare: PHP ${fare.toStringAsFixed(0)} (estimated)'
                  '${showsDiscount ? '\n${FareDiscountToggle.defaultLabel}: PHP ${_applyFareDiscount(fare, mode).toStringAsFixed(0)}' : ''}',
      extras: [
        if (step.isCommunity) ...[
          const SizedBox(height: 4),
          const CommunityRouteBadge(),
        ],
      ],
    );
  }

  String _totalFareLabel() {
    final label = PhFareCalculator.tripEstimateLabel(
      PhFareCalculator.tripFare(
        widget.result,
        discount: _isDiscountFareEnabled,
      ),
    );
    return label == 'Free' ? label : '$label est.';
  }

  bool get _hasFareSteps => widget.result.steps.any(
    (step) => step.estimatedFare > 0 && step.suggestedMode != 'Walk',
  );

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
}
