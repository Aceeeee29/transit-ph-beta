import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/route.dart' as route_model;
import '../models/place.dart';
import '../models/location_search_result.dart';
import '../services/routing_service.dart';
import '../services/route_history_service.dart';
import '../services/route_metrics_service.dart';
import '../services/gamification_service.dart';
import '../services/quick_route_link_service.dart';
import '../services/tutorial_service.dart';
import '../services/contribute_route_edit_service.dart';
import '../data/camanava_places.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/map_controls.dart';
import '../widgets/route_preview.dart';
import '../widgets/route_form_stepper.dart';
import '../widgets/tutorial_overlay.dart';
import '../services/location_service.dart';
import '../utils/map_distance.dart';
import 'contribute_location_search_screen.dart';
import '../widgets/contribute/contribute_dialogs.dart';
import '../widgets/contribute/draggable_step_markers_layer.dart';
import '../widgets/contribute/location_search_bar.dart';
import '../widgets/translated_text.dart';
import '../widgets/location_permission_notice.dart';
import 'dart:async';
part 'contribute_screen_dialogs.dart';
part 'contribute_screen_map_editor.dart';
part 'contribute_screen_route_builder.dart';

/// What the Map tab is currently showing. The map itself is shared — only the
/// overlay UI and draw behaviour swap when the user toggles.
enum MapTabMode { contribute, nearby }

class _StepEditControls {
  final List<List<LatLng>> stepControlPoints;
  final List<LatLng> boundaryWaypoints;
  final List<DraggableStepBodyHandle> bodyHandles;
  final List<DraggableStepBodyHandle> insertHandles;

  const _StepEditControls({
    required this.stepControlPoints,
    required this.boundaryWaypoints,
    required this.bodyHandles,
    this.insertHandles = const [],
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
  final MapTabMode mapMode;
  final ValueChanged<MapTabMode>? onMapModeChanged;

  /// A route to start from that is submitted as a new route (e.g. a ride
  /// recorded while following), unlike [routeToEdit] which updates one.
  final route_model.Route? draftRoute;

  /// When set, the submitted route is a suggested correction of this route.
  final String? correctionOf;

  const ContributeScreen({
    super.key,
    required this.onRouteSubmitted,
    this.draftRoute,
    this.correctionOf,
    this.routeToEdit,
    this.contributorId,
    this.quickRouteToken,
    this.onQuickRouteTokenConsumed,
    this.mapMode = MapTabMode.contribute,
    this.onMapModeChanged,
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
  List<double?> _stepOrsDistM = [];
  List<double?> _stepOrsDurS = [];
  bool _isPlacingStep = false;
  String currentMode = 'Jeepney';
  String selectionMode = 'start';
  String? selectedRegion = 'CAMANAVA';
  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;
  bool _isFormExpanded = false;
  bool _snapToRoadEnabled = true;

  /// The contributor's "Allow expressways" choice; null follows the mode's
  /// default. Not saved with the route: the drawn line itself is what
  /// records where the vehicle goes.
  bool? _expresswayOverride;

  bool get _allowExpressways =>
      _expresswayOverride ??
      RoutingService.defaultAllowsExpressways(currentMode);

  /// The step being drawn: its start, then each tap, in order. Empty when
  /// no step is open. An open step extends with every tap and can be
  /// adjusted by dragging before "Save step" asks for its details.
  List<LatLng> _openStepControls = [];
  String _openStepMode = 'Jeepney';

  bool get _hasOpenStep => _openStepControls.length >= 2;

  /// Saved steps plus the open one, which acts as the last step.
  int get _stepCount => steps.length + (_hasOpenStep ? 1 : 0);

  List<LatLng> _controlsForStep(int index) =>
      index < steps.length ? steps[index].controlPoints : _openStepControls;

  String _modeForStep(int index) =>
      index < steps.length ? steps[index].mode : _openStepMode;
  bool _showEditHandles = false;
  bool _showPins = true;
  bool _showTutorial = false;
  late MapTabMode _mapMode;
  LatLng? _searchedLocation;
  String _lastLocationSearchQuery = '';
  String? _activeQuickRouteToken;

  // ─── Nearby-places mode state ───────────────────────────────────────────────
  Position? _nearbyPosition;
  bool _nearbyIsLocating = false;
  Place? _nearbySelectedPlace;
  final Set<PlaceCategory> _nearbySelected = {PlaceCategory.tourist};
  LatLng? _debugCoord;

  // ─── Zoom slider state ───────────────────────────────────────────────────────
  double _currentZoom = 11.0;
  bool _zoomControlsVisible = false;
  Timer? _zoomVisibilityTimer;

  // ─── Color tokens
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

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
      const LatLng(
        14.60,
        120.92,
      ), // tightened north edge — excludes North Caloocan
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
    'Jeepney',
    'Bus',
    'Train',
    'Tricycle',
    'FX/Van',
    'Walk',
    'Ferry',
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
    _mapMode = widget.mapMode;
    _checkTutorialStatus();
    if (widget.quickRouteToken != null &&
        widget.quickRouteToken!.trim().isNotEmpty) {
      _loadQuickRouteLink(widget.quickRouteToken!.trim());
    } else {
      _loadRouteToEdit();
      if (widget.routeToEdit == null) {
        _saveToHistory();
      }
    }
  }

  @override
  void didUpdateWidget(covariant ContributeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mapMode != _mapMode) {
      _mapMode = widget.mapMode;
      _onMapModeApplied(_mapMode);
    }
  }

  /// Camera + housekeeping when the mode actually flips.
  void _onMapModeApplied(MapTabMode mode) {
    if (mode == MapTabMode.nearby) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(
            CamanavaBounds.center,
            CamanavaBounds.initialZoom,
          );
        }
      });
    }
  }

  /// Programmatic mode flip — used by the in-screen toggle.
  void _switchMapMode(MapTabMode mode) {
    if (_mapMode == mode) return;
    setState(() => _mapMode = mode);
    widget.onMapModeChanged?.call(mode);
    _onMapModeApplied(mode);
  }

  bool get _isQuickCreateMode => _activeQuickRouteToken != null;

  void _loadRouteToEdit() {
    final route = widget.routeToEdit ?? widget.draftRoute;
    if (route != null) {
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
          content: TranslatedText(
            'This quick route link is invalid or has expired.',
          ),
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
        const SnackBar(
          content: TranslatedText('Need at least start and end points on map'),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate() || !_validateStepReliability()) {
      return;
    }

    final ownerId = FirebaseAuth.instance.currentUser?.uid;
    if (ownerId == null || ownerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText('Please sign in to create a quick link.'),
        ),
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
    if (_mapMode == MapTabMode.nearby) {
      setState(() => _debugCoord = point);
      return;
    }

    if (selectionMode == 'start') {
      setState(() {
        pathPoints.add(point);
        selectionMode = 'step';
      });
      _saveToHistory();
      if (_startLocationController.text.isEmpty) {
        final name = await LocationService.getAddressFromCoordinates(
          point.latitude,
          point.longitude,
        );
        if (mounted && _startLocationController.text.isEmpty) {
          _startLocationController.text =
              name ??
              '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
        }
      }
    } else if (selectionMode == 'step') {
      if (pathPoints.isEmpty || _isPlacingStep) return;
      _isPlacingStep = true;
      try {
        await _extendOpenStep(point);
      } finally {
        _isPlacingStep = false;
      }
    }
  }

  /// Opens a step at the end of the route (in the current mode) or extends
  /// the open one to [point]. Each tap is its own short piece, so a long
  /// ride drawn tap by tap follows the vehicle's real roads instead of
  /// whatever the router picks across one long jump.
  Future<void> _extendOpenStep(LatLng point) async {
    final opening = !_hasOpenStep;
    final mode = opening ? currentMode : _openStepMode;
    final from = opening ? pathPoints.last : _openStepControls.last;
    final piece = await ContributeRouteEditService.pieceRouter(
      mode: mode,
      snapToRoadEnabled: _snapToRoadEnabled,
      allowExpressways: _allowExpressways,
    )(from, point);
    if (!mounted) return;

    setState(() {
      if (opening) {
        _openStepMode = mode;
        _openStepControls = [from];
      }
      pathPoints.addAll(
        pathPoints.isNotEmpty && piece.first == pathPoints.last
            ? piece.skip(1)
            : piece,
      );
      // Where the line actually ends: on the road for vehicles, even when
      // the tap was off it.
      _openStepControls = [..._openStepControls, piece.last];
    });
    if (_snapToRoadEnabled && piece.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText(
            'Could not follow the roads here, using a straight line.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Removes the open step's last tapped point (and its piece); discards
  /// the step when only one piece is left.
  void _undoOpenStepPoint() {
    if (!_hasOpenStep) return;
    if (_openStepControls.length <= 2) {
      _discardOpenStep();
      return;
    }
    final openStart = steps.isEmpty ? 0 : stepBoundaries.last;
    final geometry = StepGeometry.fromPath(
      _stepPath(steps.length),
      _openStepControls,
    );
    final kept = geometry.pieces.sublist(0, geometry.pieces.length - 1);
    final keptPath = <LatLng>[];
    for (final piece in kept) {
      keptPath.addAll(
        keptPath.isNotEmpty && piece.first == keptPath.last
            ? piece.skip(1)
            : piece,
      );
    }
    setState(() {
      pathPoints = [...pathPoints.sublist(0, openStart), ...keptPath];
      _openStepControls = _openStepControls.sublist(
        0,
        _openStepControls.length - 1,
      );
    });
  }

  void _discardOpenStep() {
    setState(() {
      // Back to where the last saved step ended (or the start point).
      final keep = steps.isEmpty ? 1 : stepBoundaries.last + 1;
      if (keep < pathPoints.length) pathPoints = pathPoints.sublist(0, keep);
      _openStepControls = [];
    });
  }

  /// Asks for the open step's details, then saves it with its points.
  void _saveOpenStep() {
    if (!_hasOpenStep) return;
    showDialog(
      context: context,
      builder:
          (_) => StepDialog(
            mode: _openStepMode,
            modeColors: modeColors,
            getModeIcon: _getModeIcon,
            stepPath: _stepPath(steps.length),
            // Cancelling keeps the step open for more drawing.
            onCancel: () {},
            onSaved: (step) {
              setState(() {
                steps.add(step.copyWith(controlPoints: _openStepControls));
                stepBoundaries.add(pathPoints.length - 1);
                // Measured from the drawn line when the route is built.
                _stepOrsDistM.add(null);
                _stepOrsDurS.add(null);
                _openStepControls = [];
              });
              _saveToHistory();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Step ${steps.length} saved. Tap the map to start the '
                    'next step, or tap Finish Route.',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
    );
  }

  /// POI/nearby-place pin scale for the current zoom: 0 (hidden) below
  /// [_pinHideZoom] so a wide-out view isn't swamped with markers, ramping
  /// up to full size by [_pinFullSizeZoom].
  static const double _pinHideZoom = 10.5;
  static const double _pinFullSizeZoom = 13.5;

  double get _poiPinScale {
    final t = (_currentZoom - _pinHideZoom) / (_pinFullSizeZoom - _pinHideZoom);
    return t.clamp(0.0, 1.0);
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
          zoom =
              14.5; // small, compact cities need a tighter zoom to feel focused
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
        content: TranslatedText('Location found and map locked to that place'),
        duration: Duration(seconds: 2),
      ),
    );

    return true;
  }

  void _onLocationPicked(double lat, double lng, String name) {
    final target = LatLng(lat, lng);
    if (!mounted) return;
    _mapController.move(target, 15.0);
    setState(() {
      _searchedLocation = target;
      _lastLocationSearchQuery = name;
      selectedRegion = null;
      _currentZoom = 15.0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Showing $name'),
        duration: const Duration(seconds: 2),
      ),
    );
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

  /// The drawn line of step [index] (or of the step being added, which runs
  /// from the previous step's end to the end of the path).
  List<LatLng> _stepPath(int index) {
    if (pathPoints.length < 2) return const [];
    final start = index == 0 ? 0 : stepBoundaries[index - 1];
    final end =
        index < stepBoundaries.length
            ? stepBoundaries[index]
            : pathPoints.length - 1;
    if (start < 0 || end >= pathPoints.length || end <= start) return const [];
    return pathPoints.sublist(start, end + 1);
  }

  Future<void> _onFinishRoutePressed() async {
    if (_hasOpenStep) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText(
            'Save or discard the step you are drawing first.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final shouldFinish = await _confirmFinishRoute();
    if (!mounted || !shouldFinish) return;

    setState(() => selectionMode = 'done');
    if (_endLocationController.text.isEmpty && pathPoints.isNotEmpty) {
      final last = pathPoints.last;
      final name = await LocationService.getAddressFromCoordinates(
        last.latitude,
        last.longitude,
      );
      if (mounted && _endLocationController.text.isEmpty) {
        setState(() {
          _endLocationController.text =
              name ??
              '${last.latitude.toStringAsFixed(5)}, ${last.longitude.toStringAsFixed(5)}';
        });
      }
    }
  }

  void _showEditStepDialog(int index) {
    if (index < 0 || index >= steps.length) return;
    final step = steps[index];
    showDialog(
      context: context,
      builder:
          (_) => StepDialog(
            mode: step.mode,
            modeColors: modeColors,
            getModeIcon: _getModeIcon,
            initialStep: step,
            stepPath: _stepPath(index),
            onCancel: () {},
            onSaved: (updated) {
              // The dialog edits details only; keep the line's points.
              setState(
                () =>
                    steps[index] = updated.copyWith(
                      controlPoints: steps[index].controlPoints,
                    ),
              );
              _saveToHistory();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: TranslatedText('Step updated.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
    );
  }

  Future<void> _deleteStep(int index) async {
    if (index < 0 || index >= steps.length) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const TranslatedText('Remove this step?'),
            content: Text(
              '${steps[index].instruction} will be removed and the remaining steps reconnected.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const TranslatedText('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const TranslatedText('Remove'),
              ),
            ],
          ),
    );
    if (!mounted || confirm != true) return;

    final remaining = List<route_model.Step>.from(steps)..removeAt(index);
    if (remaining.isEmpty) {
      _onReset();
      return;
    }

    // Every other step keeps its exact line; only the gap is reconnected
    // by re-routing the first piece of the step that followed.
    final geometries = [
      for (var i = 0; i < steps.length; i++) _stepGeometrySection(i),
    ]..removeAt(index);
    final distances = List<double?>.from(_stepOrsDistM);
    final durations = List<double?>.from(_stepOrsDurS);
    if (index < distances.length) distances.removeAt(index);
    if (index < durations.length) durations.removeAt(index);
    if (index > 0 && index < geometries.length) {
      geometries[index] = await geometries[index].moveControl(
        0,
        geometries[index - 1].controls.last,
        ContributeRouteEditService.pieceRouter(
          mode: remaining[index].mode,
          snapToRoadEnabled: _snapToRoadEnabled,
          allowExpressways: _expresswayOverride,
        ),
      );
      if (index < distances.length) distances[index] = null;
      if (index < durations.length) durations[index] = null;
    }
    if (!mounted) return;

    final newPath = <LatLng>[];
    final newBoundaries = <int>[];
    for (final geometry in geometries) {
      final stepPath = geometry.path;
      if (newPath.isNotEmpty &&
          stepPath.isNotEmpty &&
          newPath.last == stepPath.first) {
        newPath.addAll(stepPath.skip(1));
      } else {
        newPath.addAll(stepPath);
      }
      newBoundaries.add(newPath.isEmpty ? 0 : newPath.length - 1);
    }

    setState(() {
      steps = [
        for (var i = 0; i < remaining.length; i++)
          remaining[i].copyWith(controlPoints: geometries[i].controls),
      ];
      pathPoints = newPath;
      stepBoundaries = newBoundaries;
      _stepOrsDistM = distances;
      _stepOrsDurS = durations;
    });
    _saveToHistory();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: TranslatedText('Step removed.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _moveStep(int index, int delta) async {
    final target = index + delta;
    if (index < 0 ||
        index >= steps.length ||
        target < 0 ||
        target >= steps.length) {
      return;
    }

    final reordered = List<route_model.Step>.from(steps);
    final moved = reordered.removeAt(index);
    reordered.insert(target, moved);

    final controlPoints = _stepEditControls.stepControlPoints;
    if (index >= controlPoints.length) return;
    final movedCp = controlPoints.removeAt(index);
    controlPoints.insert(target, movedCp);

    final rebuilt =
        await ContributeRouteEditService.rebuildFromStepControlPoints(
          steps: reordered,
          stepControlPoints: controlPoints,
          snapToRoadEnabled: _snapToRoadEnabled,
          allowExpressways: _expresswayOverride,
        );
    if (!mounted) return;

    setState(() {
      steps = reordered;
      pathPoints = rebuilt.pathPoints;
      stepBoundaries = rebuilt.stepBoundaries;
      _stepOrsDistM = rebuilt.stepOrsDistM;
      _stepOrsDurS = rebuilt.stepOrsDurS;
    });
    _saveToHistory();
  }

  Future<bool> _confirmFinishRoute() async {
    final shouldFinish = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const TranslatedText('Finish route now?'),
            content: const TranslatedText(
              'You can still preview and submit after this. If you need to add more steps, tap Keep Adding.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const TranslatedText('Keep Adding'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const TranslatedText('Finish Route'),
              ),
            ],
          ),
    );

    return shouldFinish ?? false;
  }

  Future<bool> _confirmDiscardRouteProgress() async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const TranslatedText('Discard this route?'),
            content: const TranslatedText(
              'Going back now will lose the points and steps you\'ve placed. This can\'t be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const TranslatedText('Keep Editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const TranslatedText('Discard'),
              ),
            ],
          ),
    );

    return shouldDiscard ?? false;
  }

  // ─── History controls ────────────────────────────────────────────────────────

  void _onUndo() {
    // While drawing a step, undo takes back its last point first.
    if (_hasOpenStep) {
      _undoOpenStepPoint();
      return;
    }
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
    if (_hasOpenStep) return;
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

  }

  void _onReset() {
    setState(() {
      pathPoints = [];
      steps = [];
      stepBoundaries = [];
      _stepOrsDistM.clear();
      _stepOrsDurS.clear();
      _openStepControls = [];
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
        content: TranslatedText(
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
          content: TranslatedText(
            'Finish adding steps first to edit route handles.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _showEditHandles = !_showEditHandles);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: TranslatedText(
          _showEditHandles
              ? 'Edit handles enabled. Drag markers to adjust route.'
              : 'Edit handles disabled.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _togglePins() {
    setState(() => _showPins = !_showPins);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: TranslatedText(
          _showPins ? 'Pins shown on map.' : 'Pins hidden on map.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─── Route utilities ─────────────────────────────────────────────────────────

  /// setState bridge for extension part files (e.g. contribute_screen_route_builder).
  void _setUiState(VoidCallback fn) => setState(fn);

  /// Called once per newly-submitted (non-edit) route so the Profile counters
  /// (routes contributed + total distance ridden) stay in sync with Firestore.
  Future<void> _bumpContributionStats() async {
    try {
      final user = await GamificationService.loadUser();
      await GamificationService.incrementRoutesContributed(user);
      await GamificationService.recalculateUserStats(user);
    } catch (_) {
      // Stats are best-effort; never block the submit flow on them.
    }
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
      final startLabel = TimeOfDay(
        hour: earliest.hour,
        minute: earliest.minute,
      ).format(context);
      final endLabel = TimeOfDay(
        hour: latest.hour,
        minute: latest.minute,
      ).format(context);
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
      final endIdx =
          (i < stepBoundaries.length)
              ? stepBoundaries[i]
              : pathPoints.length - 1;
      if (endIdx > startIdx) {
        final pts = pathPoints.sublist(startIdx, endIdx + 1);
        result.add(
          Polyline(
            points: pts,
            color: Colors.black.withOpacity(0.5),
            strokeWidth: 8.0,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
        result.add(
          Polyline(
            points: pts,
            color: color,
            strokeWidth: 6.0,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
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

  Future<void> _onBoundaryWaypointDragEnd(
    int index,
    LatLng updatedPoint,
  ) async {
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

  Future<void> _onViaPointLongPress(int stepIndex, int controlIndex) =>
      _onViaPointLongPressSection(stepIndex, controlIndex);

  Future<void> _onInsertHandleDragEnd(
    int stepIndex,
    int pieceIndex,
    LatLng point,
  ) => _onInsertHandleDragEndSection(stepIndex, pieceIndex, point);

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
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
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
                          _mapController.move(
                            _mapController.camera.center,
                            value,
                          );
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
                  child: const Icon(
                    Icons.remove_circle,
                    size: 22,
                    color: _accent,
                  ),
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
    final isNearby = _mapMode == MapTabMode.nearby;
    final hasRouteProgress = pathPoints.isNotEmpty || steps.isNotEmpty;
    final guardPop = !isNearby && Navigator.canPop(context) && hasRouteProgress;
    return Stack(
      children: [
        PopScope(
          canPop: !guardPop,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final navigator = Navigator.of(context);
            final discard = await _confirmDiscardRouteProgress();
            if (!mounted || !discard) return;
            navigator.pop();
          },
          child: Scaffold(
            backgroundColor: _bg,
            appBar: _buildAppBar(),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  return Stack(
                    children: [
                      _buildMapLayer(),
                      if (isNearby) ...[
                        _buildNearbyFilterChips(),
                        _buildNearbyDebugCoordChip(),
                        _buildPinsToggle(),
                        if (_nearbySelectedPlace != null)
                          _buildNearbyInfoCard(_nearbySelectedPlace!),
                        _buildNearbyFabs(),
                      ] else ...[
                        _buildMapControlsOverlay(),
                        if (selectionMode != 'done') _buildInstructionPill(),
                        _buildStepChipsBar(),
                        _buildLocationSearchBar(),
                        _buildRegionSelector(),
                        _buildPinsToggle(),
                        _buildVerticalZoomSlider(),
                        _buildFormDrawer(context, constraints.maxHeight),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        if (_showNotificationOverlay)
          NotificationOverlay(
            notifications: _pendingNotifications,
            onAllDismissed: _onNotificationsDismissed,
          ),
        if (_showTutorial && !isNearby)
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

  Widget _buildStepChipsBar() {
    return this._buildStepChipsBarSection();
  }

  Widget _buildRegionSelector() {
    return this._buildRegionSelectorSection();
  }

  Widget _buildLocationSearchBar() {
    return this._buildLocationSearchBarSection();
  }

  Widget _buildPinsToggle() {
    return this._buildPinsToggleSection();
  }

  Widget _buildFormDrawer(BuildContext context, double availableHeight) {
    return this._buildFormDrawerSection(context, availableHeight);
  }

  Widget _buildDrawerHandle() {
    return this._buildDrawerHandleSection();
  }

  Widget _buildFormContent() {
    return this._buildFormContentSection();
  }
}
