import 'package:flutter/material.dart';
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
import '../repositories/offline_route_repository.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/route_map/route_report_dialog.dart';

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

class _RouteMapScreenState extends State<RouteMapScreen> {
  static const _skipTrustPromptDateKey = 'route_trust_feedback_skip_until_date';

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
  bool _isExitPromptOpen = false;
  bool _isRouteDownloaded = false;
  bool _isDownloadingRoute = false;

  // ─── Color tokens ────────────────────────────────────────────────────────────
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

  // ─── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadReports();
    _loadEngagementState();
    _generatePathPoints();
    _loadScheduleWindowSnapshot();
    if (widget.enableRouteIntegrity) {
      _loadRouteTrustState();
    }
    _loadDownloadedState();
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

  Future<void> _loadScheduleWindowSnapshot() async {
    final snapshot = await ScheduleWindowService.getRouteScheduleSnapshot(
      widget.route,
    );
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

  Future<void> _loadRouteTrustState() async {
    final summary = await RouteService.getRouteFeedbackSummary(widget.route.id);
    final score = RouteTrustService.computeConfidence(
      route: widget.route,
      feedbackSummary: summary,
    );

    final uid = FirebaseAuth.instance.currentUser?.uid;
    Map<String, bool>? mine;
    if (uid != null && uid.trim().isNotEmpty) {
      mine = await RouteService.getUserRouteQualityFeedback(
        routeId: widget.route.id,
        userId: uid,
      );
    }

    if (!mounted) return;
    setState(() {
      _feedbackSummary = summary;
      _trustScore = score;
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
        const SnackBar(content: Text('Sign in to submit route trust feedback.')),
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
    bool fare = _fareAccurate;
    bool schedule = _scheduleAccurate;
    bool operating = _stillOperating;

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final score = _trustScore ??
                RouteTrustService.computeConfidence(
                  route: widget.route,
                  feedbackSummary: _feedbackSummary,
                );
            final trustLabel = RouteTrustService.confidenceLabel(score.total);
            final trustColor = score.total >= 85
                ? const Color(0xFF2D9F63)
                : score.total >= 65
                    ? const Color(0xFF2E7CF6)
                    : const Color(0xFFE89A3C);

            Widget questionRow({
              required String label,
              required bool value,
              required ValueChanged<bool> onChanged,
            }) {
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => setDialogState(() => onChanged(true)),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: value ? _accent.withValues(alpha: 0.12) : _surfaceAlt,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: value ? _accent.withValues(alpha: 0.35) : _border,
                        ),
                      ),
                      child: Text(
                        'Yes',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: value ? _accent : _textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => setDialogState(() => onChanged(false)),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: !value ? _accent.withValues(alpha: 0.12) : _surfaceAlt,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: !value ? _accent.withValues(alpha: 0.35) : _border,
                        ),
                      ),
                      child: Text(
                        'No',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: !value ? _accent : _textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.verified_outlined, size: 16, color: trustColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Route confidence: ${score.total}/100 ($trustLabel)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: trustColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Before leaving, help improve route reliability with quick trust feedback.',
                      style: TextStyle(
                        fontSize: 11,
                        color: _textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    questionRow(
                      label: 'Fare accurate?',
                      value: fare,
                      onChanged: (v) => fare = v,
                    ),
                    const SizedBox(height: 8),
                    questionRow(
                      label: 'Schedule accurate?',
                      value: schedule,
                      onChanged: (v) => schedule = v,
                    ),
                    const SizedBox(height: 8),
                    questionRow(
                      label: 'Still operating?',
                      value: operating,
                      onChanged: (v) => operating = v,
                    ),
                    const SizedBox(height: 12),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 6,
                      overflowSpacing: 6,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop({
                            'action': 'dismiss',
                            'fareAccurate': fare,
                            'scheduleAccurate': schedule,
                            'stillOperating': operating,
                          }),
                          child: const Text('Dismiss'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop({
                            'action': 'skip_today',
                            'fareAccurate': fare,
                            'scheduleAccurate': schedule,
                            'stillOperating': operating,
                          }),
                          child: const Text('Don\'t ask again today'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(dialogContext).pop({
                            'action': 'submit',
                            'fareAccurate': fare,
                            'scheduleAccurate': schedule,
                            'stillOperating': operating,
                          }),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Submit'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _handleBackPressed() async {
    if (!widget.enableRouteIntegrity) {
      return true;
    }

    if (await _isTrustPromptSkippedToday()) {
      return true;
    }

    if (_isExitPromptOpen) return false;
    _isExitPromptOpen = true;
    try {
      final result = await _showExitTrustFeedbackDialog();
      if (!mounted || result == null) return false;

      final action = (result['action'] as String?) ?? 'dismiss';
      final fare = (result['fareAccurate'] as bool?) ?? _fareAccurate;
      final schedule =
          (result['scheduleAccurate'] as bool?) ?? _scheduleAccurate;
      final operating =
          (result['stillOperating'] as bool?) ?? _stillOperating;

      setState(() {
        _fareAccurate = fare;
        _scheduleAccurate = schedule;
        _stillOperating = operating;
      });

      if (action == 'submit') {
        final ok = await _submitTrustFeedbackValues(
          fareAccurate: fare,
          scheduleAccurate: schedule,
          stillOperating: operating,
        );
        return ok;
      }

      if (action == 'skip_today') {
        await _setTrustPromptSkipToday();
      }

      return true;
    } finally {
      _isExitPromptOpen = false;
    }
  }

  String _todayToken() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<bool> _isTrustPromptSkippedToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_skipTrustPromptDateKey);
      return value == _todayToken();
    } catch (_) {
      return false;
    }
  }

  Future<void> _setTrustPromptSkipToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_skipTrustPromptDateKey, _todayToken());
    } catch (_) {}
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
        setState(() {});
        _startLocationTracking();
      } catch (e) {
        debugPrint('RouteMapScreen: failed to get current position: $e');
      }
    }
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

  Future<void> _loadReports() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/reports.json');
      if (await file.exists()) {
        final contents = await file.readAsString();
        final Map<String, dynamic> jsonData = jsonDecode(contents);
        final List<route_model.Report> loadedReports = [];
        if (jsonData.containsKey(widget.route.id)) {
          final List<dynamic> reportList = jsonData[widget.route.id];
          loadedReports.addAll(
            reportList.map(
              (r) => route_model.Report(
                type: r['type'],
                description: r['description'],
                timestamp: DateTime.fromMillisecondsSinceEpoch(r['timestamp']),
              ),
            ),
          );
        }
        setState(() {
          _routeReports = loadedReports..addAll(widget.route.reports);
          _routeReports.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        });
      } else {
        setState(() => _routeReports = List.from(widget.route.reports));
      }
    } catch (e) {
      setState(() => _routeReports = List.from(widget.route.reports));
    }
  }

  Future<void> _saveReports() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/reports.json');
      Map<String, dynamic> allReports = {};
      if (await file.exists()) {
        allReports = jsonDecode(await file.readAsString());
      }
      allReports[widget.route.id] = _routeReports
          .map((r) => {
                'type': r.type,
                'description': r.description,
                'timestamp': r.timestamp.millisecondsSinceEpoch,
              })
          .toList();
      await file.writeAsString(jsonEncode(allReports));
    } catch (e) {
      debugPrint('RouteMapScreen: failed to save reports locally: $e');
    }
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
      (i) => LatLng(
          start.latitude + latStep * i, start.longitude + lngStep * i),
    );
  }

  // ─── Actions ─────────────────────────────────────────────────────────────────

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
          content:
              Text('Remove your current vote first before voting again'),
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
    if (_displayPosition != null) {
      if (_isNavigationStarted && !_isAutoFollowEnabled) {
        setState(() => _isAutoFollowEnabled = true);
      }
      _mapController.move(
        _displayPosition!,
        15.0,
      );
    }
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
    _positionSubscription?.cancel();
    super.dispose();
  }

  // ─── Computed values ──────────────────────────────────────────────────────────

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
      '${time.hour}:${time.minute.toString().padLeft(2, '0')} ${time.day}/${time.month}';

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
        child:
            const Icon(Icons.location_on, color: Colors.green, size: 40),
      ));
    }
    if (_pathPoints.length > 1) {
      result.add(Marker(
        point: _pathPoints.last,
        child: const Icon(Icons.flag, color: Colors.red, size: 40),
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

  // ─── Build ───────────────────────────────────────────────────────────────────

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
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text(
          'Route Map',
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.map_outlined,
                  size: 36, color: _textSecondary),
            ),
            const SizedBox(height: 16),
            const Text(
              'No route data available',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _surface,
      foregroundColor: _textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: GestureDetector(
        onTap: () async {
          final canLeave = await _handleBackPressed();
          if (!mounted || !canLeave) return;
          Navigator.of(context).pop();
        },
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _surfaceAlt,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _border),
          ),
          child: const Icon(Icons.arrow_back_ios_new,
              size: 15, color: _textSecondary),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.route.startLocation,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            children: [
              const Icon(Icons.arrow_forward,
                  size: 11, color: _textSecondary),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  widget.route.endLocation,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (widget.showDownloadButton)
          GestureDetector(
            onTap: (_isDownloadingRoute || _isRouteDownloaded)
                ? null
                : _downloadRouteForOffline,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _isRouteDownloaded
                    ? _green.withValues(alpha: 0.12)
                    : _accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isRouteDownloaded
                      ? _green.withValues(alpha: 0.35)
                      : _accent.withValues(alpha: 0.3),
                ),
              ),
              child: _isDownloadingRoute
                  ? const Padding(
                      padding: EdgeInsets.all(8.5),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _isRouteDownloaded
                          ? Icons.download_done_rounded
                          : Icons.download_rounded,
                      color: _isRouteDownloaded ? _green : _accent,
                      size: 18,
                    ),
            ),
          ),
        _VoteButton(
          icon: Icons.arrow_upward_rounded,
          count: widget.route.upvotes,
          active: _userVote == true,
          activeColor: _green,
          onTap: _isApplyingVote ? null : () => _vote(true),
        ),
        _VoteButton(
          icon: Icons.arrow_downward_rounded,
          count: widget.route.downvotes,
          active: _userVote == false,
          activeColor: _danger,
          onTap: _isApplyingVote ? null : () => _vote(false),
        ),
        GestureDetector(
          onTap: _showReportDialog,
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _danger.withValues(alpha: 0.25)),
            ),
            child: const Icon(Icons.report_problem_outlined,
                color: _danger, size: 17),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
    );
  }

  Widget _buildMapSection(LatLng center) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 10.0,
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
              userAgentPackageName: 'com.example.app.transitph_beta',
            ),
            MarkerLayer(markers: markers),
            PolylineLayer(polylines: polylines),
          ],
        ),
        Positioned(top: 12, right: 12, child: _buildMapLegend()),
        Positioned(bottom: 12, left: 12, child: _buildStartControl()),
        Positioned(bottom: 12, right: 12, child: _buildCenterButton()),
      ],
    );
  }

  Widget _buildStartControl() {
    if (!_isNavigationStarted) {
      return ElevatedButton.icon(
        onPressed: _startNavigation,
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: const Text('Start'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _isAutoFollowEnabled = !_isAutoFollowEnabled),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isAutoFollowEnabled ? _accent.withValues(alpha: 0.45) : _border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isAutoFollowEnabled
                  ? Icons.gps_fixed_rounded
                  : Icons.gps_not_fixed_rounded,
              color: _isAutoFollowEnabled ? _accent : _textSecondary,
              size: 17,
            ),
            const SizedBox(width: 6),
            Text(
              _isAutoFollowEnabled ? 'Following' : 'Follow paused',
              style: TextStyle(
                color: _isAutoFollowEnabled ? _accent : _textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: modeColors.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: entry.value,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  entry.key,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCenterButton() {
    return GestureDetector(
      onTap: _centerOnCurrentLocation,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(Icons.my_location_rounded,
            color: _accent, size: 20),
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _border, width: 1.5)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMetricsRow(),
          if (_scheduleSnapshot != null) ...[
            const SizedBox(height: 10),
            _buildScheduleSummaryChip(),
          ],
          const SizedBox(height: 16),
          _buildSectionLabel(
              'Route Steps (${widget.route.steps.length})'),
          ...widget.route.steps.asMap().entries.map(
                (e) => _buildStepTile(e.key, e.value),
              ),
          if (_routeReports.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildSectionLabel('Recent Reports'),
            ..._routeReports.map(_buildReportTile),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String? _routeScheduleText() {
    final saved = widget.route.schedule?.trim();
    if (saved != null && saved.isNotEmpty) return saved;

    final transportSteps = widget.route.steps.where((s) => s.mode != 'Walk').toList();
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
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
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
    if (start == null || start.isEmpty || end == null || end.isEmpty) return null;
    return '$start-$end';
  }

  Widget _buildScheduleSummaryChip() {
    final snapshot = _scheduleSnapshot;
    if (snapshot == null) return const SizedBox.shrink();

    final color = _scheduleStateColor(snapshot.state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.timelapse_rounded, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              snapshot.summaryText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
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

  // ─── FIXED: use saved distance fields instead of recalculating ────────────
  Widget _buildMetricsRow() {
    // Priority: distanceMeters (most accurate, from ORS snap-to-road)
    //           → distance string (pre-formatted at submission time)
    //           → recalculate from path points (last resort only)
    final distanceValue = () {
      if (widget.route.distanceMeters != null &&
          widget.route.distanceMeters! > 0) {
        return RouteMetricsService.formatDistance(
            widget.route.distanceMeters! / 1000);
      }
      if (widget.route.distance != null &&
          widget.route.distance!.isNotEmpty) {
        final parsedKm =
            RouteMetricsService.parseDistanceToKm(widget.route.distance);
        if (parsedKm != null) {
          return RouteMetricsService.formatDistance(parsedKm);
        }
        return widget.route.distance!;
      }
      return RouteMetricsService.formatDistance(
          RouteMetricsService.calculateRouteDistance(_pathPoints));
    }();

    final scheduleText = _routeScheduleText();
    final trustScore = _trustScore;
    final trustLabel = trustScore != null
        ? RouteTrustService.confidenceLabel(trustScore.total)
        : 'Loading';
    final trustColor = trustScore == null
        ? _textSecondary
        : trustScore.total >= 85
            ? _green
            : trustScore.total >= 65
                ? _accent
                : const Color(0xFFE89A3C);
    final trustValue = trustScore != null ? '${trustScore.total}/100' : '--';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _metricCard(
            icon: Icons.straighten,
            iconColor: const Color(0xFF9B7FE8),
            label: 'Distance',
            value: distanceValue,
          ),
          if (widget.route.eta != null) ...[
            const SizedBox(width: 10),
            _metricCard(
              icon: Icons.access_time_rounded,
              iconColor: _accent,
              label: 'ETA',
              value: RouteMetricsService.formatEtaLabel(widget.route.eta),
            ),
          ],
          if (widget.route.price != null) ...[
            const SizedBox(width: 10),
            _metricCard(
              icon: Icons.payments_outlined,
              iconColor: _green,
              label: 'Fare',
              value: '${widget.route.price}',
            ),
          ],
          if (scheduleText != null) ...[
            const SizedBox(width: 10),
            _metricCard(
              icon: Icons.schedule_outlined,
              iconColor: const Color(0xFFE89A3C),
              label: 'Schedule',
              value: scheduleText,
            ),
          ],
          if (widget.enableRouteIntegrity) ...[
            const SizedBox(width: 10),
            _metricCard(
              icon: Icons.verified_user_outlined,
              iconColor: trustColor,
              label: 'Integrity ($trustLabel)',
              value: trustValue,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepTile(int idx, route_model.Step step) {
    final modeColor = modeColors[step.mode] ?? _accent;
    final scheduleView = ScheduleWindowService.findStepView(_scheduleSnapshot, idx);
    final stepSchedule = scheduleView?.displayText ?? _stepScheduleText(step);
    final altSuggestion = step.alternateRouteSuggestion?.trim();
    final isTransport = step.mode != 'Walk';
    final estimatedFare = isTransport
        ? RouteMetricsService.calculateFareForMode(step.mode, 1)
        : 0.0;
    final fareValue = step.actualFare ?? estimatedFare;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: modeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: modeColor.withValues(alpha: 0.3)),
                  ),
                  child: Icon(_getModeIcon(step.mode),
                      color: modeColor, size: 18),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _surfaceAlt,
                    shape: BoxShape.circle,
                    border: Border.all(color: _border),
                  ),
                  child: Center(
                    child: Text(
                      '${idx + 1}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.mode,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: modeColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.instruction,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _textPrimary,
                      height: 1.4,
                    ),
                  ),
                  if (step.details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      step.details,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (stepSchedule != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (scheduleView != null
                                ? _scheduleStateColor(scheduleView.state)
                                : const Color(0xFFE89A3C))
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (scheduleView != null
                                  ? _scheduleStateColor(scheduleView.state)
                                  : const Color(0xFFFFD9AE))
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        scheduleView == null
                            ? 'Schedule: $stepSchedule'
                            : stepSchedule,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheduleView != null
                              ? _scheduleStateColor(scheduleView.state)
                              : const Color(0xFF9A5A17),
                        ),
                      ),
                    ),
                  ],
                  if (altSuggestion != null && altSuggestion.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFD54F)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: Color(0xFF7A5800),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              altSuggestion,
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7A5800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (isTransport) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF8F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFB9E4C6)),
                      ),
                      child: Text(
                        'Fare: PHP ${fareValue.toStringAsFixed(0)} '
                        '(${step.actualFare != null ? 'actual' : 'estimated'})',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2D9F63),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportTile(route_model.Report report) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _danger.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(_getReportIcon(report.type),
                  color: _danger, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.type,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  if (report.description != null &&
                      report.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      report.description!,
                      style: const TextStyle(
                          fontSize: 12, color: _textSecondary),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time,
                          size: 11, color: _textSecondary),
                      const SizedBox(width: 3),
                      Text(
                        _formatTime(report.timestamp),
                        style: const TextStyle(
                            fontSize: 11, color: _textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: _textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      );
}

// ─── Vote button widget ───────────────────────────────────────────────────────

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
          color: active ? activeColor.withValues(alpha: 0.12) : _surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color:
                active ? activeColor.withValues(alpha: 0.4) : _border,
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