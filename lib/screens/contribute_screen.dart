import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/route.dart' as route_model;
import '../services/gamification_service.dart';
import '../services/routing_service.dart';
import '../services/route_history_service.dart';
import '../services/route_metrics_service.dart';
import '../services/tutorial_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/map_controls.dart';
import '../widgets/route_preview.dart';
import '../widgets/route_form_stepper.dart';
import '../widgets/tutorial_overlay.dart';

class ContributeScreen extends StatefulWidget {
  final Future<void> Function(route_model.Route) onRouteSubmitted;
  final route_model.Route? routeToEdit;
  final String? contributorId;

  const ContributeScreen({
    super.key,
    required this.onRouteSubmitted,
    this.routeToEdit,
    this.contributorId,
  });

  @override
  State<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends State<ContributeScreen> {
  final _formKey = GlobalKey<FormState>();
  final MapController _mapController = MapController();
  final RouteHistoryService _historyService = RouteHistoryService();

  final TextEditingController _startLocationController =
      TextEditingController();
  final TextEditingController _endLocationController = TextEditingController();
  final TextEditingController _shortDescriptionController =
      TextEditingController();
  final TextEditingController _scheduleController = TextEditingController();

  List<LatLng> pathPoints = [];
  List<route_model.Step> steps = [];
  List<int> stepBoundaries = [];
  String currentMode = 'Walk';
  String selectionMode = 'start'; // 'start', 'step', 'end', 'done'
  String? selectedRegion;
  bool _showRoutePreview = false;

  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;
  bool _isFormExpanded = false;
  bool _snapToRoadEnabled = true;

  // Tutorial state
  bool _showTutorial = false;

  // ─── Color tokens (matches design system) ──────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  // Philippine regions with approximate boundaries
  final Map<String, LatLngBounds> philippineRegions = {
    'Philippines': LatLngBounds(
      const LatLng(4.5, 116.0),
      const LatLng(21.5, 127.0),
    ),
    'Region I – Ilocos Region': LatLngBounds(
      const LatLng(15.5, 119.5),
      const LatLng(18.5, 121.0),
    ),
    'Region II – Cagayan Valley': LatLngBounds(
      const LatLng(16.0, 121.0),
      const LatLng(19.0, 122.5),
    ),
    'Region III – Central Luzon': LatLngBounds(
      const LatLng(14.5, 120.0),
      const LatLng(16.0, 121.5),
    ),
    'Region IV-A – CALABARZON': LatLngBounds(
      const LatLng(13.5, 120.5),
      const LatLng(15.0, 122.0),
    ),
    'MIMAROPA Region (Region IV-B)': LatLngBounds(
      const LatLng(8.5, 117.0),
      const LatLng(14.0, 122.0),
    ),
    'Region V – Bicol Region': LatLngBounds(
      const LatLng(12.5, 122.5),
      const LatLng(14.5, 124.5),
    ),
    'Region VI – Western Visayas': LatLngBounds(
      const LatLng(9.5, 121.5),
      const LatLng(12.0, 123.5),
    ),
    'Region VII – Central Visayas': LatLngBounds(
      const LatLng(9.0, 123.0),
      const LatLng(11.5, 124.5),
    ),
    'Region VIII – Eastern Visayas': LatLngBounds(
      const LatLng(10.0, 124.0),
      const LatLng(13.0, 126.0),
    ),
    'Region IX – Zamboanga Peninsula': LatLngBounds(
      const LatLng(6.5, 121.5),
      const LatLng(9.0, 123.5),
    ),
    'Region X – Northern Mindanao': LatLngBounds(
      const LatLng(7.5, 123.5),
      const LatLng(9.5, 126.0),
    ),
    'Region XI – Davao Region': LatLngBounds(
      const LatLng(5.5, 125.0),
      const LatLng(8.0, 127.0),
    ),
    'Region XII – SOCCSKSARGEN': LatLngBounds(
      const LatLng(5.0, 124.0),
      const LatLng(8.0, 125.5),
    ),
    'Region XIII – Caraga': LatLngBounds(
      const LatLng(8.0, 125.5),
      const LatLng(10.5, 127.0),
    ),
    'NCR – National Capital Region': LatLngBounds(
      const LatLng(14.4, 120.9),
      const LatLng(14.8, 121.2),
    ),
    'CAR – Cordillera Administrative Region': LatLngBounds(
      const LatLng(16.0, 120.0),
      const LatLng(18.5, 121.5),
    ),
    'BARMM – Bangsamoro Autonomous Region in Muslim Mindanao': LatLngBounds(
      const LatLng(5.0, 119.0),
      const LatLng(7.5, 122.0),
    ),
  };

  static const List<String> modes = [
    'Walk',
    'Jeepney',
    'Bus',
    'Train',
    'Tricycle',
    'FX/Van',
    'Ferry',
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

  @override
  void initState() {
    super.initState();
    _checkTutorialStatus();
    _loadRouteToEdit();
  }

  void _loadRouteToEdit() {
    if (widget.routeToEdit != null) {
      final route = widget.routeToEdit!;
      setState(() {
        pathPoints = List<LatLng>.from(route.pathPoints);
        steps = List<route_model.Step>.from(route.steps);
        stepBoundaries = List<int>.from(route.stepBoundaries);
        _startLocationController.text = route.startLocation;
        _endLocationController.text = route.endLocation;
        _shortDescriptionController.text = route.shortDescription;
        _scheduleController.text = route.schedule ?? '';
        selectionMode = 'done';
      });
      _saveToHistory();
    }
  }

  Future<void> _checkTutorialStatus() async {
    final hasSeenTutorial = await TutorialService.hasSeenContributeTutorial();
    if (!hasSeenTutorial && mounted) {
      // Expand the form so tutorial can highlight form elements
      setState(() {
        _isFormExpanded = true;
        _showTutorial = true;
      });
    }
  }

  void _onTutorialComplete() async {
    await TutorialService.markContributeTutorialAsSeen();
    if (mounted) {
      setState(() {
        _showTutorial = false;
      });
    }
  }

  void _loadExampleRoute() {
    final exampleRoute = TutorialService.getExampleRoute();
    setState(() {
      pathPoints = List<LatLng>.from(exampleRoute.pathPoints);
      steps = List<route_model.Step>.from(exampleRoute.steps);
      stepBoundaries = List<int>.from(exampleRoute.stepBoundaries);
      _startLocationController.text = exampleRoute.startLocation;
      _endLocationController.text = exampleRoute.endLocation;
      _shortDescriptionController.text = exampleRoute.shortDescription;
      _scheduleController.text = exampleRoute.schedule ?? '';
      selectionMode = 'done';
    });
    _saveToHistory();
  }

  @override
  void dispose() {
    _startLocationController.dispose();
    _endLocationController.dispose();
    _shortDescriptionController.dispose();
    _scheduleController.dispose();
    super.dispose();
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) async {
    if (selectionMode == 'start') {
      setState(() {
        pathPoints.add(point);
        selectionMode = 'step';
        _showModeDialog();
      });
    } else if (selectionMode == 'step') {
      if (pathPoints.isNotEmpty) {
        final lastPoint = pathPoints.last;

        if (_snapToRoadEnabled) {
          // Try to get route from OpenRouteService with snap-to-road
          try {
            final result = await RoutingService.getRoute(
              originName: lastPoint.toString(),
              origin: lastPoint,
              destinationName: point.toString(),
              destination: point,
              mode: currentMode,
            );
            if (result != null && result.polyline.isNotEmpty) {
              setState(() {
                pathPoints.addAll(result.polyline);
              });
              _showStepDialog();
              return;
            }
          } catch (e) {
            // If snap-to-road fails, we'll fall back to straight line
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Snap-to-road failed, using straight line instead',
                ),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }

        // Either snap-to-road is disabled or it failed, use straight line
        setState(() {
          pathPoints.add(point);
        });
        _showStepDialog();
      }
    }
  }

  void _onRegionChanged(String? region) {
    if (region != null && philippineRegions.containsKey(region)) {
      final bounds = philippineRegions[region]!;

      // reset to initial view
      if (region == 'Philippines') {
        _mapController.move(const LatLng(12.8797, 121.7740), 6.0);
      } else if (region == 'MIMAROPA Region (Region IV-B)') {
        //use move instead of fitCamera
        final center = LatLng(
          (bounds.southWest.latitude + bounds.northEast.latitude) / 2,
          (bounds.southWest.longitude + bounds.northEast.longitude) / 2,
        );
        _mapController.move(center, 7.0);
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(20)),
        );
      }
      setState(() {
        selectedRegion = region;
      });
    }
  }

  void _showModeDialog() {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.08),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      border: Border(
                        bottom: BorderSide(color: _border, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _accentSoft,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.alt_route,
                            color: _accent,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Select Transport Mode',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children:
                            modes.map((mode) {
                              final color = modeColors[mode] ?? _accent;
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    currentMode = mode;
                                  });
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Tap on the map to select the next point for $mode',
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        currentMode == mode
                                            ? color.withValues(alpha: 0.08)
                                            : _surface,
                                    borderRadius: BorderRadius.circular(11),
                                    border: Border.all(
                                      color:
                                          currentMode == mode
                                              ? color.withValues(alpha: 0.4)
                                              : _border,
                                      width: currentMode == mode ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(9),
                                        ),
                                        child: Icon(
                                          _getModeIcon(mode),
                                          color: color,
                                          size: 17,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        mode,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight:
                                              currentMode == mode
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                          color:
                                              currentMode == mode
                                                  ? _textPrimary
                                                  : _textSecondary,
                                        ),
                                      ),
                                      if (currentMode == mode) ...[
                                        const Spacer(),
                                        Icon(
                                          Icons.check_circle_rounded,
                                          color: color,
                                          size: 16,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _showStepDialog() {
    String instruction = '';
    String details = '';

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.08),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      border: Border(
                        bottom: BorderSide(color: _border, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: (modeColors[currentMode] ?? _accent)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            _getModeIcon(currentMode),
                            color: modeColors[currentMode] ?? _accent,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Step: $currentMode',
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _styledTextField(
                          hint: 'e.g., Ride a jeep with Cubao terminal',
                          label: 'Instruction',
                          icon: Icons.info_outline,
                          maxLines: 2,
                          onChanged: (v) => instruction = v,
                        ),
                        const SizedBox(height: 10),
                        _styledTextField(
                          hint: 'e.g., Drop off at Gateway Mall',
                          label: 'Details',
                          icon: Icons.location_on_outlined,
                          maxLines: 2,
                          onChanged: (v) => details = v,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ghostButton(
                            label: 'Cancel',
                            onTap: () {
                              Navigator.pop(context);
                              pathPoints.removeLast(); // Remove the point if cancel
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: _gradientButton(
                            label: 'Save Step',
                            icon: Icons.check_rounded,
                            onTap: () {
                              setState(() {
                                steps.add(
                                  route_model.Step(
                                    mode: currentMode,
                                    instruction: instruction,
                                    details: details,
                                  ),
                                );
                                stepBoundaries.add(pathPoints.length - 1);
                              });
                              Navigator.pop(context);
                              _showAddAnotherStepDialog();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _showAddAnotherStepDialog() {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.08),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      border: Border(
                        bottom: BorderSide(color: _border, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3EC97A).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.check_circle_outline,
                            color: Color(0xFF3EC97A),
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Step Added',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _accentSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                '${steps.length}',
                                style: const TextStyle(
                                  color: _accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'step${steps.length > 1 ? 's' : ''} added to this route',
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      children: [
                        _gradientButton(
                          label: 'Add Another Step',
                          icon: Icons.add_rounded,
                          onTap: () {
                            Navigator.pop(context);
                            _showModeDialog();
                          },
                        ),
                        const SizedBox(height: 8),
                        _ghostButton(
                          label: 'Finish Route',
                          onTap: () {
                            Navigator.pop(context);
                            setState(() {
                              selectionMode = 'done';
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _submit() async {
    if (pathPoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Need at least start and end points on map'),
        ),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      final modes = steps.map((step) => step.mode).toList();
      final fare = RouteMetricsService.calculateFareEstimate(
        pathPoints,
        modes,
        stepBoundaries,
      );
      final etaMinutes = RouteMetricsService.calculateEta(
        pathPoints,
        modes,
        stepBoundaries,
      );

      final route = route_model.Route(
        id: widget.routeToEdit?.id ?? DateTime.now().toString(),
        startLocation:
            _startLocationController.text.isEmpty
                ? 'Start Point (${pathPoints.first.latitude.toStringAsFixed(4)}, ${pathPoints.first.longitude.toStringAsFixed(4)})'
                : _startLocationController.text,
        endLocation:
            _endLocationController.text.isEmpty
                ? 'End Point (${pathPoints.last.latitude.toStringAsFixed(4)}, ${pathPoints.last.longitude.toStringAsFixed(4)})'
                : _endLocationController.text,
        shortDescription:
            _shortDescriptionController.text.isEmpty
                ? 'Custom route with ${steps.length} steps'
                : _shortDescriptionController.text,
        steps: steps,
        startLat: pathPoints.first.latitude,
        startLng: pathPoints.first.longitude,
        endLat: pathPoints.last.latitude,
        endLng: pathPoints.last.longitude,
        pathPoints: pathPoints,
        stepBoundaries: stepBoundaries,
        eta: etaMinutes.toString(),
        price: fare,
        schedule:
            _scheduleController.text.isEmpty ? null : _scheduleController.text,
        contributorId: widget.routeToEdit?.contributorId ?? widget.contributorId,
      );

      widget.onRouteSubmitted(route);

      // Award points only for new contributions, not edits
      if (widget.routeToEdit == null) {
        final user = await GamificationService.loadUser();
        final unlockedItems =
            await GamificationService.incrementRoutesContributed(user);

        // Show achievement notifications
        if (unlockedItems.isNotEmpty && mounted) {
          setState(() {
            _pendingNotifications = unlockedItems;
            _showNotificationOverlay = true;
          });
        }
      }

      if (!mounted) return;
      final message =
          widget.routeToEdit != null
              ? 'Route updated successfully!'
              : 'Route submitted for review!';

      await showDialog(
        context: context,
        builder:
            (context) => Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.08),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 28),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3EC97A).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFF3EC97A).withOpacity(0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.check_circle_outline_rounded,
                        color: Color(0xFF3EC97A),
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Route Submitted',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: _textSecondary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: _gradientButton(
                        label: 'OK',
                        icon: Icons.check_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      );

      // Reset form only for new routes
      if (widget.routeToEdit == null) {
        setState(() {
          pathPoints = [];
          steps = [];
          stepBoundaries = [];
          selectionMode = 'start';
          _startLocationController.clear();
          _endLocationController.clear();
          _shortDescriptionController.clear();
          _scheduleController.clear();
        });
      }
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

  List<Polyline> get polylines {
    List<Polyline> polylines = [];
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final color = modeColors[step.mode] ?? Colors.blue;
      final startIdx = (i == 0) ? 0 : stepBoundaries[i - 1];
      final endIdx =
          (i < stepBoundaries.length)
              ? stepBoundaries[i]
              : pathPoints.length - 1;
      if (endIdx > startIdx) {
        final stepPoints = pathPoints.sublist(startIdx, endIdx + 1);
        // Add border (background) polyline for better visibility
        polylines.add(
          Polyline(
            points: stepPoints,
            color: Colors.black.withOpacity(0.5),
            strokeWidth: 8.0,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
        // Add main polyline on top
        polylines.add(
          Polyline(
            points: stepPoints,
            color: color,
            strokeWidth: 6.0,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
      }
    }
    return polylines;
  }

  void _onNotificationsDismissed() {
    setState(() {
      _showNotificationOverlay = false;
      _pendingNotifications.clear();
    });
  }

  void _onUndo() {
    final previousState = _historyService.undo();
    if (previousState != null) {
      setState(() {
        pathPoints = previousState.pathPoints;
        steps = previousState.steps;
        stepBoundaries = previousState.stepBoundaries;
      });
    }
  }

  void _onRedo() {
    final nextState = _historyService.redo();
    if (nextState != null) {
      setState(() {
        pathPoints = nextState.pathPoints;
        steps = nextState.steps;
        stepBoundaries = nextState.stepBoundaries;
      });
    }
  }

  void _onReset() {
    setState(() {
      pathPoints = [];
      steps = [];
      stepBoundaries = [];
      selectionMode = 'start';
      _startLocationController.clear();
      _endLocationController.clear();
      _shortDescriptionController.clear();
      _scheduleController.clear();
    });
    _historyService.clear();
  }

  void _onPreviewRoute() {
    if (pathPoints.length < 2 || steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Need at least start, end points and one step'),
        ),
      );
      return;
    }

    final modes = steps.map((step) => step.mode).toList();
    final fare = RouteMetricsService.calculateFareEstimate(
      pathPoints,
      modes,
      stepBoundaries,
    );
    final etaMinutes = RouteMetricsService.calculateEta(
      pathPoints,
      modes,
      stepBoundaries,
    );

    final route = route_model.Route(
      id: DateTime.now().toString(),
      startLocation:
          _startLocationController.text.isEmpty
              ? 'Start Point (${pathPoints.first.latitude.toStringAsFixed(4)}, ${pathPoints.first.longitude.toStringAsFixed(4)})'
              : _startLocationController.text,
      endLocation:
          _endLocationController.text.isEmpty
              ? 'End Point (${pathPoints.last.latitude.toStringAsFixed(4)}, ${pathPoints.last.longitude.toStringAsFixed(4)})'
              : _endLocationController.text,
      shortDescription:
          _shortDescriptionController.text.isEmpty
              ? 'Custom route with ${steps.length} steps'
              : _shortDescriptionController.text,
      steps: steps,
      startLat: pathPoints.first.latitude,
      startLng: pathPoints.first.longitude,
      endLat: pathPoints.last.latitude,
      endLng: pathPoints.last.longitude,
      pathPoints: pathPoints,
      stepBoundaries: stepBoundaries,
      eta: etaMinutes.toString(),
      price: fare,
      schedule:
          _scheduleController.text.isEmpty ? null : _scheduleController.text,
    );

    setState(() {
      _showRoutePreview = true;
    });

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => RoutePreview(
              route: route,
              onEdit: () {
                Navigator.pop(context);
                setState(() {
                  _showRoutePreview = false;
                });
              },
              onSubmit: () {
                Navigator.pop(context);
                _submit();
              },
            ),
      ),
    );
  }

  void _onStepsChanged(List<route_model.Step> updatedSteps) {
    setState(() {
      steps = updatedSteps;
    });
    _saveToHistory();
  }

  void _onStepReordered(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final step = steps.removeAt(oldIndex);
      steps.insert(newIndex, step);

      // Update step boundaries
      if (stepBoundaries.isNotEmpty) {
        final boundary = stepBoundaries.removeAt(oldIndex);
        stepBoundaries.insert(newIndex, boundary);
      }
    });
    _saveToHistory();
  }

  void _onStepDeleted(int index) {
    setState(() {
      steps.removeAt(index);
      if (index < stepBoundaries.length) {
        stepBoundaries.removeAt(index);
      }
    });
    _saveToHistory();
  }

  void _onSnapToRoadToggled(bool enabled) {
    setState(() {
      _snapToRoadEnabled = enabled;
    });

    // Show a snackbar to inform the user
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

  void _saveToHistory() {
    _historyService.addState(
      List<LatLng>.from(pathPoints),
      List<route_model.Step>.from(steps),
      List<int>.from(stepBoundaries),
    );
  }

  // ─── Shared UI helpers (matching design system) ────────────────────────────

  Widget _styledTextField({
    required String hint,
    required String label,
    required IconData icon,
    int maxLines = 1,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: TextField(
        onChanged: onChanged,
        maxLines: maxLines,
        style: const TextStyle(color: _textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _textSecondary, fontSize: 13),
          hintText: hint,
          hintStyle: const TextStyle(color: _textSecondary, fontSize: 13),
          prefixIcon: Icon(icon, color: _accent, size: 18),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 13,
            horizontal: 4,
          ),
        ),
      ),
    );
  }

  Widget _gradientButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ghostButton({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 46,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: _textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: _bg,
          // ─── AppBar ────────────────────────────────────────────────────
          appBar: AppBar(
            backgroundColor: _surface,
            foregroundColor: _textPrimary,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            title: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.add_road_rounded,
                    color: _accent,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.routeToEdit != null
                      ? 'Edit Route'
                      : 'Contribute a Route',
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            actions: [
              GestureDetector(
                onTap: () => setState(() => _showTutorial = true),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child: const Icon(
                    Icons.help_outline_rounded,
                    color: _textSecondary,
                    size: 18,
                  ),
                ),
              ),
              if (selectionMode == 'done')
                GestureDetector(
                  onTap: _onPreviewRoute,
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _accentSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _accent.withOpacity(0.3)),
                    ),
                    child: const Icon(
                      Icons.preview_rounded,
                      color: _accent,
                      size: 18,
                    ),
                  ),
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: _border),
            ),
          ),
          body: SafeArea(
            child: Stack(
              children: [
                // Full-screen Map
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(12.8797, 121.7740),
                    initialZoom: 6.0,
                    minZoom: 5.0,
                    maxZoom: 18.0,
                    cameraConstraint: CameraConstraint.contain(
                      bounds: LatLngBounds(
                        const LatLng(4.5, 116.0),
                        const LatLng(21.5, 127.0),
                      ),
                    ),
                    onTap: _onMapTap,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.app.transitph_beta',
                    ),
                    PolylineLayer(polylines: polylines),
                    MarkerLayer(
                      markers: [
                        if (pathPoints.isNotEmpty)
                          Marker(
                            point: pathPoints.first,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.green,
                              size: 40,
                            ),
                          ),
                        if (pathPoints.length > 1)
                          Marker(
                            point: pathPoints.last,
                            child: const Icon(
                              Icons.flag,
                              color: Colors.red,
                              size: 40,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // Map Controls
                Positioned(
                  top: 70,
                  left: 20,
                  child: MapControls(
                    historyService: _historyService,
                    pathPoints: pathPoints,
                    steps: steps,
                    stepBoundaries: stepBoundaries,
                    selectionMode: selectionMode,
                    currentMode: currentMode,
                    onUndo: _onUndo,
                    onRedo: _onRedo,
                    onReset: _onReset,
                    onPreview: _onPreviewRoute,
                    onSnapToRoadToggled: _onSnapToRoadToggled,
                    snapToRoadEnabled: _snapToRoadEnabled,
                  ),
                ),

                // ─── Instruction pill (above bottom sheet, no overlap) ──
                if (selectionMode != 'done')
                  Positioned(
                    bottom: 50,
                    left: 16,
                    right: 16,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: _surface.withOpacity(0.96),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: _border),
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                color: _accentSoft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.touch_app_rounded,
                                size: 13,
                                color: _accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _getInstructionText(),
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ─── Region Selector Overlay ──────────────────────────
                Positioned(
                  top: 10,
                  right: 16,
                  child: Container(
                    width: 155,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _surface.withOpacity(0.97),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedRegion,
                      hint: const Text(
                        'Select Region',
                        style: TextStyle(fontSize: 11, color: _textSecondary),
                      ),
                      isExpanded: true,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _accent,
                        size: 18,
                      ),
                      dropdownColor: _surface,
                      style: const TextStyle(color: _textPrimary, fontSize: 11),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      items:
                          philippineRegions.keys.map((region) {
                            return DropdownMenuItem<String>(
                              value: region,
                              child: Text(
                                region,
                                style: const TextStyle(fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                      onChanged: _onRegionChanged,
                    ),
                  ),
                ),

                // ─── Form Stepper Container ───────────────────────────
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height:
                        _isFormExpanded
                            ? MediaQuery.of(context).size.height * 0.6
                            : 40,
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      border: Border(
                        top: BorderSide(color: _border, width: 1.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      child: Column(
                        children: [
                          // ─── Handle / Toggle ──────────────────────────
                          InkWell(
                            onTap: () {
                              setState(() {
                                _isFormExpanded = !_isFormExpanded;
                              });
                            },
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                            child: SizedBox(
                              height: 40,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 36,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: _border,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _isFormExpanded
                                        ? 'Hide Form'
                                        : 'Route Details',
                                    style: const TextStyle(
                                      color: _textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    _isFormExpanded
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.keyboard_arrow_up_rounded,
                                    size: 18,
                                    color: _accent,
                                  ),
                                  if (!_isFormExpanded && steps.isNotEmpty) ...[
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _accentSoft,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: _accent.withOpacity(0.2),
                                        ),
                                      ),
                                      child: Text(
                                        '${steps.length} step${steps.length > 1 ? 's' : ''}',
                                        style: const TextStyle(
                                          color: _accent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          // ─── Form content ─────────────────────────────
                          if (_isFormExpanded)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Form(
                                  key: _formKey,
                                  child: RouteFormStepper(
                                    startLocationController:
                                        _startLocationController,
                                    endLocationController:
                                        _endLocationController,
                                    shortDescriptionController:
                                        _shortDescriptionController,
                                    scheduleController: _scheduleController,
                                    steps: steps,
                                    onSubmit: _submit,
                                    onReset: _onReset,
                                    selectionMode: selectionMode,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
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

  String _getInstructionText() {
    switch (selectionMode) {
      case 'start':
        return 'Tap on the map to select the starting point';
      case 'step':
        return 'Tap to select next point for $currentMode';
      case 'done':
        return 'Route complete! Fill in the details below and submit.';
      default:
        return '';
    }
  }
}