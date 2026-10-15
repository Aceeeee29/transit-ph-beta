import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/map/map_pin_images.dart';
import '../widgets/map/transit_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import '../models/route.dart' as route_model;
import '../services/fare_matrix.dart';
import '../services/gamification_service.dart';
import '../services/route_metrics_service.dart';
import '../services/route_service.dart';
import '../services/route_trust_service.dart';
import '../services/offline_tile_service.dart';
import '../services/active_navigation_service.dart';
import '../services/route_follow_engine.dart';
import '../services/route_follow_guidance.dart';
import '../widgets/route_map/follow_guidance_card.dart';
import '../widgets/route_map/follow_route_layers.dart';
import '../widgets/route_map/follow_simulator_sheet.dart';
import '../widgets/route_map/ride_correction_flow.dart';
import '../services/osm_places.dart';
import '../services/facing.dart';
import '../repositories/offline_route_repository.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/fare_discount_toggle.dart';
import '../widgets/route_map/route_report_dialog.dart';
import '../widgets/translated_text.dart';
import '../widgets/location_permission_notice.dart';
import '../data/camanava_places.dart';
import '../models/place.dart';
import '../services/map_tab_controller.dart';
import '../widgets/map_tab/map_drawer.dart';
import '../widgets/map_tab/map_side_button.dart';
import '../widgets/map_tab/place_category_chips.dart';
import '../widgets/map_tab/place_widgets.dart';
import '../widgets/map_tab/route_view_widgets.dart';
import '../theme/app_colors.dart';
part 'route_map_screen_widgets.dart';
part 'route_map_screen_data.dart';
part 'route_map_screen_chrome.dart';

class RouteMapScreen extends StatefulWidget {
  final route_model.Route route;
  final bool enableRouteIntegrity;
  final bool showDownloadButton;

  /// Back to the map. Without it, back pops this page.
  final VoidCallback? onClose;

  const RouteMapScreen({
    super.key,
    required this.route,
    this.enableRouteIntegrity = true,
    this.showDownloadButton = true,
    this.onClose,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  static const _skipTrustPromptDateKey = 'route_trust_feedback_skip_until_date';

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
  bool _isAutoFollowEnabled = false;
  bool _isFinishingRoute = false;
  List<route_model.Report> _routeReports = [];
  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;
  bool? _userVote;
  String? _currentUserId;
  bool _isApplyingVote = false;
  List<LatLng> _pathPoints = [];
  Map<String, int> _feedbackSummary = const {
    'fareAccurateYes': 0,
    'fareAccurateNo': 0,
    'scheduleAccurateYes': 0,
    'scheduleAccurateNo': 0,
    'stillOperatingYes': 0,
    'stillOperatingNo': 0,
  };
  RouteTrustScore? _trustScore;
  bool _isSubmittingTrustFeedback = false;
  bool _fareAccurate = true;
  bool _scheduleAccurate = true;
  bool _stillOperating = true;
  bool _hasSubmittedTrustFeedback = false;
  DateTime? _trustFeedbackNextAllowedAt;
  bool _isExitPromptOpen = false;
  bool _isRouteDownloaded = false;
  bool _isDownloadingRoute = false;
  bool _isDiscountFareEnabled = false;
  bool _hasManualFareDiscountOverride = false;

  // ─── Map chrome (drawer, place pins) ──────────────────────────────────────
  final DraggableScrollableController _drawerController =
      DraggableScrollableController();
  Place? _selectedPlace;
  static const double _drawerPeekHeight = 80.0;

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static Color get _bg => AppColors.bg;
  static Color get _surface => AppColors.surface;
  static Color get _surfaceAlt => AppColors.surfaceAlt;
  static const _accent = Color(0xFF0B8FD6);
  static Color get _textPrimary => AppColors.textPrimary;
  static Color get _textSecondary => AppColors.textSecondary;
  static Color get _border => AppColors.border;
  static const _danger = Color(0xFFE05C6A);
  static const _green = Color(0xFF3EC97A);

  final Map<String, Color> modeColors = {
    'Walk': Colors.green,
    'Jeepney': Colors.blue,
    'Bus': Colors.red,
    'Train': Colors.purple,
    'Tricycle': Colors.orange,
    'FX/Van': Colors.amber,
    'Ferry': Colors.lightBlue,
  };

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

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

    _generatePathPoints();
    _initLocation();
    _loadReports();
    _loadEngagementState();
    if (widget.enableRouteIntegrity) {
      _loadRouteTrustState();
    }
    _loadFareProfile();
    _loadDownloadedState();
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
    if (_isNavigationStarted && _isAutoFollowEnabled) return;
    final tilted = camera.tilt > 5;
    if (tilted != _tilted && mounted) setState(() => _tilted = tilted);
  }

  Future<void> _loadDownloadedState() async {
    final isDownloaded = await OfflineRouteRepository.isRouteDownloaded(
      widget.route.id,
    );
    if (!mounted) return;
    setState(() => _isRouteDownloaded = isDownloaded);
  }

  Future<void> _downloadRouteForOffline() async {
    if (!widget.showDownloadButton) return;
    if (_isDownloadingRoute || _isRouteDownloaded) return;

    setState(() => _isDownloadingRoute = true);
    try {
      await OfflineRouteRepository.saveRoute(widget.route);
      await OfflineTileService.cacheRouteTiles(_pointsForTileCaching());
      if (!mounted) return;
      setState(() => _isRouteDownloaded = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route downloaded for offline mode.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _isDownloadingRoute = false);
      }
    }
  }

  List<LatLng> _pointsForTileCaching() {
    final points = <LatLng>[];
    points.addAll(widget.route.pathPoints);
    if (widget.route.startLat != null && widget.route.startLng != null) {
      points.add(LatLng(widget.route.startLat!, widget.route.startLng!));
    }
    if (widget.route.endLat != null && widget.route.endLng != null) {
      points.add(LatLng(widget.route.endLat!, widget.route.endLng!));
    }
    return points;
  }

  Future<void> _loadEngagementState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _currentUserId = uid;

    try {
      await RouteService.incrementViewForUser(widget.route.id, uid);
      final results = await Future.wait([
        RouteService.getRouteById(widget.route.id),
        RouteService.getUserVote(widget.route.id, uid),
      ]);

      if (!mounted) return;

      final latestRoute = results[0] as route_model.Route?;
      final vote = results[1] as bool?;

      setState(() {
        if (latestRoute != null) {
          widget.route.views = latestRoute.views;
          widget.route.upvotes = latestRoute.upvotes;
          widget.route.downvotes = latestRoute.downvotes;
        }
        _userVote = vote;
      });
    } catch (_) {}
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

  Future<void> _loadRouteTrustState() async {
    final summary = await RouteService.getRouteFeedbackSummary(widget.route.id);
    final score = RouteTrustService.computeConfidence(
      route: widget.route,
      feedbackSummary: summary,
    );

    final uid = FirebaseAuth.instance.currentUser?.uid;
    Map<String, bool>? mine;
    DateTime? nextAllowedAt;
    if (uid != null && uid.trim().isNotEmpty) {
      final results = await Future.wait<dynamic>([
        RouteService.getUserRouteQualityFeedback(
          routeId: widget.route.id,
          userId: uid,
        ),
        RouteService.getUserRouteFeedbackNextAllowedAt(
          routeId: widget.route.id,
          userId: uid,
        ),
      ]);
      mine = results[0] as Map<String, bool>?;
      nextAllowedAt = results[1] as DateTime?;
    }

    if (!mounted) return;
    setState(() {
      _feedbackSummary = summary;
      _trustScore = score;
      _hasSubmittedTrustFeedback = mine != null;
      _trustFeedbackNextAllowedAt = nextAllowedAt;
      if (mine != null) {
        _fareAccurate = mine['fareAccurate'] ?? _fareAccurate;
        _scheduleAccurate = mine['scheduleAccurate'] ?? _scheduleAccurate;
        _stillOperating = mine['stillOperating'] ?? _stillOperating;
      }
    });
  }

  Future<bool> _submitTrustFeedbackValues({
    required bool fareAccurate,
    required bool scheduleAccurate,
    required bool stillOperating,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to submit route trust feedback.'),
        ),
      );
      return false;
    }
    if (_isSubmittingTrustFeedback) return false;

    setState(() => _isSubmittingTrustFeedback = true);
    try {
      await RouteService.submitRouteQualityFeedback(
        routeId: widget.route.id,
        userId: uid,
        fareAccurate: fareAccurate,
        scheduleAccurate: scheduleAccurate,
        stillOperating: stillOperating,
      );
      await _loadRouteTrustState();
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks! Route trust feedback saved.')),
      );
      return true;
    } catch (e) {
      if (e is StateError) {
        final rawMessage = e.message.toString();
        if (rawMessage.startsWith('feedback_cooldown:')) {
          return true;
        }
      }

      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not submit feedback: $e')));
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSubmittingTrustFeedback = false);
      }
    }
  }

  Future<Map<String, dynamic>?> _showExitTrustFeedbackDialog() async {
    return _showExitTrustFeedbackDialogSection();
  }

  /// Shown when the user taps Stop Route (never on back/minimize), subject
  /// to the same rarity gate as before: guaranteed the first time a user
  /// stops a route they haven't given feedback on, then throttled by
  /// [_trustFeedbackNextAllowedAt] / the daily skip flag after that.
  Future<void> _maybeShowTrustFeedbackPrompt() async {
    if (!widget.enableRouteIntegrity) return;
    if (await _isTrustPromptSkippedToday()) return;

    if (_hasSubmittedTrustFeedback) {
      final nextAllowedAt = _trustFeedbackNextAllowedAt;
      if (nextAllowedAt == null || DateTime.now().isBefore(nextAllowedAt)) {
        return;
      }
    }

    if (_isExitPromptOpen) return;
    _isExitPromptOpen = true;
    try {
      final result = await _showExitTrustFeedbackDialog();
      if (!mounted || result == null) return;

      final action = (result['action'] as String?) ?? 'dismiss';
      final fare = (result['fareAccurate'] as bool?) ?? _fareAccurate;
      final schedule =
          (result['scheduleAccurate'] as bool?) ?? _scheduleAccurate;
      final operating = (result['stillOperating'] as bool?) ?? _stillOperating;

      _applyTrustFeedbackSelection(
        fareAccurate: fare,
        scheduleAccurate: schedule,
        stillOperating: operating,
      );

      if (action == 'submit') {
        await _submitTrustFeedbackValues(
          fareAccurate: fare,
          scheduleAccurate: schedule,
          stillOperating: operating,
        );
      } else if (action == 'skip_today') {
        await _setTrustPromptSkipToday();
      }
    } finally {
      _isExitPromptOpen = false;
    }
  }

  void _applyTrustFeedbackSelection({
    required bool fareAccurate,
    required bool scheduleAccurate,
    required bool stillOperating,
  }) {
    setState(() {
      _fareAccurate = fareAccurate;
      _scheduleAccurate = scheduleAccurate;
      _stillOperating = stillOperating;
    });
  }

  void _setAutoFollowEnabled(bool value) {
    setState(() => _isAutoFollowEnabled = value);
  }

  void _setRouteReports(
    List<route_model.Report> reports, {
    bool sortByLatest = false,
  }) {
    setState(() {
      _routeReports = reports;
      if (sortByLatest) {
        _routeReports.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
    });
  }

  Future<bool> _isTrustPromptSkippedToday() async {
    return _isTrustPromptSkippedTodaySection();
  }

  Future<void> _setTrustPromptSkipToday() async {
    await _setTrustPromptSkipTodaySection();
  }

  /// True while this screen's route is the active follow session; the
  /// session (GPS, progress, arrival) lives in [ActiveNavigationService].
  bool get _isNavigationStarted =>
      ActiveNavigationService.instance.isFollowing(widget.route.id);

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
    final hasAccess = await ensureLocationAccess(
      context,
      reason: 'show where you are on the route',
    );
    if (!hasAccess) return;

    // Resuming an active session: its stream already tracks the user.
    final sessionPosition =
        _isNavigationStarted
            ? ActiveNavigationService.instance.lastPosition
            : null;
    if (sessionPosition != null) {
      _onNavigationPosition();
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() => _applyPosition(position, _rawLatLng(position)));
      if (!_isNavigationStarted) _startLocationTracking();
    } catch (e) {
      debugPrint('RouteMapScreen: failed to get current position: $e');
    }
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
    if (position == null) return;
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

  void _applyPosition(Position position, LatLng display) {
    _currentPosition = position;
    _displayPosition = display;
    _facing.onFix(position);
    // GPS heading is noise when barely moving (often reported as 0, which
    // spun the map north); keep the last good heading until moving again.
    if (position.speed >= _minHeadingSpeedMps) {
      _displayHeading = _normalizeHeading(position.heading);
    }
  }

  static const _minHeadingSpeedMps = 1.0;

  /// How close the camera follows: street level on foot, a little wider at
  /// vehicle speed so more of the road ahead shows.
  double get _followZoom =>
      (_currentPosition?.speed ?? 0) > _vehicleZoomSpeedMps ? 16.5 : 17.5;
  static const _vehicleZoomSpeedMps = 6.0;

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

  Future<void> _loadReports() async {
    await _loadReportsSection();
  }

  Future<void> _saveReports() async {
    await _saveReportsSection();
  }

  void _generatePathPoints() {
    if (widget.route.pathPoints.isNotEmpty) {
      _pathPoints = List.from(widget.route.pathPoints);
      return;
    }
    if (widget.route.startLat == null ||
        widget.route.startLng == null ||
        widget.route.endLat == null ||
        widget.route.endLng == null) {
      _pathPoints = [];
      return;
    }

    final start = LatLng(widget.route.startLat!, widget.route.startLng!);
    final end = LatLng(widget.route.endLat!, widget.route.endLng!);
    if (widget.route.steps.isEmpty) {
      _pathPoints = [start, end];
      return;
    }

    final numSegments = widget.route.steps.length;
    final latStep = (end.latitude - start.latitude) / numSegments;
    final lngStep = (end.longitude - start.longitude) / numSegments;
    _pathPoints = List.generate(
      numSegments + 1,
      (i) =>
          LatLng(start.latitude + latStep * i, start.longitude + lngStep * i),
    );
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

  void _applyVoteDelta(bool? previousVote, bool? nextVote) {
    if (previousVote == true) {
      widget.route.upvotes = (widget.route.upvotes - 1).clamp(0, 1 << 31);
    } else if (previousVote == false) {
      widget.route.downvotes = (widget.route.downvotes - 1).clamp(0, 1 << 31);
    }
    if (nextVote == true) {
      widget.route.upvotes += 1;
    } else if (nextVote == false) {
      widget.route.downvotes += 1;
    }
  }

  Future<void> _vote(bool isUpvote) async {
    if (_isApplyingVote) return;

    if (_currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to vote on routes')),
      );
      return;
    }

    if (_userVote != null && _userVote != isUpvote) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remove your current vote first before voting again'),
        ),
      );
      return;
    }

    // Mirror the server's toggle logic optimistically: tapping the same
    // vote again clears it, otherwise it becomes the tapped vote (the
    // pre-checks above already guarantee _userVote is null or == isUpvote
    // here, so this always matches what the transaction below will do).
    final previousVote = _userVote;
    final previousUpvotes = widget.route.upvotes;
    final previousDownvotes = widget.route.downvotes;
    final optimisticVote = previousVote == isUpvote ? null : isUpvote;

    setState(() {
      _isApplyingVote = true;
      _userVote = optimisticVote;
      _applyVoteDelta(previousVote, optimisticVote);
    });

    try {
      final updatedVote = await RouteService.setUserVote(
        routeId: widget.route.id,
        userId: _currentUserId!,
        isUpvote: isUpvote,
      );
      if (!mounted) return;

      if (updatedVote != optimisticVote) {
        // Reconcile with the server's actual result.
        setState(() {
          _userVote = updatedVote;
          _applyVoteDelta(optimisticVote, updatedVote);
        });
      }

      final message =
          updatedVote == null
              ? 'Vote removed'
              : (updatedVote ? 'Upvoted route' : 'Downvoted route');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _userVote = previousVote;
        widget.route.upvotes = previousUpvotes;
        widget.route.downvotes = previousDownvotes;
      });
      final message =
          e.message == 'remove_first'
              ? 'Remove your current vote first before voting again'
              : 'Unable to save vote right now';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _userVote = previousVote;
        widget.route.upvotes = previousUpvotes;
        widget.route.downvotes = previousDownvotes;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save vote right now')),
      );
    } finally {
      if (mounted) setState(() => _isApplyingVote = false);
    }
  }

  void _showReportDialog() {
    showRouteReportDialog(
      context,
      onSubmit: (type, description) => _submitReport(type, description),
    );
  }

  void _submitReport(String type, String description) async {
    final report = route_model.Report(
      type: type,
      description: description.isNotEmpty ? description : null,
      timestamp: DateTime.now(),
    );
    _routeReports.add(report);
    await _saveReports();

    final user = await GamificationService.loadUser();
    final unlockedItems = await GamificationService.incrementReportsSubmitted(
      user,
    );
    if (unlockedItems.isNotEmpty) {
      setState(() {
        _pendingNotifications = unlockedItems;
        _showNotificationOverlay = true;
      });
    }

    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report submitted!')));
    }
  }

  void _centerOnCurrentLocation() {
    if (_displayPosition == null) return;
    if (_isNavigationStarted && !_isAutoFollowEnabled) {
      setState(() => _isAutoFollowEnabled = true);
    }
    _smoothMoveCamera(_displayPosition!, zoom: _followZoom, bearing: _heading);
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
    final ranges = _stepRanges();
    ActiveNavigationService.instance.start(
      FollowTarget.route(
        widget.route,
        path: _pathPoints,
        steps: [
          for (var i = 0; i < ranges.length; i++)
            _followStep(
              i < widget.route.steps.length ? widget.route.steps[i] : null,
              ranges[i],
            ),
        ],
      ),
      initialPosition: _currentPosition,
      enableRouteIntegrity: widget.enableRouteIntegrity,
      showDownloadButton: widget.showDownloadButton,
    );
    _onNavigationPosition();
    _centerOnCurrentLocation();
  }

  FollowStep _followStep(
    route_model.Step? step,
    ({int start, int end, Color color}) range,
  ) {
    final designated = step?.usesDesignatedStops ?? false;
    return FollowStep(
      mode: step?.mode,
      startIndex: range.start,
      endIndex: range.end,
      designatedStops: designated,
      stops: [
        if (designated)
          for (final stop in step!.stops)
            FollowStop(
              point: stop.point,
              name: stop.name,
              pickup: stop.pickup,
              dropoff: stop.dropoff,
            ),
      ],
    );
  }

  /// Ends a session that reached the end of the route.
  Future<void> _finishArrivedRoute() async {
    if (_isFinishingRoute) return;
    _isFinishingRoute = true;
    try {
      await _maybeShowTrustFeedbackPrompt();
      if (!mounted) return;
      await _endNavigationAndOfferCorrection();
    } finally {
      _isFinishingRoute = false;
    }
  }

  /// Ends the session, then — if the vehicle went a different way than this
  /// route — offers the ride as a correction or a new route.
  Future<void> _endNavigationAndOfferCorrection() async {
    final deviations = ActiveNavigationService.instance.finishDeviations();
    final boundaries = [for (final range in _stepRanges()) range.end];
    _endNavigation();
    if (!mounted) return;
    await RideCorrectionFlow.offer(
      context,
      deviations: deviations,
      followedPath: _pathPoints,
      route: widget.route,
      stepBoundaries: boundaries,
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

    await _maybeShowTrustFeedbackPrompt();
    if (!mounted) return;
    await _endNavigationAndOfferCorrection();
  }

  void _onNotificationsDismissed() {
    setState(() {
      _showNotificationOverlay = false;
      _pendingNotifications.clear();
    });
  }

  @override
  void dispose() {
    final navigation = ActiveNavigationService.instance;
    navigation.removeListener(_onNavigationSessionChanged);
    navigation.followUpdates.removeListener(_onNavigationPosition);
    MapTabController.instance.placeCategories.removeListener(_onSharedMapState);
    MapTabController.instance.showPins.removeListener(_onSharedMapState);
    _drawerController.dispose();
    _facing.dispose();
    _positionSubscription?.cancel();
    super.dispose();
  }

  /// Pin filter or visibility changed (here or elsewhere on the Map tab).
  void _onSharedMapState() {
    if (mounted) setState(() {});
  }

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

  /// Back to the map (or out of this page when opened on its own).
  void _closeView() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  bool get _hasFareSteps =>
      widget.route.steps.any((step) => step.mode != 'Walk');

  bool _isStudentCategory(String category) =>
      category.replaceAll('_', ' ') == 'student';

  /// Per ride: the discount rounds each fare up to the next peso.
  double _applyFareDiscount(double fare) =>
      _isDiscountFareEnabled ? PhFareCalculator.discountedFare(fare) : fare;

  void _setDiscountEnabled(bool value) {
    setState(() {
      _isDiscountFareEnabled = value;
      _hasManualFareDiscountOverride = true;
    });
  }

  double? _parseFareAmount(String? priceLabel) {
    if (priceLabel == null) return null;
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(priceLabel);
    if (match == null) return null;
    return double.tryParse(match.group(1) ?? '');
  }

  double _estimateStepDistanceKm(int stepIndex) {
    if (_pathPoints.length < 2) return 0.0;

    final boundaries =
        widget.route.stepBoundaries.isNotEmpty
            ? widget.route.stepBoundaries
            : _computeEvenBoundaries();
    final startIdx = stepIndex == 0 ? 0 : boundaries[stepIndex - 1];
    final endIdx =
        stepIndex < boundaries.length
            ? boundaries[stepIndex]
            : _pathPoints.length - 1;

    if (endIdx <= startIdx) return 0.0;
    final distance = const Distance();
    double total = 0.0;
    for (int i = startIdx; i < endIdx && i + 1 < _pathPoints.length; i++) {
      total += distance.as(
        LengthUnit.Kilometer,
        _pathPoints[i],
        _pathPoints[i + 1],
      );
    }
    return total;
  }

  double _estimateStepFare(int stepIndex, route_model.Step step) {
    final distanceKm = _estimateStepDistanceKm(stepIndex);
    return RouteMetricsService.calculateFareForMode(step.mode, distanceKm);
  }

  double _calculateRouteFareTotal() =>
      _routeFareTotal(discounted: _isDiscountFareEnabled);

  double _routeFareTotal({required bool discounted}) {
    double fare(double regular) =>
        discounted ? PhFareCalculator.discountedFare(regular) : regular;
    double total = 0.0;
    for (int i = 0; i < widget.route.steps.length; i++) {
      final step = widget.route.steps[i];
      if (step.mode == 'Walk') continue;
      final baseFare = step.actualFare ?? _estimateStepFare(i, step);
      total += fare(baseFare);
    }

    if (total <= 0) {
      final parsed = _parseFareAmount(widget.route.price);
      if (parsed != null) total = fare(parsed);
    }

    return total;
  }

  RouteFollowEngine? _pathLineCache;

  /// The drawn path measured the same way the follow session measures
  /// progress along it.
  RouteFollowEngine? get _pathLine {
    if (_pathPoints.length < 2) return null;
    return _pathLineCache ??= RouteFollowEngine(_pathPoints);
  }

  /// While following: the distance left and an ETA from each remaining
  /// step's typical speed. Null when not following.
  ({double meters, int minutes})? _remainingTrip() {
    final snapshot = _followSnapshot;
    final line = _pathLine;
    if (snapshot == null || !snapshot.hasProgress || line == null) return null;
    final ranges = _stepRanges();
    var minutes = 0.0;
    for (var i = 0; i < ranges.length; i++) {
      final start = line.alongAt(ranges[i].start);
      final end = line.alongAt(ranges[i].end);
      final left = end - math.max(start, snapshot.progressMeters);
      if (left <= 0) continue;
      final mode =
          i < widget.route.steps.length
              ? widget.route.steps[i].mode
              : 'Jeepney';
      minutes += left / 1000 / RouteMetricsService.speedKmhForMode(mode) * 60;
    }
    return (meters: snapshot.remainingMeters, minutes: minutes.ceil());
  }

  /// With the discount on, the card shows the discounted total and this
  /// label keeps the regular fare visible ("Fare · reg. PHP 33").
  String? _regularFareNote() {
    if (!_isDiscountFareEnabled) return null;
    final regular = _routeFareTotal(discounted: false);
    if (regular <= 0) return null;
    return 'Fare · reg. PHP ${regular.round()}';
  }

  String? _routeFareLabel() {
    if (!_hasFareSteps && (widget.route.price == null)) return null;
    final totalFare = _calculateRouteFareTotal();
    if (totalFare <= 0) return 'Free';
    return 'PHP ${totalFare.round()}';
  }

  /// The saved ETA, or an estimate from the drawn path when it is missing or
  /// was saved as 0.
  String? _routeEtaLabel() {
    final saved = widget.route.eta?.trim() ?? '';
    final savedMinutes = int.tryParse(saved.replaceAll(RegExp(r'[^0-9]'), ''));
    if (saved.isNotEmpty && (savedMinutes == null || savedMinutes > 0)) {
      return RouteMetricsService.formatEtaLabel(saved);
    }
    if (widget.route.steps.isEmpty) return null;
    final estimated = RouteMetricsService.calculateEta(
      _pathPoints,
      widget.route.steps.map((s) => s.mode).toList(),
      widget.route.stepBoundaries.isNotEmpty
          ? widget.route.stepBoundaries
          : _computeEvenBoundaries(),
    );
    return estimated > 0
        ? RouteMetricsService.formatEtaLabel('$estimated')
        : null;
  }

  IconData _getModeIcon(String mode) {
    switch (mode) {
      case 'Walk':
        return Icons.directions_walk;
      case 'Jeepney':
      case 'Bus':
        return Icons.directions_bus;
      case 'Train':
        return Icons.train;
      case 'Tricycle':
        return Icons.two_wheeler;
      case 'FX/Van':
        return Icons.directions_car;
      case 'Ferry':
        return Icons.directions_boat;
      default:
        return Icons.directions_walk;
    }
  }

  IconData _getReportIcon(String type) {
    switch (type) {
      case 'Heavy traffic / congestion':
        return Icons.traffic;
      case 'Road closure / construction':
        return Icons.construction;
      case 'Accident / crash':
        return Icons.car_crash;
      case 'Hazard on road':
        return Icons.warning;
      case 'Crime / suspicious activity':
        return Icons.security;
      case 'Bus/train delay':
        return Icons.schedule;
      case 'Cancelled service':
        return Icons.cancel;
      case 'Crowding / full capacity':
        return Icons.group;
      case 'Flooding / water logging':
        return Icons.water;
      case 'Landslide / mudslide':
        return Icons.terrain;
      case 'Storm / lightning hazard':
        return Icons.thunderstorm;
      default:
        return Icons.report;
    }
  }

  String _formatTime(DateTime time) =>
      '${time.hour}:${time.minute.toString().padLeft(2, '0')} '
      '${time.day}/${time.month}';

  /// Each step's path-index range and colour; one blue range when the route
  /// has no steps.
  List<({int start, int end, Color color})> _stepRanges() {
    final last = _pathPoints.length - 1;
    if (widget.route.steps.isEmpty) {
      return [(start: 0, end: last, color: Colors.blue)];
    }
    final boundaries =
        widget.route.stepBoundaries.isNotEmpty
            ? widget.route.stepBoundaries
            : _computeEvenBoundaries();
    return [
      for (int i = 0; i < widget.route.steps.length; i++)
        (
          start: math.min(i == 0 ? 0 : boundaries[i - 1], last),
          end: math.min(i < boundaries.length ? boundaries[i] : last, last),
          color: modeColors[widget.route.steps[i].mode] ?? Colors.blue,
        ),
    ];
  }

  /// The route (travelled part grey while following) plus, when the
  /// traveler is off it, the dashed temporary path back to it.
  List<MapLine> get _lines {
    return [
      ...FollowRouteLayers.routeLines(
        path: _pathPoints,
        ranges: _stepRanges(),
        snapshot: _followSnapshot,
        outline: Colors.black,
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

  /// Whether the traveler has already passed step [stepIndex] while
  /// following, using the same ranges as [_lines] so the two stay in sync.
  bool _isStepCompleted(int stepIndex) {
    final ranges = _stepRanges();
    if (stepIndex >= ranges.length) return false;
    return FollowRouteLayers.isRangeCompleted(
      ranges[stepIndex],
      _followSnapshot,
    );
  }

  List<int> _computeEvenBoundaries() {
    final total = _pathPoints.length;
    final numSteps = widget.route.steps.length;
    return List.generate(
      numSteps - 1,
      (i) => ((i + 1) * (total - 1) / numSteps).round(),
    );
  }

  /// The start pin and the end flag.
  List<MapIcon> get _icons => [
    if (_pathPoints.isNotEmpty)
      MapIcon(_pathPoints.first, MapPinImages.routeStart, anchorBottom: true),
    if (_pathPoints.length > 1)
      MapIcon(_pathPoints.last, MapPinImages.routeEnd, anchorBottom: true),
  ];

  /// Designated stops in their step's color, and the next point to reach
  /// while following.
  List<MapDot> get _dots {
    final target = FollowRouteLayers.targetDot(_guidance);
    return [
      for (final step in widget.route.steps)
        if (step.usesDesignatedStops)
          for (final stop in step.stops)
            MapDot(
              stop.point,
              radius: 5,
              strokeColor: modeColors[step.mode] ?? Colors.blue,
            ),
      if (target != null) target,
    ];
  }

  /// How passengers board this step, for its tile.
  String? _boardingLabel(route_model.Step step) {
    if (step.mode == 'Walk') return null;
    if (step.usesDesignatedStops) {
      final count = step.stops.length;
      if (count > 0) {
        return 'Board and get off at $count designated '
            '${count == 1 ? 'stop' : 'stops'}';
      }
      return step.mode == 'Train'
          ? 'Board and get off at the stations'
          : 'Board at the start, get off at the end (stops not yet mapped)';
    }
    return 'Board or get off anywhere along the route';
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

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_pathPoints.isEmpty) return _buildEmptyState();

    final center = LatLng(
      (_pathPoints.first.latitude + _pathPoints.last.latitude) / 2,
      (_pathPoints.first.longitude + _pathPoints.last.longitude) / 2,
    );

    return Stack(
      children: [
        Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: Stack(
              children: [
                _buildMapSection(center),
                _buildTopOverlaySection(),
                if (kDebugMode && _isNavigationStarted && !_hasArrived)
                  Positioned(
                    left: 12,
                    bottom: _drawerPeekHeight + 12,
                    child: FollowSimulatorButton(path: _pathPoints),
                  ),
                _buildSideButtonsSection(),
                _buildRouteDrawerSection(),
              ],
            ),
          ),
        ),
        if (_showNotificationOverlay)
          NotificationOverlay(
            notifications: _pendingNotifications,
            onAllDismissed: _onNotificationsDismissed,
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return _buildEmptyStateSection();
  }

  Widget _buildMapSection(LatLng center) {
    return _buildMapSectionSection(center);
  }

  String? _routeScheduleText() {
    final saved = widget.route.schedule?.trim();
    if (saved != null && saved.isNotEmpty) return saved;

    final transportSteps =
        widget.route.steps.where((s) => s.mode != 'Walk').toList();
    if (transportSteps.isEmpty) return null;

    final has24x7Leg = transportSteps.any((s) => s.is24_7);
    int? earliest;
    int? latest;

    for (final step in transportSteps) {
      if (step.is24_7) continue;
      final start = _parseTimeToMinutes(step.startTime);
      final end = _parseTimeToMinutes(step.endTime);
      if (start == null || end == null) continue;
      earliest = earliest == null ? start : math.min(earliest, start);
      latest = latest == null ? end : math.max(latest, end);
    }

    if (has24x7Leg && earliest != null && latest != null) {
      return '24/7 (some steps: ${_minutesToText(earliest)}-${_minutesToText(latest)})';
    }
    if (has24x7Leg) return '24/7';
    if (earliest != null && latest != null) {
      return '${_minutesToText(earliest)}-${_minutesToText(latest)}';
    }
    return null;
  }

  int? _parseTimeToMinutes(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  String _minutesToText(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String? _stepScheduleText(route_model.Step step) {
    if (step.mode == 'Walk') return null;
    if (step.is24_7) return '24/7';
    final start = step.startTime?.trim();
    final end = step.endTime?.trim();
    if (start == null || start.isEmpty || end == null || end.isEmpty)
      return null;
    return '$start-$end';
  }

  Widget _buildMetricsRow() {
    return _buildMetricsRowSection();
  }

  Widget _buildStepTile(int idx, route_model.Step step) {
    return _buildStepTileSection(idx, step);
  }

  Widget _buildReportTile(route_model.Report report) {
    return _buildReportTileSection(report);
  }

  Widget _metricCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return _metricCardSection(
      icon: icon,
      iconColor: iconColor,
      label: label,
      value: value,
    );
  }

  Widget _buildSectionLabel(String label) => _buildSectionLabelSection(label);
}
