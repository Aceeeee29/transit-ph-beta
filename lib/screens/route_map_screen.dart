import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import '../models/route.dart' as route_model;
import '../services/gamification_service.dart';
import '../services/schedule_window_service.dart';
import '../services/route_metrics_service.dart';
import '../services/route_service.dart';
import '../services/route_trust_service.dart';
import '../services/offline_tile_service.dart';
import '../repositories/offline_route_repository.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/fare_discount_toggle.dart';
import '../widgets/route_map/route_report_dialog.dart';
part 'route_map_screen_widgets.dart';
part 'route_map_screen_overlays.dart';
part 'route_map_screen_data.dart';

class RouteMapScreen extends StatefulWidget {
  final route_model.Route route;
  final bool enableRouteIntegrity;
  final bool showDownloadButton;

  const RouteMapScreen({
    super.key,
    required this.route,
    this.enableRouteIntegrity = true,
    this.showDownloadButton = true,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

// FIX: Added SingleTickerProviderStateMixin for smooth camera animation
class _RouteMapScreenState extends State<RouteMapScreen>
    with SingleTickerProviderStateMixin {
  static const _skipTrustPromptDateKey =
      'route_trust_feedback_skip_until_date';

  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  LatLng? _displayPosition;
  double _displayHeading = 0;
  LatLng? _lastCameraTarget;
  DateTime? _lastCameraMoveAt;
  bool _isNavigationStarted = false;
  bool _isAutoFollowEnabled = false;
  List<route_model.Report> _routeReports = [];
  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;
  bool? _userVote;
  String? _currentUserId;
  bool _isApplyingVote = false;
  List<LatLng> _pathPoints = [];
  RouteScheduleSnapshot? _scheduleSnapshot;
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

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
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
    _loadReports();
    _loadEngagementState();
    _generatePathPoints();
    _loadScheduleWindowSnapshot();
    if (widget.enableRouteIntegrity) {
      _loadRouteTrustState();
    }
    _loadFareProfile();
    _loadDownloadedState();
    _loadOfflineTileTemplate();
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
    final rotation =
        _lerpRotation(_animStartRotation, _animTargetRotation, t);

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
      await OfflineTileService.cacheRouteTiles(
        _pointsForTileCaching(),
      );
      if (!mounted) return;
      setState(() => _isRouteDownloaded = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Route downloaded for offline mode.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Download failed: $e')));
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

  Future<void> _loadScheduleWindowSnapshot() async {
    final snapshot =
        await ScheduleWindowService.getRouteScheduleSnapshot(widget.route);
    if (!mounted) return;
    setState(() => _scheduleSnapshot = snapshot);
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
    final summary =
        await RouteService.getRouteFeedbackSummary(widget.route.id);
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
        _scheduleAccurate =
            mine['scheduleAccurate'] ?? _scheduleAccurate;
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
            content:
                Text('Sign in to submit route trust feedback.')),
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
        const SnackBar(
            content: Text('Thanks! Route trust feedback saved.')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit feedback: $e')),
      );
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

  Future<bool> _handleBackPressed() async {
    return _handleBackPressedSection();
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

  void _toggleAutoFollowEnabled() {
    setState(() => _isAutoFollowEnabled = !_isAutoFollowEnabled);
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

  Future<void> _initLocation() async {
    final permission = await Permission.location.request();
    if (permission.isGranted) {
      try {
        _currentPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        _displayPosition =
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
        _displayHeading = _normalizeHeading(_currentPosition!.heading);
        if (mounted) setState(() {});
        _startLocationTracking();
      } catch (e) {
        debugPrint(
            'RouteMapScreen: failed to get current position: $e');
      }
    }
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

    final start =
        LatLng(widget.route.startLat!, widget.route.startLng!);
    final end = LatLng(widget.route.endLat!, widget.route.endLng!);
    if (widget.route.steps.isEmpty) {
      _pathPoints = [start, end];
      return;
    }

    final numSegments = widget.route.steps.length;
    final latStep =
        (end.latitude - start.latitude) / numSegments;
    final lngStep =
        (end.longitude - start.longitude) / numSegments;
    _pathPoints = List.generate(
      numSegments + 1,
      (i) => LatLng(
        start.latitude + latStep * i,
        start.longitude + lngStep * i,
      ),
    );
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

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
          content: Text(
              'Remove your current vote first before voting again'),
        ),
      );
      return;
    }

    setState(() => _isApplyingVote = true);

    try {
      final updatedVote = await RouteService.setUserVote(
        routeId: widget.route.id,
        userId: _currentUserId!,
        isUpvote: isUpvote,
      );

      final latestRoute =
          await RouteService.getRouteById(widget.route.id);
      if (!mounted) return;

      setState(() {
        _userVote = updatedVote;
        if (latestRoute != null) {
          widget.route.upvotes = latestRoute.upvotes;
          widget.route.downvotes = latestRoute.downvotes;
          widget.route.views = latestRoute.views;
        }
      });

      final message = updatedVote == null
          ? 'Vote removed'
          : (updatedVote ? 'Upvoted route' : 'Downvoted route');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 1)),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      final message = e.message == 'remove_first'
          ? 'Remove your current vote first before voting again'
          : 'Unable to save vote right now';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Unable to save vote right now')),
      );
    } finally {
      if (mounted) setState(() => _isApplyingVote = false);
    }
  }

  void _showReportDialog() {
    showRouteReportDialog(
      context,
      onSubmit: (type, description) =>
          _submitReport(type, description),
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
    final unlockedItems =
        await GamificationService.incrementReportsSubmitted(user);
    if (unlockedItems.isNotEmpty) {
      setState(() {
        _pendingNotifications = unlockedItems;
        _showNotificationOverlay = true;
      });
    }

    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report submitted!')),
      );
    }
  }

  void _centerOnCurrentLocation() {
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
        const SnackBar(
            content: Text('Waiting for live location...')),
      );
      return;
    }

    setState(() {
      _isNavigationStarted = true;
      _isAutoFollowEnabled = true;
    });
    _centerOnCurrentLocation();
  }

  void _onNotificationsDismissed() {
    setState(() {
      _showNotificationOverlay = false;
      _pendingNotifications.clear();
    });
  }

  @override
  void dispose() {
    _cameraAnim.dispose();
    _cameraAnimController.dispose();
    _positionSubscription?.cancel();
    super.dispose();
  }

 

  bool get _hasFareSteps =>
      widget.route.steps.any((step) => step.mode != 'Walk');

  double get _fareDiscountMultiplier => _isDiscountFareEnabled ? 0.8 : 1.0;

  bool _isStudentCategory(String category) =>
      category.replaceAll('_', ' ') == 'student';

  double _applyFareDiscount(double fare) => fare * _fareDiscountMultiplier;

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

    final boundaries = widget.route.stepBoundaries.isNotEmpty
        ? widget.route.stepBoundaries
        : _computeEvenBoundaries();
    final startIdx = stepIndex == 0 ? 0 : boundaries[stepIndex - 1];
    final endIdx = stepIndex < boundaries.length
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

  double _calculateRouteFareTotal() {
    double total = 0.0;
    for (int i = 0; i < widget.route.steps.length; i++) {
      final step = widget.route.steps[i];
      if (step.mode == 'Walk') continue;
      final baseFare = step.actualFare ?? _estimateStepFare(i, step);
      total += baseFare;
    }

    if (total <= 0) {
      final parsed = _parseFareAmount(widget.route.price);
      if (parsed != null) total = parsed;
    }

    return _applyFareDiscount(total);
  }

  String? _routeFareLabel() {
    if (!_hasFareSteps && (widget.route.price == null)) return null;
    final totalFare = _calculateRouteFareTotal();
    if (totalFare <= 0) return 'Free';
    return 'PHP ${totalFare.round()}';
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

  List<Polyline> get polylines {
    if (_pathPoints.length < 2) return [];
    if (widget.route.steps.isEmpty) {
      return [
        Polyline(
          points: _pathPoints,
          color: Colors.black,
          strokeWidth: 8.0,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        Polyline(
          points: _pathPoints,
          color: Colors.blue,
          strokeWidth: 6.0,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      ];
    }

    final boundaries = widget.route.stepBoundaries.isNotEmpty
        ? widget.route.stepBoundaries
        : _computeEvenBoundaries();

    final result = <Polyline>[];
    for (int i = 0; i < widget.route.steps.length; i++) {
      final step = widget.route.steps[i];
      final color = modeColors[step.mode] ?? Colors.blue;
      final startIdx = i == 0 ? 0 : boundaries[i - 1];
      final endIdx = i < boundaries.length
          ? boundaries[i]
          : _pathPoints.length - 1;
      if (endIdx > startIdx) {
        final pts = _pathPoints.sublist(startIdx, endIdx + 1);
        result.add(Polyline(
          points: pts,
          color: Colors.black,
          strokeWidth: 8.0,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ));
        result.add(Polyline(
          points: pts,
          color: color,
          strokeWidth: 6.0,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ));
      }
    }
    return result;
  }

  List<int> _computeEvenBoundaries() {
    final total = _pathPoints.length;
    final numSteps = widget.route.steps.length;
    return List.generate(
      numSteps - 1,
      (i) => ((i + 1) * (total - 1) / numSteps).round(),
    );
  }

  List<Marker> get markers {
    final result = <Marker>[];
    if (_pathPoints.isNotEmpty) {
      result.add(Marker(
        point: _pathPoints.first,
        child: const Icon(Icons.location_on,
            color: Colors.green, size: 40),
      ));
    }
    if (_pathPoints.length > 1) {
      result.add(Marker(
        point: _pathPoints.last,
        child:
            const Icon(Icons.flag, color: Colors.red, size: 40),
      ));
    }
    if (_displayPosition != null) {
      result.add(Marker(
        point: _displayPosition!,
        child: Transform.rotate(
          angle: _displayHeading * (math.pi / 180),
          child: const Icon(
            Icons.navigation,
            color: Colors.blue,
            size: 38,
          ),
        ),
      ));
    }
    return result;
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
        PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final navigator = Navigator.of(context);
            final canLeave = await _handleBackPressed();
            if (!mounted || !canLeave) return;
            navigator.pop();
          },
          child: Scaffold(
            backgroundColor: _bg,
            appBar: _buildAppBar(),
            body: Column(
              children: [
                Expanded(flex: 2, child: _buildMapSection(center)),
                Expanded(flex: 1, child: _buildInfoPanel()),
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

  AppBar _buildAppBar() {
    return _buildAppBarSection();
  }

  Widget _buildMapSection(LatLng center) {
    return _buildMapSectionSection(center);
  }

  Widget _buildStartControl() {
    return _buildStartControlSection();
  }

  Widget _buildMapLegend() {
    return _buildMapLegendSection();
  }

  Widget _buildCenterButton() {
    return _buildCenterButtonSection();
  }

  Widget _buildInfoPanel() {
    return _buildInfoPanelSection();
  }

  String? _routeScheduleText() {
    final saved = widget.route.schedule?.trim();
    if (saved != null && saved.isNotEmpty) return saved;

    final transportSteps = widget.route.steps
        .where((s) => s.mode != 'Walk')
        .toList();
    if (transportSteps.isEmpty) return null;

    final has24x7Leg = transportSteps.any((s) => s.is24_7);
    int? earliest;
    int? latest;

    for (final step in transportSteps) {
      if (step.is24_7) continue;
      final start = _parseTimeToMinutes(step.startTime);
      final end = _parseTimeToMinutes(step.endTime);
      if (start == null || end == null) continue;
      earliest =
          earliest == null ? start : math.min(earliest, start);
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
    if (start == null ||
        start.isEmpty ||
        end == null ||
        end.isEmpty) return null;
    return '$start-$end';
  }

  Widget _buildScheduleSummaryChip() {
    return _buildScheduleSummaryChipSection();
  }

  Color _scheduleStateColor(ScheduleWindowState state) {
    switch (state) {
      case ScheduleWindowState.live:
        return const Color(0xFF2D9F63);
      case ScheduleWindowState.stale:
        return const Color(0xFFB8732F);
      case ScheduleWindowState.scheduled:
        return const Color(0xFF2E7CF6);
      case ScheduleWindowState.estimated:
        return const Color(0xFF9B7FE8);
      case ScheduleWindowState.unavailable:
        return _textSecondary;
    }
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

  Widget _buildSectionLabel(String label) =>
      _buildSectionLabelSection(label);
}

// ─── Vote button widget ────────────────────────────────────────────────────────

class _VoteButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _border = Color(0xFFD4E4F7);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);

  const _VoteButton({
    required this.icon,
    required this.count,
    required this.active,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.12)
              : _surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: active
                ? activeColor.withValues(alpha: 0.4)
                : _border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 15,
                color: active ? activeColor : _textSecondary),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? activeColor : _textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}