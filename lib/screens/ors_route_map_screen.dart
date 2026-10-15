import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../widgets/map/map_pin_images.dart';
import '../widgets/map/transit_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../models/ors_route_result.dart';
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
import '../widgets/translated_text.dart';
import '../data/camanava_places.dart';
import '../models/place.dart';
import '../services/map_tab_controller.dart';
import '../widgets/map_tab/map_drawer.dart';
import '../widgets/map_tab/map_side_button.dart';
import '../widgets/map_tab/place_category_chips.dart';
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
  // Taller than other route views: the header also credits the guide.
  static const double _drawerPeekHeight = 100.0;

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
    OsmPlaces.all().then((places) {
      if (mounted) setState(() => _allPlaces = places);
    });

    _initLocation();
    _loadFareProfile();
    _loadDownloadState();
  }

  Future<void> _loadFareProfile() async {
    final student = await FareProfileService.isStudent();
    if (!student || !mounted || _hasManualFareDiscountOverride) return;
    setState(() => _isDiscountFareEnabled = true);
  }

  double _applyFareDiscount(double fare) =>
      _isDiscountFareEnabled ? PhFareCalculator.discountedFare(fare) : fare;

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
    _map.moveTo(
      target,
      zoom: zoom,
      bearing: bearing,
      tilt: _tilted ? _tilt3d : 0,
      duration: const Duration(milliseconds: 900),
      linear: true,
    );
  }

  /// The 2D/3D button.
  void _toggleTilt() {
    setState(() => _tilted = !_tilted);
    _map.tiltTo(_tilted ? _tilt3d : 0);
  }

  /// Keeps the 2D/3D button in step with a tilt by hand. Following sets
  /// the tilt itself, and a gesture stops following first.
  void _onMapCameraIdle(TransitMapCamera camera) {
    if (_isNavigationStarted && _isAutoFollowEnabled) return;
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
    _smoothMoveCamera(center, zoom: 13.0);
  }

  void _centerOnMe() {
    if (_displayPosition == null) return;
    if (_isNavigationStarted && !_isAutoFollowEnabled) {
      setState(() => _isAutoFollowEnabled = true);
    }
    _smoothMoveCamera(
      _displayPosition!,
      zoom: _followZoom,
      bearing: _displayHeading,
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
          color: _modeColor(step.suggestedMode),
        ),
    ];
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

  /// Round start and end badges.
  List<MapIcon> get _icons {
    final points = widget.result.polyline;
    return [
      if (points.isNotEmpty) MapIcon(points.first, MapPinImages.badgeStart),
      if (points.length > 1) MapIcon(points.last, MapPinImages.badgeEnd),
    ];
  }

  /// The next point to reach while following.
  List<MapDot> get _dots {
    final target = FollowRouteLayers.targetDot(_guidance);
    return [if (target != null) target];
  }

  /// The traveler's dot, drawn above every other layer.
  MapUser? get _mapUser {
    final at = _displayPosition;
    if (at == null) return null;
    return MapUser(
      at,
      accuracyMeters: _currentPosition?.accuracy ?? 0,
      headingDegrees: _displayHeading,
      speedMps: _currentPosition?.speed ?? 0,
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
    return const Distance().as(
      LengthUnit.Kilometer,
      here,
      LatLng(place.lat, place.lng),
    );
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
      places: _mapPlaces,
      lines: _lines,
      dots: _dots,
      icons: _icons,
      user: _mapUser,
      onTap: (_) => _clearSelectedPlace(),
      onPlaceTap: _onPlaceTapped,
      onUserGesture: () {
        if (_isAutoFollowEnabled) {
          setState(() => _isAutoFollowEnabled = false);
        }
      },
      onCameraIdle: _onMapCameraIdle,
      // Below the top bar and the chips.
      compassMargin: const math.Point(16, 130),
      attributionMargin: const math.Point(8, _drawerPeekHeight + 8),
    );
  }

  Widget _buildTopOverlay() {
    if (_guidance.kind != FollowGuidanceKind.none) {
      // Following: the next instruction takes the search bar's place.
      return Positioned(
        top: 8,
        left: 12,
        right: 12,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RouteBackButton(onBack: _closeView),
            const SizedBox(width: 8),
            Expanded(
              child: FollowGuidanceCard(
                guidance: _guidance,
                remainingMeters:
                    ActiveNavigationService.instance.connectorRemainingMeters,
                isRerouting: ActiveNavigationService.instance.isRerouting,
                routeStartLabel: widget.originName,
              ),
            ),
          ],
        ),
      );
    }
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: RouteTopBar(
              from: widget.originName,
              to: widget.destinationName,
              onBack: _closeView,
            ),
          ),
          if (!_isNavigationStarted) ...[
            const SizedBox(height: 8),
            PlaceCategoryChips(
              selected: MapTabController.instance.placeCategories.value,
              onToggleAll: MapTabController.instance.toggleAllCategories,
              onToggle: MapTabController.instance.toggleCategory,
            ),
          ],
        ],
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
    final String primary;
    final String secondary;
    if (snapshot != null && snapshot.hasProgress) {
      // Time left scales the route's estimate by the distance left.
      final total = widget.result.distanceMeters;
      final share = total > 0 ? snapshot.remainingMeters / total : 1.0;
      final minutesLeft = (widget.result.durationSeconds * share / 60)
          .ceil()
          .clamp(1, 1 << 20);
      primary = '$minutesLeft min left';
      secondary =
          '${RouteMetricsService.formatDistanceMeters(snapshot.remainingMeters)} left'
          ' · ${_totalFareLabel()}';
    } else {
      primary = widget.result.durationLabel;
      secondary =
          '${RouteMetricsService.formatDistanceMeters(widget.result.distanceMeters)}'
          ' · ${_totalFareLabel()}';
    }

    return MapDrawer(
      controller: _drawerController,
      peekHeight: _drawerPeekHeight,
      header: RouteDrawerHeader(
        primary: primary,
        secondary: secondary,
        byline:
            'Suggested by ${RouteGuide.nameFor('${widget.destinationName}|'
            '${widget.result.distanceMeters.round()}|'
            '${widget.result.durationSeconds.round()}')}',
        trailing: RouteFollowButton(
          isFollowing: _isNavigationStarted,
          hasArrived: _hasArrived,
          onStart: _startNavigation,
          onStop: _stopNavigation,
          onDone: _endNavigationAndOfferCorrection,
        ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.showDownloadButton)
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
              RouteActionChip(
                icon: Icons.fit_screen_rounded,
                label: 'Whole route',
                onTap: _centerOnRoute,
              ),
            ],
          ),
        ),
        _buildModeLegendRow(),
        if (_hasFareSteps)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FareDiscountToggle(
              value: _isDiscountFareEnabled,
              onChanged: _setDiscountEnabled,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              iconColor: AppColors.textSecondary,
              iconSize: 15,
              activeColor: Colors.blue.shade700,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Steps (${widget.result.steps.length})',
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
          ),
        ),
        if (widget.result.steps.isEmpty)
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
          for (var i = 0; i < widget.result.steps.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            _buildStepTile(widget.result.steps[i]),
          ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Text(
            '© OSRM · © OpenStreetMap contributors',
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  /// Which color is which mode on the map.
  Widget _buildModeLegendRow() {
    final modes = _activeModes();
    if (modes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final mode in modes)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _modeColor(mode),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 5),
                Icon(_modeIcon(mode), size: 13, color: _modeColor(mode)),
                const SizedBox(width: 3),
                Text(
                  mode,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _modeColor(mode),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStepTile(OrsStep step) {
    final modeColor = _modeColor(step.suggestedMode);
    return ListTile(
      dense: true,
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: modeColor.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: modeColor, width: 1.5),
        ),
        child: Icon(_modeIcon(step.suggestedMode), size: 16, color: modeColor),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: modeColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              step.suggestedMode,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.instruction, style: const TextStyle(fontSize: 13)),
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
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (step.distanceMeters > 0)
            Text(
              _formatStepDistance(step.distanceMeters),
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          if (step.estimatedFare > 0)
            Text(
              '₱${_applyFareDiscount(step.estimatedFare).toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.green.shade600,
              ),
            ),
        ],
      ),
    );
  }

  String _formatStepDistance(double meters) {
    return RouteMetricsService.formatDistanceMeters(meters);
  }

  String _totalFareLabel() {
    final label = PhFareCalculator.tripEstimateLabel(
      widget.result.baseFarePhp,
      student: _isDiscountFareEnabled,
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
