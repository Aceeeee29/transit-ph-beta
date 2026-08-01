import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../models/route.dart' as route_model;
import '../models/place_model.dart';
import '../services/places_service.dart';
import '../services/routing_service.dart';
import '../services/route_history_service.dart';
import '../services/route_metrics_service.dart';
import '../services/quick_route_link_service.dart';
import '../services/tutorial_service.dart';
import '../services/contribute_route_edit_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/map_controls.dart';
import '../widgets/route_preview.dart';
import '../widgets/route_form_stepper.dart';
import '../widgets/tutorial_overlay.dart';
import '../services/location_service.dart';
import 'contribute_location_search_screen.dart';
import '../widgets/contribute/contribute_dialogs.dart';
import '../widgets/contribute/draggable_step_markers_layer.dart';
import '../widgets/contribute/location_search_bar.dart';
import 'dart:async';
part 'contribute_screen_dialogs.dart';
part 'contribute_screen_map_editor.dart';
part 'contribute_screen_route_builder.dart';

class _StepEditControls {
  final List<List<LatLng>> stepControlPoints;
  final List<LatLng> boundaryWaypoints;
  final List<DraggableStepBodyHandle> bodyHandles;

  const _StepEditControls({
    required this.stepControlPoints,
    required this.boundaryWaypoints,
    required this.bodyHandles,
  });

  factory _StepEditControls.empty() {
    return const _StepEditControls(
      stepControlPoints: [],
      boundaryWaypoints: [],
      bodyHandles: [],
    );
  }
}

class ContributeScreen extends StatefulWidget {
  final Future<void> Function(route_model.Route) onRouteSubmitted;
  final route_model.Route? routeToEdit;
  final String? contributorId;
  final String? quickRouteToken;
  final VoidCallback? onQuickRouteTokenConsumed;

  const ContributeScreen({
    super.key,
    required this.onRouteSubmitted,
    this.routeToEdit,
    this.contributorId,
    this.quickRouteToken,
    this.onQuickRouteTokenConsumed,
  });

  @override
  State<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends State<ContributeScreen> {
  final _formKey = GlobalKey<FormState>();
  final MapController _mapController = MapController();
  final RouteHistoryService _historyService = RouteHistoryService();

  final _startLocationController = TextEditingController();
  final _endLocationController = TextEditingController();
  final _shortDescriptionController = TextEditingController();

  List<LatLng> pathPoints = [];
  List<route_model.Step> steps = [];
  List<String> _selectedRouteTags = [];
  List<int> stepBoundaries = [];
  final List<double?> _stepOrsDistM = [];
  final List<double?> _stepOrsDurS = [];
  double? _pendingOrsDistM;
  double? _pendingOrsDurS;
  int? _pendingStepStartIndex;
  String currentMode = 'Jeepney';
  String selectionMode = 'start';
  String? selectedRegion;
  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;
  bool _isFormExpanded = false;
  bool _snapToRoadEnabled = true;
  bool _showEditHandles = false;
  bool _showTutorial = false;
  LatLng? _searchedLocation;
  String _lastLocationSearchQuery = '';
  String? _activeQuickRouteToken;

  // ─── Zoom slider state ───────────────────────────────────────────────────────
  double _currentZoom = 11.0;
  bool _zoomControlsVisible = false; 
  Timer? _zoomVisibilityTimer;  

  // ─── POI layer state ─────────────────────────────────────────────────────────
  final Set<PlaceCategory> _visiblePoiCategories = {};
  bool _poiFilterVisible = false;

  
  // ─── Color tokens 
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  static const Map<PlaceCategory, IconData> _poiIcons = {
    PlaceCategory.school: Icons.school,
    PlaceCategory.hospital: Icons.local_hospital,
    PlaceCategory.mall: Icons.shopping_bag,
    PlaceCategory.publicPark: Icons.park,
  };

  static const Map<PlaceCategory, Color> _poiColors = {
    PlaceCategory.school: Color(0xFF6A4CFF),
    PlaceCategory.hospital: Color(0xFFE05C6A),
    PlaceCategory.mall: Color(0xFFE89A3C),
    PlaceCategory.publicPark: Color(0xFF3EC97A),
  };

  // ─── CAMANAVA and Metro Manila boundaries ───────────────────────────────────
  // NOTE: these are hand-tuned approximate rectangles, not survey-grade
  // administrative boundaries. CAMANAVA's northern edge is intentionally
  // tightened to exclude North Caloocan (a separate, non-contiguous part of
  // Caloocan City). Because North Caloocan sits at similar latitudes to
  // Valenzuela, this rectangle-based approach may clip a small sliver of
  // Valenzuela's northernmost tip — a known tradeoff of using rectangles
  // instead of true polygon boundaries.
  final Map<String, LatLngBounds> philippineRegions = {
    'Metro Manila': LatLngBounds(
      const LatLng(14.38, 120.82),
      const LatLng(14.95, 121.20),
    ),
    'CAMANAVA': LatLngBounds(
      const LatLng(14.60, 120.92), // tightened north edge — excludes North Caloocan
      const LatLng(14.74, 121.03),
    ),
    'Caloocan': LatLngBounds(
      // South Caloocan only — North Caloocan is a separate, non-contiguous area
      const LatLng(14.62, 120.96),
      const LatLng(14.68, 121.01),
    ),
    'Malabon': LatLngBounds(
      const LatLng(14.63, 120.93),
      const LatLng(14.70, 120.99),
    ),
    'Navotas': LatLngBounds(
      const LatLng(14.63, 120.92),
      const LatLng(14.69, 120.97),
    ),
    'Valenzuela': LatLngBounds(
      const LatLng(14.655, 120.94),
      const LatLng(14.755, 121.02),
    ),
  };

  static const List<String> modes = [
    'Jeepney', 'Bus', 'Train', 'Tricycle', 'FX/Van', 'Walk', 'Ferry',
  ];

  static const List<String> onboardingUserTags = [
    'Student',
    'Employee',
    'Foreigner',
    'New to Area',
  ];

  static const List<String> otherRouteTags = [
    'Tourist',
    'Budget',
    'Fast',
    'Accessible',
  ];

  static const List<String> routeAudienceTags = [
    ...onboardingUserTags,
    ...otherRouteTags,
  ];

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
    _checkTutorialStatus();
    if (widget.quickRouteToken != null && widget.quickRouteToken!.trim().isNotEmpty) {
      _loadQuickRouteLink(widget.quickRouteToken!.trim());
    } else {
      _loadRouteToEdit();
      if (widget.routeToEdit == null) {
        _saveToHistory();
      }
    }
  }

  bool get _isQuickCreateMode => _activeQuickRouteToken != null;

  void _loadRouteToEdit() {
    if (widget.routeToEdit != null) {
      final route = widget.routeToEdit!;
      setState(() {
        pathPoints = List<LatLng>.from(route.pathPoints);
        steps = List<route_model.Step>.from(route.steps);
        _selectedRouteTags = List<String>.from(route.audienceTags);
        stepBoundaries = List<int>.from(route.stepBoundaries);
        _startLocationController.text = route.startLocation;
        _endLocationController.text = route.endLocation;
        _shortDescriptionController.text = route.shortDescription;
        selectionMode = 'done';
      });
      _saveToHistory();
    }
  }

  Future<void> _loadQuickRouteLink(String token) async {
    final payload = await QuickRouteLinkService.getValidLink(token);
    if (!mounted) return;

    widget.onQuickRouteTokenConsumed?.call();

    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This quick route link is invalid or has expired.'),
        ),
      );
      return;
    }

    final route = payload.draftRoute;
    setState(() {
      _activeQuickRouteToken = payload.token;
      pathPoints = List<LatLng>.from(route.pathPoints);
      steps = List<route_model.Step>.from(route.steps);
      _selectedRouteTags = List<String>.from(route.audienceTags);
      stepBoundaries = List<int>.from(route.stepBoundaries);
      _startLocationController.text = route.startLocation;
      _endLocationController.text = route.endLocation;
      _shortDescriptionController.text = route.shortDescription;
      selectionMode = 'done';
    });
    _saveToHistory();
  }

  Future<void> _createQuickLink() async {
    if (pathPoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need at least start and end points on map')),
      );
      return;
    }

    if (!_formKey.currentState!.validate() || !_validateStepReliability()) {
      return;
    }

    final ownerId = FirebaseAuth.instance.currentUser?.uid;
    if (ownerId == null || ownerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to create a quick link.')),
      );
      return;
    }

    try {
      final draftRoute = _buildRoute(existingId: null);
      final token = await QuickRouteLinkService.createLink(
        draftRoute: draftRoute,
        ownerId: ownerId,
      );
      final url = QuickRouteLinkService.buildShareUrl(token);
      await Clipboard.setData(ClipboardData(text: url));

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _QuickLinkDialog(url: url),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Quick link copied: $url'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create quick link: $e')),
      );
    }
  }

  Future<void> _checkTutorialStatus() async {
    final hasSeenTutorial = await TutorialService.hasSeenContributeTutorial();
    if (!hasSeenTutorial && mounted) {
      setState(() {
        _isFormExpanded = true;
        _showTutorial = true;
      });
    }
  }

  void _onTutorialComplete() async {
    await TutorialService.markContributeTutorialAsSeen();
    if (mounted) setState(() => _showTutorial = false);
  }

  void _loadExampleRoute() {
    final exampleRoute = TutorialService.getExampleRoute();
    setState(() {
      pathPoints = List<LatLng>.from(exampleRoute.pathPoints);
      steps = List<route_model.Step>.from(exampleRoute.steps);
      _selectedRouteTags = List<String>.from(exampleRoute.audienceTags);
      stepBoundaries = List<int>.from(exampleRoute.stepBoundaries);
      _startLocationController.text = exampleRoute.startLocation;
      _endLocationController.text = exampleRoute.endLocation;
      _shortDescriptionController.text = exampleRoute.shortDescription;
      selectionMode = 'done';
    });
    _saveToHistory();
  }

  @override
  void dispose() {
    _zoomVisibilityTimer?.cancel();
    _startLocationController.dispose();
    _endLocationController.dispose();
    _shortDescriptionController.dispose();
    super.dispose();
  }

  // ─── Map interaction ─────────────────────────────────────────────────────────

  void _onMapTap(TapPosition tapPosition, LatLng point) async {
    if (selectionMode == 'start') {
      setState(() {
        pathPoints.add(point);
        selectionMode = 'step';
        _showModeDialog();
      });
      _saveToHistory();
      if (_startLocationController.text.isEmpty) {
        final name = await LocationService.getAddressFromCoordinates(
            point.latitude, point.longitude);
        if (mounted && _startLocationController.text.isEmpty) {
          _startLocationController.text = name ??
              '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
        }
      }
    } else if (selectionMode == 'step') {
      if (pathPoints.isNotEmpty) {
        final lastPoint = pathPoints.last;
        _pendingStepStartIndex = pathPoints.length;

        if (_snapToRoadEnabled) {
          try {
            final result = await RoutingService.snapToRoad(
              origin: lastPoint,
              destination: point,
              mode: currentMode,
            );
            if (result != null && result.polyline.isNotEmpty) {
              _pendingOrsDistM = result.distanceMeters;
              _pendingOrsDurS = result.durationSeconds;
              setState(() => pathPoints.addAll(result.polyline));
              _showStepDialog();
              return;
            }
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Snap-to-road failed, using straight line instead'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }

        _pendingOrsDistM = null;
        _pendingOrsDurS = null;
        setState(() => pathPoints.add(point));
        _showStepDialog();
      }
    }
  }

  void _onRegionChanged(String? region) {
    if (region != null && philippineRegions.containsKey(region)) {
      final bounds = philippineRegions[region]!;
      final center = LatLng(
        (bounds.southWest.latitude + bounds.northEast.latitude) / 2,
        (bounds.southWest.longitude + bounds.northEast.longitude) / 2,
      );

      double zoom;
      switch (region) {
        case 'Metro Manila':
          zoom = 9.7;
          break;
        case 'CAMANAVA':
          zoom = 13.0;
          break;
        case 'Malabon':
        case 'Navotas':
          zoom = 14.5; // small, compact cities need a tighter zoom to feel focused
          break;
        case 'Caloocan':
          zoom = 14.0;
          break;
        case 'Valenzuela':
          zoom = 13.5;
          break;
        default:
          zoom = 13.0;
          break;
      } 

      _mapController.move(center, zoom);
      setState(() {
        selectedRegion = region;
        _currentZoom = zoom;
      });
    }
  }

  Future<bool> _onLocationSearched(String query) async {
    final match = await LocationService.getCoordinatesFromAddress(query);
    if (match == null) {
      return false;
    }

    final target = LatLng(match.latitude, match.longitude);
    if (!mounted) {
      return true;
    }

    _mapController.move(target, 15.0);
    setState(() {
      _searchedLocation = target;
      selectedRegion = null;
      _currentZoom = 15.0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Location found and map locked to that place'),
        duration: Duration(seconds: 2),
      ),
    );

    return true;
  }

  Future<void> _openLocationSearchScreen() async {
    await this._openLocationSearchScreenSection();
  }

  // ─── Region border polygon (for the selected-region outline) ────────────────

  List<Polygon> get _regionBoundaryPolygons {
    if (selectedRegion == null) return [];
    final bounds = philippineRegions[selectedRegion];
    if (bounds == null) return [];

    final corners = [
      LatLng(bounds.northEast.latitude, bounds.southWest.longitude), // NW
      LatLng(bounds.northEast.latitude, bounds.northEast.longitude), // NE
      LatLng(bounds.southWest.latitude, bounds.northEast.longitude), // SE
      LatLng(bounds.southWest.latitude, bounds.southWest.longitude), // SW
    ];

    return [
      Polygon(
        points: corners,
        color: _accent.withOpacity(0.08),
        borderColor: _accent,
        borderStrokeWidth: 2.5,
      ),
    ];
  }

  // ─── Dialog launchers ────────────────────────────────────────────────────────

  void _showModeDialog() {
    showDialog(
      context: context,
      builder: (_) => ModeSelectionDialog(
        currentMode: currentMode,
        modes: modes,
        modeColors: modeColors,
        getModeIcon: _getModeIcon,
        onModeSelected: (mode) {
          setState(() => currentMode = mode);
        },
      ),
    );
  }

  void _showStepDialog() {
    showDialog(
      context: context,
      builder: (_) => StepDialog(
        mode: currentMode,
        modeColors: modeColors,
        getModeIcon: _getModeIcon,
        onCancel: _cancelPendingStep,
        onSaved: (step) {
          setState(() {
            steps.add(step);
            stepBoundaries.add(pathPoints.length - 1);
            _stepOrsDistM.add(_pendingOrsDistM);
            _stepOrsDurS.add(_pendingOrsDurS);
            _pendingStepStartIndex = null;
            _pendingOrsDistM = null;
            _pendingOrsDurS = null;
          });
          _saveToHistory();
          _showAddAnotherStepDialog();
        },
      ),
    );
  }

  void _cancelPendingStep() {
    setState(() {
      final rollbackIndex = _pendingStepStartIndex;
      if (rollbackIndex != null &&
          rollbackIndex >= 0 &&
          rollbackIndex < pathPoints.length) {
        pathPoints = pathPoints.sublist(0, rollbackIndex);
      } else if (pathPoints.isNotEmpty) {
        pathPoints.removeLast();
      }
      _pendingStepStartIndex = null;
      _pendingOrsDistM = null;
      _pendingOrsDurS = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || selectionMode != 'step') return;
      _showModeDialog();
    });
  }

  void _showAddAnotherStepDialog() {
    showDialog(
      context: context,
      builder: (_) => AddStepDialog(
        stepCount: steps.length,
        onAddAnother: () => _showModeDialog(),
        onFinished: () async {
          final shouldFinish = await _confirmFinishRoute();
          if (!mounted || !shouldFinish) {
            if (mounted && selectionMode == 'step') {
              _showModeDialog();
            }
            return;
          }

          setState(() => selectionMode = 'done');
          if (_endLocationController.text.isEmpty &&
              pathPoints.isNotEmpty) {
            final last = pathPoints.last;
            final name =
                await LocationService.getAddressFromCoordinates(
                    last.latitude, last.longitude);
            if (mounted && _endLocationController.text.isEmpty) {
              _endLocationController.text = name ??
                  '${last.latitude.toStringAsFixed(5)}, ${last.longitude.toStringAsFixed(5)}';
            }
          }
        },
      ),
    );
  }

  Future<bool> _confirmFinishRoute() async {
    final shouldFinish = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Finish route now?'),
        content: const Text(
          'You can still preview and submit after this. If you need to add more steps, tap Keep Adding.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep Adding'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Finish Route'),
          ),
        ],
      ),
    );

    return shouldFinish ?? false;
  }

  // ─── History controls ────────────────────────────────────────────────────────

  void _onUndo() {
    final prev = _historyService.undo();
    if (prev != null) {
      setState(() {
        pathPoints = prev.pathPoints;
        steps = prev.steps;
        stepBoundaries = prev.stepBoundaries;
        selectionMode = prev.selectionMode;
        if (selectionMode != 'done') {
          _showEditHandles = false;
        }
        _syncStepMetricsWithSteps();
      });
    }
  }

  void _onRedo() {
    final next = _historyService.redo();
    if (next != null) {
      setState(() {
        pathPoints = next.pathPoints;
        steps = next.steps;
        stepBoundaries = next.stepBoundaries;
        selectionMode = next.selectionMode;
        if (selectionMode != 'done') {
          _showEditHandles = false;
        }
        _syncStepMetricsWithSteps();
      });
    }
  }

  void _syncStepMetricsWithSteps() {
    if (_stepOrsDistM.length > steps.length) {
      _stepOrsDistM.removeRange(steps.length, _stepOrsDistM.length);
    }
    if (_stepOrsDurS.length > steps.length) {
      _stepOrsDurS.removeRange(steps.length, _stepOrsDurS.length);
    }

    while (_stepOrsDistM.length < steps.length) {
      _stepOrsDistM.add(null);
    }
    while (_stepOrsDurS.length < steps.length) {
      _stepOrsDurS.add(null);
    }

    _pendingStepStartIndex = null;
    _pendingOrsDistM = null;
    _pendingOrsDurS = null;
  }

  void _onReset() {
    setState(() {
      pathPoints = [];
      steps = [];
      stepBoundaries = [];
      _stepOrsDistM.clear();
      _stepOrsDurS.clear();
      _pendingStepStartIndex = null;
      _pendingOrsDistM = null;
      _pendingOrsDurS = null;
      selectionMode = 'start';
      _showEditHandles = false;
      _startLocationController.clear();
      _endLocationController.clear();
      _shortDescriptionController.clear();
      _selectedRouteTags = [];
      _searchedLocation = null;
      _lastLocationSearchQuery = '';
    });
    _historyService.clear();
  }

  void _saveToHistory() {
    _historyService.addState(
      List<LatLng>.from(pathPoints),
      List<route_model.Step>.from(steps),
      List<int>.from(stepBoundaries),
      selectionMode,
    );
  }

  void _onNotificationsDismissed() {
    setState(() {
      _showNotificationOverlay = false;
      _pendingNotifications.clear();
    });
  }

  void _onSnapToRoadToggled(bool enabled) {
    setState(() => _snapToRoadEnabled = enabled);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Snap to road enabled - routes will follow roads'
              : 'Snap to road disabled - routes will use straight lines',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleEditHandles() {
    if (selectionMode != 'done' || steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Finish adding steps first to edit route handles.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _showEditHandles = !_showEditHandles);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _showEditHandles
            ? 'Edit handles enabled. Drag markers to adjust route.'
              : 'Edit handles disabled.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─── Route utilities ─────────────────────────────────────────────────────────

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

  double _speedForMode(String mode) {
    switch (mode) {
      case 'Walk':
        return 5.0;
      case 'Jeepney':
        return 20.0;
      case 'Bus':
        return 25.0;
      case 'Train':
        return 40.0;
      case 'Tricycle':
        return 15.0;
      case 'FX/Van':
        return 30.0;
      case 'Ferry':
        return 20.0;
      default:
        return 5.0;
    }
  }

  DateTime? _parseTimeValue(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(2000, 1, 1, hour, minute);
  }

  String _deriveRouteSchedule(List<route_model.Step> routeSteps) {
    if (routeSteps.isEmpty) return 'Schedule not provided';

    final transportSteps = routeSteps.where((s) => s.mode != 'Walk').toList();
    if (transportSteps.isEmpty) return 'Walk-only route';

    final has24x7Leg = transportSteps.any((s) => s.is24_7);
    DateTime? earliest;
    DateTime? latest;

    for (final step in transportSteps) {
      if (step.is24_7) continue;
      final start = _parseTimeValue(step.startTime);
      final end = _parseTimeValue(step.endTime);
      if (start != null && (earliest == null || start.isBefore(earliest))) {
        earliest = start;
      }
      if (end != null && (latest == null || end.isAfter(latest))) {
        latest = end;
      }
    }

    if (earliest != null && latest != null) {
      final startLabel = TimeOfDay(hour: earliest.hour, minute: earliest.minute)
          .format(context);
      final endLabel = TimeOfDay(hour: latest.hour, minute: latest.minute)
          .format(context);
      return has24x7Leg
          ? '$startLabel - $endLabel (some legs run 24/7)'
          : '$startLabel - $endLabel';
    }

    if (has24x7Leg) return '24/7';
    return 'Schedule varies by step';
  }

  List<Polyline> get polylines {
    final result = <Polyline>[];
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final color = modeColors[step.mode] ?? Colors.blue;
      final startIdx = (i == 0) ? 0 : stepBoundaries[i - 1];
      final endIdx = (i < stepBoundaries.length)
          ? stepBoundaries[i]
          : pathPoints.length - 1;
      if (endIdx > startIdx) {
        final pts = pathPoints.sublist(startIdx, endIdx + 1);
        result.add(Polyline(
          points: pts,
          color: Colors.black.withOpacity(0.5),
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

  int _clampPathIndex(int index) {
    return this._clampPathIndexSection(index);
  }

  int _pickStepBodyHandleIndex(int startIdx, int endIdx) {
    return this._pickStepBodyHandleIndexSection(startIdx, endIdx);
  }

  _StepEditControls get _stepEditControls {
    return this._stepEditControlsSection;
  }

  Future<void> _rebuildFromStepControls(
    List<List<LatLng>> stepControlPoints,
  ) async {
    await this._rebuildFromStepControlsSection(stepControlPoints);
  }

  Future<void> _onBoundaryWaypointDragEnd(int index, LatLng updatedPoint) async {
    await this._onBoundaryWaypointDragEndSection(index, updatedPoint);
  }

  Future<void> _onBodyHandleDragEnd(
    int stepIndex,
    int controlIndex,
    LatLng updatedPoint,
  ) async {
    await this._onBodyHandleDragEndSection(
      stepIndex,
      controlIndex,
      updatedPoint,
    );
  }

  route_model.Route _buildRoute({String? existingId}) {
    return this._buildRouteSection(existingId: existingId);
  }

  bool _validateStepReliability() {
    return this._validateStepReliabilitySection();
  }

  void _resetAfterSubmitSuccess() {
    setState(() {
      pathPoints = [];
      steps = [];
      stepBoundaries = [];
      selectionMode = 'start';
      _showEditHandles = false;
      _startLocationController.clear();
      _endLocationController.clear();
      _shortDescriptionController.clear();
      _selectedRouteTags = [];
    });
  }

  void _showTutorialOverlay() {
    setState(() => _showTutorial = true);
  }

  void _toggleFormExpanded() {
    setState(() => _isFormExpanded = !_isFormExpanded);
  }

  void _setSelectedRouteTags(List<String> tags) {
    setState(() => _selectedRouteTags = tags);
  }

  // ─── Submit ──────────────────────────────────────────────────────────────────

  void _submit({bool forceModeration = false}) async {
    await this._submitSection(forceModeration: forceModeration);
  }

  void _submitForReviewInstead() {
    _submit(forceModeration: true);
  }

  // ─── Preview route ───────────────────────────────────────────────────────────

  void _onPreviewRoute() {
    this._onPreviewRouteSection();
  }


  void _revealZoomControls() {          
    setState(() => _zoomControlsVisible = true);
    _zoomVisibilityTimer?.cancel();
    _zoomVisibilityTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _zoomControlsVisible = false);
    });
  }

  // ─── POI (nearby places) overlay layer ───────────────────────────────────────

  List<Place> get _visiblePois {
    if (_visiblePoiCategories.isEmpty) return const [];

    LatLngBounds bounds;
    try {
      bounds = _mapController.camera.visibleBounds;
    } catch (_) {
      bounds = LatLngBounds(
        const LatLng(14.38, 120.82),
        const LatLng(14.95, 121.20),
      );
    }

    return PlacesService.allPlaces.where((p) {
      if (!_visiblePoiCategories.contains(p.category)) return false;
      return bounds.contains(LatLng(p.latitude, p.longitude));
    }).toList();
  }

  void _togglePoiCategory(PlaceCategory category) {
    setState(() {
      if (!_visiblePoiCategories.add(category)) {
        _visiblePoiCategories.remove(category);
      }
    });
  }

  void _togglePoiFilterPanel() {
    setState(() => _poiFilterVisible = !_poiFilterVisible);
  }

  Widget _buildPoiFilterControls() {
    return Positioned(
      right: 12,
      top: 60,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: _togglePoiFilterPanel,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _poiFilterVisible ? _accent : _surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _poiFilterVisible ? _accent : _border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                _poiFilterVisible
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
                size: 18,
                color: _poiFilterVisible ? Colors.white : _accent,
              ),
            ),
          ),
          if (_poiFilterVisible) ...[
            const SizedBox(height: 8),
            Container(
              width: 172,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _surface.withValues(alpha: 0.98),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'POI Layers',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...PlaceCategory.values.map((cat) {
                    final isOn = _visiblePoiCategories.contains(cat);
                    return GestureDetector(
                      onTap: () => _togglePoiCategory(cat),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Icon(
                              _poiIcons[cat],
                              size: 15,
                              color:
                                  isOn ? _poiColors[cat] : _textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                cat.iconLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isOn ? _textPrimary : _textSecondary,
                                ),
                              ),
                            ),
                            Icon(
                              isOn
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              size: 16,
                              color: isOn ? _accent : _border,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Vertical zoom slider ────────────────────────────────────────────────────

  Widget _buildVerticalZoomSlider() {
  return Positioned(
    right: 12,
    top: 140,
    bottom: 160,
    child: IgnorePointer(
      ignoring: !_zoomControlsVisible,
      child: AnimatedOpacity(
        opacity: _zoomControlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: _revealZoomControls,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  _revealZoomControls();
                  final z = (_currentZoom + 1).clamp(9.0, 18.0);
                  setState(() => _currentZoom = z);
                  _mapController.move(_mapController.camera.center, z);
                },
                child: const Icon(Icons.add_circle, size: 22, color: _accent),
              ),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: _accent,
                      inactiveTrackColor: _border,
                      thumbColor: _accent,
                      overlayColor: _accent.withOpacity(0.15),
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      min: 9.0,
                      max: 18.0,
                      value: _currentZoom.clamp(9.0, 18.0),
                      onChanged: (value) {
                        _revealZoomControls();
                        setState(() {
                          _currentZoom = value;
                          selectedRegion = null;
                        });
                        _mapController.move(_mapController.camera.center, value);
                      },
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  _revealZoomControls();
                  final z = (_currentZoom - 1).clamp(9.0, 18.0);
                  setState(() => _currentZoom = z);
                  _mapController.move(_mapController.camera.center, z);
                },
                child: const Icon(Icons.remove_circle, size: 22, color: _accent),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: _bg,
          appBar: _buildAppBar(),
          body: SafeArea(
            child: Stack(
              children: [
                _buildMapLayer(),
                _buildMapControlsOverlay(),
                if (selectionMode != 'done') _buildInstructionPill(),
                _buildLocationSearchBar(),
                _buildRegionSelector(),
                _buildPoiFilterControls(),
                _buildVerticalZoomSlider(),
                _buildFormDrawer(context),
              ],
            ),
          ),
        ),
        if (_showNotificationOverlay)
          NotificationOverlay(
            notifications: _pendingNotifications,
            onAllDismissed: _onNotificationsDismissed,
          ),
        if (_showTutorial)
          TutorialOverlay(
            steps: TutorialService.getContributeTutorialSteps(),
            onComplete: _onTutorialComplete,
            onExampleRouteRequested: _loadExampleRoute,
          ),
      ],
    );
  }

  AppBar _buildAppBar() {
    return this._buildAppBarSection();
  }

  Widget _buildMapLayer() {
    return this._buildMapLayerSection();
  }

  Widget _buildMapControlsOverlay() {
    return this._buildMapControlsOverlaySection();
  }

  Widget _buildInstructionPill() {
    return this._buildInstructionPillSection();
  }

  Widget _buildRegionSelector() {
    return this._buildRegionSelectorSection();
  }

  Widget _buildLocationSearchBar() {
    return this._buildLocationSearchBarSection();
  }

  Widget _buildFormDrawer(BuildContext context) {
    return this._buildFormDrawerSection(context);
  }

  Widget _buildDrawerHandle() {
    return this._buildDrawerHandleSection();
  }

  Widget _buildFormContent() {
    return this._buildFormContentSection();
  }
}