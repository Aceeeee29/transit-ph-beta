import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import '../services/location_service.dart';
import '../widgets/contribute/contribute_dialogs.dart';
import '../widgets/contribute/location_search_bar.dart';

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
  String currentMode = 'Jeepney';
  String selectionMode = 'start';
  String? selectedRegion;
  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;
  bool _isFormExpanded = false;
  bool _snapToRoadEnabled = true;
  bool _showTutorial = false;
  LatLng? _searchedLocation;

  // ─── Color tokens 
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  // ─── Philippine regions 
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
    _loadRouteToEdit();
  }

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
      if (region == 'Philippines') {
        _mapController.move(const LatLng(12.8797, 121.7740), 6.0);
      } else if (region == 'MIMAROPA Region (Region IV-B)') {
        final center = LatLng(
          (bounds.southWest.latitude + bounds.northEast.latitude) / 2,
          (bounds.southWest.longitude + bounds.northEast.longitude) / 2,
        );
        _mapController.move(center, 7.0);
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(
              bounds: bounds, padding: const EdgeInsets.all(20)),
        );
      }
      setState(() => selectedRegion = region);
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
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Location found and map locked to that place'),
        duration: Duration(seconds: 2),
      ),
    );

    return true;
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
        onCancel: () => pathPoints.removeLast(),
        onSaved: (step) {
          setState(() {
            steps.add(step);
            stepBoundaries.add(pathPoints.length - 1);
            _stepOrsDistM.add(_pendingOrsDistM);
            _stepOrsDurS.add(_pendingOrsDurS);
            _pendingOrsDistM = null;
            _pendingOrsDurS = null;
          });
          _showAddAnotherStepDialog();
        },
      ),
    );
  }

  void _showAddAnotherStepDialog() {
    showDialog(
      context: context,
      builder: (_) => AddStepDialog(
        stepCount: steps.length,
        onAddAnother: () => _showModeDialog(),
        onFinished: () async {
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

  // ─── History controls ────────────────────────────────────────────────────────

  void _onUndo() {
    final prev = _historyService.undo();
    if (prev != null) {
      setState(() {
        pathPoints = prev.pathPoints;
        steps = prev.steps;
        stepBoundaries = prev.stepBoundaries;
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
      });
    }
  }

  void _onReset() {
    setState(() {
      pathPoints = [];
      steps = [];
      stepBoundaries = [];
      _stepOrsDistM.clear();
      _stepOrsDurS.clear();
      _pendingOrsDistM = null;
      _pendingOrsDurS = null;
      selectionMode = 'start';
      _startLocationController.clear();
      _endLocationController.clear();
      _shortDescriptionController.clear();
      _selectedRouteTags = [];
      _searchedLocation = null;
    });
    _historyService.clear();
  }

  void _saveToHistory() {
    _historyService.addState(
      List<LatLng>.from(pathPoints),
      List<route_model.Step>.from(steps),
      List<int>.from(stepBoundaries),
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

  route_model.Route _buildRoute({String? existingId}) {
    double totalDurS = 0;
    double totalDistKm = 0;
    double totalFare = 0;
    final Distance distCalc = const Distance();

    for (int i = 0; i < steps.length; i++) {
      final orsDistM =
          i < _stepOrsDistM.length ? _stepOrsDistM[i] : null;
      final orsDurS =
          i < _stepOrsDurS.length ? _stepOrsDurS[i] : null;

      if (orsDistM != null && orsDurS != null) {
        totalDistKm += orsDistM / 1000;
        totalDurS += orsDurS;
        totalFare += steps[i].actualFare ??
          RouteMetricsService.calculateFareForMode(
            steps[i].mode, orsDistM / 1000);
      } else {
        final startIdx = (i == 0)
            ? 0
            : (i - 1 < stepBoundaries.length
                ? stepBoundaries[i - 1]
                : 0);
        final endIdx = (i < stepBoundaries.length)
            ? stepBoundaries[i]
            : pathPoints.length - 1;
        double segDistKm = 0;
        for (int j = startIdx;
            j < endIdx && j + 1 < pathPoints.length;
            j++) {
          segDistKm += distCalc.as(
              LengthUnit.Kilometer, pathPoints[j], pathPoints[j + 1]);
        }
        totalDistKm += segDistKm;
        final speedKmh = _speedForMode(steps[i].mode);
        totalDurS += (segDistKm / speedKmh) * 3600;
        totalFare += steps[i].actualFare ??
          RouteMetricsService.calculateFareForMode(
            steps[i].mode, segDistKm);
      }
    }
    if (steps.length > 1) totalDurS += (steps.length - 1) * 120;

    final distStr =
        RouteMetricsService.formatDistance(totalDistKm);
    final etaStr = (totalDurS / 60).ceil().toString();
    final fareStr = 'PHP ${totalFare.round()}';
    final schedule = _deriveRouteSchedule(steps);

    final startLoc = _startLocationController.text.isEmpty
        ? 'Start Point (${pathPoints.first.latitude.toStringAsFixed(4)}, ${pathPoints.first.longitude.toStringAsFixed(4)})'
        : _startLocationController.text;
    final endLoc = _endLocationController.text.isEmpty
        ? 'End Point (${pathPoints.last.latitude.toStringAsFixed(4)}, ${pathPoints.last.longitude.toStringAsFixed(4)})'
        : _endLocationController.text;
    final desc = _shortDescriptionController.text.isEmpty
        ? 'Custom route with ${steps.length} steps'
        : _shortDescriptionController.text;

    return route_model.Route(
      id: existingId ?? DateTime.now().toString(),
      startLocation: startLoc,
      endLocation: endLoc,
      shortDescription: desc,
      steps: steps,
      startLat: pathPoints.first.latitude,
      startLng: pathPoints.first.longitude,
      endLat: pathPoints.last.latitude,
      endLng: pathPoints.last.longitude,
      pathPoints: pathPoints,
      stepBoundaries: stepBoundaries,
      eta: etaStr,
      price: fareStr,
      distance: distStr,
      schedule: schedule,
      audienceTags: _selectedRouteTags,
      distanceMeters: totalDistKm > 0 ? totalDistKm * 1000 : null,
      contributorId: widget.routeToEdit?.contributorId ??
          widget.contributorId ??
          FirebaseAuth.instance.currentUser?.uid,
      // Always starts as pending — moderator must approve before it goes live
      approvalStatus: route_model.RouteApprovalStatus.pending,
    );
  }

  bool _validateStepReliability() {
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final stepNo = i + 1;
      final isMotorized = step.mode != 'Walk';

      if (step.instruction.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Step $stepNo is missing an instruction.')),
        );
        return false;
      }

      if (!isMotorized) continue;

      if (step.details.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Step $stepNo needs details for ${step.mode}.')),
        );
        return false;
      }

      final hasSchedule = step.is24_7 ||
          ((step.startTime?.trim().isNotEmpty ?? false) &&
              (step.endTime?.trim().isNotEmpty ?? false));
      if (!hasSchedule) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Step $stepNo needs operating hours for ${step.mode}.')),
        );
        return false;
      }

      if (step.actualFare == null || step.actualFare! < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Step $stepNo needs a valid actual fare for ${step.mode}.')),
        );
        return false;
      }
    }
    return true;
  }

  // ─── Submit ──────────────────────────────────────────────────────────────────

  void _submit() async {
    if (pathPoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Need at least start and end points on map')),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      if (!_validateStepReliability()) {
        return;
      }
      final route = _buildRoute(existingId: widget.routeToEdit?.id);
      try {
        await widget.onRouteSubmitted(route);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit route: $e')),
        );
        return;
      }

      if (widget.routeToEdit == null) {
        final user = await GamificationService.loadUser();
        final unlockedItems =
            await GamificationService.incrementRoutesContributed(user);
        if (unlockedItems.isNotEmpty && mounted) {
          setState(() {
            _pendingNotifications = unlockedItems;
            _showNotificationOverlay = true;
          });
        }
      }

      if (!mounted) return;

      // ── Show the correct dialog depending on new vs edit ──────────────────
      await showDialog(
        context: context,
        builder: (_) => widget.routeToEdit != null
            ? const _SubmitSuccessDialog(isEdit: true)
            : const _SubmitSuccessDialog(isEdit: false),
      );

      if (widget.routeToEdit == null) {
        setState(() {
          pathPoints = [];
          steps = [];
          stepBoundaries = [];
          selectionMode = 'start';
          _startLocationController.clear();
          _endLocationController.clear();
          _shortDescriptionController.clear();
          _selectedRouteTags = [];
        });
      }
    }
  }

  // ─── Preview route ───────────────────────────────────────────────────────────

  void _onPreviewRoute() {
    if (pathPoints.length < 2 || steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Need at least start, end points and one step'),
        ),
      );
      return;
    }

    final route = _buildRoute();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoutePreview(
          route: route,
          onEdit: () {
            Navigator.pop(context);
          },
          onSubmit: () {
            Navigator.pop(context);
            _submit();
          },
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
    return AppBar(
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
            child: const Icon(Icons.add_road_rounded,
                color: _accent, size: 16),
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
                border:
                    Border.all(color: _accent.withOpacity(0.3)),
              ),
              child: const Icon(Icons.preview_rounded,
                  color: _accent, size: 18),
            ),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
    );
  }

  Widget _buildMapLayer() {
    return FlutterMap(
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
          userAgentPackageName:
              'com.example.app.transitph_beta',
        ),
        PolylineLayer(polylines: polylines),
        MarkerLayer(
          markers: [
            if (pathPoints.isNotEmpty)
              Marker(
                point: pathPoints.first,
                child: const Icon(Icons.location_on,
                    color: Colors.green, size: 40),
              ),
            if (pathPoints.length > 1)
              Marker(
                point: pathPoints.last,
                child: const Icon(Icons.flag,
                    color: Colors.red, size: 40),
              ),
            if (_searchedLocation != null)
              Marker(
                point: _searchedLocation!,
                child: const Icon(Icons.my_location_rounded,
                    color: _accent, size: 34),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMapControlsOverlay() {
    double? totalOrsDistKm;
    int? totalOrsDurMinutes;

    if (_stepOrsDistM.isNotEmpty &&
        _stepOrsDistM.every((d) => d != null)) {
      totalOrsDistKm =
          _stepOrsDistM.fold(0.0, (sum, d) => sum + (d ?? 0)) /
              1000;
    }
    if (_stepOrsDurS.isNotEmpty &&
        _stepOrsDurS.every((d) => d != null)) {
      double totalSeconds =
          _stepOrsDurS.fold(0.0, (sum, d) => sum + (d ?? 0));
      if (steps.length > 1)
        totalSeconds += ((steps.length - 1) * 120);
      totalOrsDurMinutes = (totalSeconds / 60).ceil();
    }

    return Positioned(
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
        orsDistanceKm: totalOrsDistKm,
        orsDurationMinutes: totalOrsDurMinutes,
      ),
    );
  }

  Widget _buildInstructionPill() {
    String text;
    switch (selectionMode) {
      case 'start':
        text = 'Tap on the map to select the starting point';
        break;
      case 'step':
        text = 'Tap to select next point for $currentMode';
        break;
      default:
        text = '';
    }

    return Positioned(
      bottom: 50,
      left: 16,
      right: 16,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 9),
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
                  text,
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
    );
  }

  Widget _buildRegionSelector() {
    return Positioned(
      top: 10,
      right: 16,
      child: Container(
        width: 155,
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
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
            style:
                TextStyle(fontSize: 11, color: _textSecondary),
          ),
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: _accent,
            size: 18,
          ),
          dropdownColor: _surface,
          style:
              const TextStyle(color: _textPrimary, fontSize: 11),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
          items: philippineRegions.keys.map((region) {
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
    );
  }

  Widget _buildLocationSearchBar() {
    return Positioned(
      top: 10,
      left: 16,
      right: 180,
      child: ContributeLocationSearchBar(
        onSearch: _onLocationSearched,
        surface: _surface,
        border: _border,
        accent: _accent,
        textPrimary: _textPrimary,
        textSecondary: _textSecondary,
      ),
    );
  }

  Widget _buildFormDrawer(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: _isFormExpanded
            ? MediaQuery.of(context).size.height * 0.6
            : 40,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          border:
              Border(top: BorderSide(color: _border, width: 1.5)),
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
              top: Radius.circular(20)),
          child: Column(
            children: [
              _buildDrawerHandle(),
              if (_isFormExpanded) _buildFormContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerHandle() {
    return InkWell(
      onTap: () =>
          setState(() => _isFormExpanded = !_isFormExpanded),
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(20)),
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
              _isFormExpanded ? 'Hide Form' : 'Route Details',
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
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: _accent.withOpacity(0.2)),
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
    );
  }

  Widget _buildFormContent() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 8),
        child: Form(
          key: _formKey,
          child: RouteFormStepper(
            startLocationController: _startLocationController,
            endLocationController: _endLocationController,
            shortDescriptionController: _shortDescriptionController,
            selectedRouteTags: _selectedRouteTags,
            userTagOptions: onboardingUserTags,
            otherTagOptions: otherRouteTags,
            onRouteTagsChanged: (tags) {
              setState(() => _selectedRouteTags = tags);
            },
            onSubmit: _submit,
            onReset: _onReset,
            selectionMode: selectionMode,
          ),
        ),
      ),
    );
  }
}

// ─── Submit success dialog ────────────────────────────────────────────────────

class _SubmitSuccessDialog extends StatelessWidget {
  final bool isEdit;

  static const _bg = Color(0xFFF4F8FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _warning = Color(0xFFFFB547);
  static const _green = Color(0xFF3EC97A);

  const _SubmitSuccessDialog({required this.isEdit});

  @override
  Widget build(BuildContext context) {
    return Dialog(
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

            // ── Icon — green check for edit, warning clock for new ──────────
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isEdit
                    ? _green.withOpacity(0.12)
                    : _warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isEdit
                      ? _green.withOpacity(0.3)
                      : _warning.withOpacity(0.3),
                ),
              ),
              child: Icon(
                isEdit
                    ? Icons.check_circle_outline_rounded
                    : Icons.pending_actions_rounded,
                color: isEdit ? _green : _warning,
                size: 34,
              ),
            ),

            const SizedBox(height: 16),

            Text(
              isEdit ? 'Route Updated' : 'Pending Review',
              style: const TextStyle(
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
                isEdit
                    ? 'Your route has been updated successfully.'
                    : 'Your route has been submitted and is awaiting moderator approval. It will appear publicly once approved.',
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // ── Pending status steps (only for new submissions) ─────────────
            if (!isEdit) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _warning.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: _warning.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      _step(
                        icon: Icons.check_circle_rounded,
                        color: _green,
                        label: 'Route submitted',
                        done: true,
                      ),
                      const SizedBox(height: 10),
                      _step(
                        icon: Icons.shield_outlined,
                        color: _warning,
                        label: 'Awaiting moderator review',
                        done: false,
                      ),
                      const SizedBox(height: 10),
                      _step(
                        icon: Icons.public_rounded,
                        color: _textSecondary,
                        label: 'Goes live after approval',
                        done: false,
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
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
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_rounded,
                          color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Got it',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
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
    );
  }

  Widget _step({
    required IconData icon,
    required Color color,
    required String label,
    required bool done,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: done ? _textPrimary : _textSecondary,
              fontWeight:
                  done ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}