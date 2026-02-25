import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import '../models/route.dart' as route_model;
import '../services/gamification_service.dart';
import '../services/route_metrics_service.dart';
import '../widgets/notification_overlay.dart';

class RouteMapScreen extends StatefulWidget {
  final route_model.Route route;

  const RouteMapScreen({super.key, required this.route});

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  List<route_model.Report> _routeReports = [];
  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;
  bool? _userVote;
  List<LatLng> _pathPoints = [];

  // ─── Color tokens ───────────────────────────────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);
  static const _green = Color(0xFF3EC97A);

  static const Map<String, List<String>> reportCategories = {
    'Traffic-Related': [
      'Heavy traffic / congestion',
      'Road closure / construction',
      'Detour / alternative route',
      'Slow-moving vehicles',
    ],
    'Safety-Related': [
      'Accident / crash',
      'Hazard on road',
      'Crime / suspicious activity',
    ],
    'Transit-Specific': [
      'Bus/train delay',
      'Cancelled service',
      'Crowding / full capacity',
    ],
    'Weather-Related': [
      'Flooding / water logging',
      'Landslide / mudslide',
      'Storm / lightning hazard',
    ],
  };

  final Map<String, Color> modeColors = {
    'Walk': Colors.green,
    'Jeepney': Colors.blue,
    'Bus': Colors.red,
    'Train': Colors.purple,
    'Tricycle': Colors.orange,
    'FX/Van': Colors.amber,
    'Ferry': Colors.lightBlue,
  };

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

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadReports();
    _incrementViews();
    _generatePathPoints();
  }

  Future<void> _incrementViews() async {
    setState(() {
      widget.route.views++;
    });
  }

  Future<void> _initLocation() async {
    final permission = await Permission.location.request();
    if (permission.isGranted) {
      try {
        _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        setState(() {});
      } catch (e) {
        // Handle error
      }
    }
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
        setState(() {
          _routeReports = List.from(widget.route.reports);
        });
      }
    } catch (e) {
      setState(() {
        _routeReports = List.from(widget.route.reports);
      });
    }
  }

  Future<void> _saveReports() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/reports.json');
      Map<String, dynamic> allReports = {};
      if (await file.exists()) {
        final contents = await file.readAsString();
        allReports = jsonDecode(contents);
      }
      allReports[widget.route.id] =
          _routeReports
              .map(
                (r) => {
                  'type': r.type,
                  'description': r.description,
                  'timestamp': r.timestamp.millisecondsSinceEpoch,
                },
              )
              .toList();
      await file.writeAsString(jsonEncode(allReports));
    } catch (e) {
      // Handle error
    }
  }

  void _showReportDialog() {
    String? selectedType;
    String description = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setSheetState) => DraggableScrollableSheet(
                  initialChildSize: 0.75,
                  minChildSize: 0.5,
                  maxChildSize: 0.95,
                  builder:
                      (context, scrollController) => Container(
                        decoration: const BoxDecoration(
                          color: _bg,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: Column(
                          children: [
                            // Handle
                            Container(
                              margin: const EdgeInsets.only(top: 12),
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: _border,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            // Header
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                14,
                                16,
                                14,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: _danger.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: const Icon(
                                      Icons.report_problem_outlined,
                                      color: _danger,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Report an Issue',
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
                            Divider(color: _border, height: 1),
                            // Content
                            Expanded(
                              child: ListView(
                                controller: scrollController,
                                padding: const EdgeInsets.all(16),
                                children: [
                                  ...reportCategories.entries.map((entry) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      decoration: BoxDecoration(
                                        color: _surface,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: _border),
                                      ),
                                      child: Theme(
                                        data: Theme.of(context).copyWith(
                                          dividerColor: Colors.transparent,
                                        ),
                                        child: ExpansionTile(
                                          tilePadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 4,
                                              ),
                                          title: Text(
                                            entry.key,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: _textPrimary,
                                            ),
                                          ),
                                          iconColor: _accent,
                                          collapsedIconColor: _textSecondary,
                                          children:
                                              entry.value.map((type) {
                                                return GestureDetector(
                                                  onTap:
                                                      () => setSheetState(
                                                        () =>
                                                            selectedType = type,
                                                      ),
                                                  child: Container(
                                                    margin:
                                                        const EdgeInsets.fromLTRB(
                                                          10,
                                                          0,
                                                          10,
                                                          6,
                                                        ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          selectedType == type
                                                              ? _accentSoft
                                                              : _surfaceAlt,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            9,
                                                          ),
                                                      border: Border.all(
                                                        color:
                                                            selectedType == type
                                                                ? _accent
                                                                    .withOpacity(
                                                                      0.35,
                                                                    )
                                                                : _border,
                                                        width:
                                                            selectedType == type
                                                                ? 1.5
                                                                : 1,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Container(
                                                          width: 16,
                                                          height: 16,
                                                          decoration: BoxDecoration(
                                                            shape:
                                                                BoxShape.circle,
                                                            border: Border.all(
                                                              color:
                                                                  selectedType ==
                                                                          type
                                                                      ? _accent
                                                                      : _border,
                                                              width: 2,
                                                            ),
                                                            color:
                                                                selectedType ==
                                                                        type
                                                                    ? _accent
                                                                    : Colors
                                                                        .transparent,
                                                          ),
                                                          child:
                                                              selectedType ==
                                                                      type
                                                                  ? const Icon(
                                                                    Icons.check,
                                                                    size: 10,
                                                                    color:
                                                                        Colors
                                                                            .white,
                                                                  )
                                                                  : null,
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            type,
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              color:
                                                                  selectedType ==
                                                                          type
                                                                      ? _textPrimary
                                                                      : _textSecondary,
                                                              fontWeight:
                                                                  selectedType ==
                                                                          type
                                                                      ? FontWeight
                                                                          .w600
                                                                      : FontWeight
                                                                          .w400,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                        ),
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 4),
                                  // Description field
                                  Container(
                                    decoration: BoxDecoration(
                                      color: _surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _border),
                                    ),
                                    child: TextField(
                                      onChanged: (val) => description = val,
                                      maxLines: 3,
                                      style: const TextStyle(
                                        color: _textPrimary,
                                        fontSize: 14,
                                      ),
                                      decoration: const InputDecoration(
                                        hintText:
                                            'Additional description (optional)',
                                        hintStyle: TextStyle(
                                          color: _textSecondary,
                                          fontSize: 13,
                                        ),
                                        prefixIcon: Icon(
                                          Icons.edit_note_outlined,
                                          color: _accent,
                                          size: 20,
                                        ),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: 13,
                                          horizontal: 4,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => Navigator.pop(context),
                                          child: Container(
                                            height: 46,
                                            decoration: BoxDecoration(
                                              color: _surface,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: _border,
                                              ),
                                            ),
                                            alignment: Alignment.center,
                                            child: const Text(
                                              'Cancel',
                                              style: TextStyle(
                                                color: _textSecondary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        flex: 2,
                                        child: GestureDetector(
                                          onTap:
                                              selectedType != null
                                                  ? () => _submitReport(
                                                    selectedType!,
                                                    description,
                                                    context,
                                                  )
                                                  : null,
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            height: 46,
                                            decoration: BoxDecoration(
                                              gradient:
                                                  selectedType != null
                                                      ? const LinearGradient(
                                                        colors: [
                                                          Color(0xFFE05C6A),
                                                          Color(0xFFEA8A94),
                                                        ],
                                                        begin:
                                                            Alignment
                                                                .centerLeft,
                                                        end:
                                                            Alignment
                                                                .centerRight,
                                                      )
                                                      : null,
                                              color:
                                                  selectedType == null
                                                      ? _border
                                                      : null,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              boxShadow:
                                                  selectedType != null
                                                      ? [
                                                        BoxShadow(
                                                          color: _danger
                                                              .withOpacity(0.3),
                                                          blurRadius: 10,
                                                          offset: const Offset(
                                                            0,
                                                            3,
                                                          ),
                                                        ),
                                                      ]
                                                      : null,
                                            ),
                                            alignment: Alignment.center,
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.flag_outlined,
                                                  color:
                                                      selectedType != null
                                                          ? Colors.white
                                                          : _textSecondary,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Submit Report',
                                                  style: TextStyle(
                                                    color:
                                                        selectedType != null
                                                            ? Colors.white
                                                            : _textSecondary,
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
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                ),
          ),
    );
  }

  void _submitReport(
    String type,
    String description,
    BuildContext context,
  ) async {
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
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Report submitted!')));
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

  void _centerOnCurrentLocation() {
    if (_currentPosition != null) {
      _mapController.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        15.0,
      );
    }
  }

  void _onNotificationsDismissed() {
    setState(() {
      _showNotificationOverlay = false;
      _pendingNotifications.clear();
    });
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

    _pathPoints = [];
    for (int i = 0; i <= numSegments; i++) {
      _pathPoints.add(
        LatLng(start.latitude + latStep * i, start.longitude + lngStep * i),
      );
    }
  }

  void _vote(bool isUpvote) {
    if (_userVote != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have already voted on this route')),
      );
      return;
    }
    setState(() {
      _userVote = isUpvote;
      if (isUpvote) {
        widget.route.upvotes++;
      } else {
        widget.route.downvotes++;
      }
    });
  }

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
    if (widget.route.stepBoundaries.isNotEmpty) {
      List<Polyline> polys = [];
      for (int i = 0; i < widget.route.steps.length; i++) {
        final step = widget.route.steps[i];
        final color = modeColors[step.mode] ?? Colors.blue;
        final startIdx = (i == 0) ? 0 : widget.route.stepBoundaries[i - 1];
        final endIdx =
            (i < widget.route.stepBoundaries.length)
                ? widget.route.stepBoundaries[i]
                : _pathPoints.length - 1;
        if (endIdx > startIdx) {
          final stepPoints = _pathPoints.sublist(startIdx, endIdx + 1);
          polys.add(
            Polyline(
              points: stepPoints,
              color: Colors.black,
              strokeWidth: 8.0,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          );
          polys.add(
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
      return polys;
    } else {
      int totalPoints = _pathPoints.length;
      int numSteps = widget.route.steps.length;
      List<int> boundaries = [];
      for (int i = 1; i < numSteps; i++) {
        boundaries.add((i * (totalPoints - 1) / numSteps).round());
      }
      List<Polyline> polys = [];
      for (int i = 0; i < widget.route.steps.length; i++) {
        final step = widget.route.steps[i];
        final color = modeColors[step.mode] ?? Colors.blue;
        final startIdx = (i == 0) ? 0 : boundaries[i - 1];
        final endIdx =
            (i < boundaries.length) ? boundaries[i] : _pathPoints.length - 1;
        if (endIdx > startIdx) {
          final stepPoints = _pathPoints.sublist(startIdx, endIdx + 1);
          polys.add(
            Polyline(
              points: stepPoints,
              color: Colors.black,
              strokeWidth: 8.0,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          );
          polys.add(
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
      return polys;
    }
  }

  List<Marker> get markers {
    List<Marker> routeMarkers = [];
    final points = _pathPoints;
    if (points.isNotEmpty) {
      routeMarkers.add(
        Marker(
          point: points.first,
          child: const Icon(Icons.location_on, color: Colors.green, size: 40),
        ),
      );
    }
    if (points.length > 1) {
      routeMarkers.add(
        Marker(
          point: points.last,
          child: const Icon(Icons.flag, color: Colors.red, size: 40),
        ),
      );
    }
    if (_currentPosition != null) {
      routeMarkers.add(
        Marker(
          point: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          child: const Icon(Icons.my_location, color: Colors.blue, size: 40),
        ),
      );
    }
    return routeMarkers;
  }

  // ─── Shared UI helpers ─────────────────────────────────────────────────────
  Widget _metricCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.04),
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
              color: iconColor.withOpacity(0.1),
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

  Widget _sectionLabel(String label) => Padding(
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

  @override
  Widget build(BuildContext context) {
    if (_pathPoints.isEmpty) {
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
                child: const Icon(
                  Icons.map_outlined,
                  size: 36,
                  color: _textSecondary,
                ),
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

    final center = LatLng(
      (_pathPoints.first.latitude + _pathPoints.last.latitude) / 2,
      (_pathPoints.first.longitude + _pathPoints.last.longitude) / 2,
    );

    return Stack(
      children: [
        Scaffold(
          backgroundColor: _bg,
          // ─── AppBar ──────────────────────────────────────────────────
          appBar: AppBar(
            backgroundColor: _surface,
            foregroundColor: _textPrimary,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _border),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  size: 15,
                  color: _textSecondary,
                ),
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
                    const Icon(
                      Icons.arrow_forward,
                      size: 11,
                      color: _textSecondary,
                    ),
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
              // ── Vote buttons ──
              GestureDetector(
                onTap: _userVote == null ? () => _vote(true) : null,
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        _userVote == true
                            ? _green.withOpacity(0.12)
                            : _surfaceAlt,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color:
                          _userVote == true ? _green.withOpacity(0.4) : _border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.arrow_upward_rounded,
                        size: 15,
                        color: _userVote == true ? _green : _textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.route.upvotes}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _userVote == true ? _green : _textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: _userVote == null ? () => _vote(false) : null,
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        _userVote == false
                            ? _danger.withOpacity(0.1)
                            : _surfaceAlt,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color:
                          _userVote == false
                              ? _danger.withOpacity(0.35)
                              : _border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.arrow_downward_rounded,
                        size: 15,
                        color: _userVote == false ? _danger : _textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.route.downvotes}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _userVote == false ? _danger : _textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ── Report button ──
              GestureDetector(
                onTap: _showReportDialog,
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _danger.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _danger.withOpacity(0.25)),
                  ),
                  child: const Icon(
                    Icons.report_problem_outlined,
                    color: _danger,
                    size: 17,
                  ),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: _border),
            ),
          ),

          body: Column(
            children: [
              // ─── Map ───────────────────────────────────────────────
              Expanded(
                flex: 2,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: 10.0,
                        minZoom: 5.0,
                        maxZoom: 18.0,
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
                        MarkerLayer(markers: markers),
                        PolylineLayer(polylines: polylines),
                      ],
                    ),

                    // ── Mode legend ────────────────────────────────────
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _surface.withOpacity(0.95),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children:
                              modeColors.entries.map((entry) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: entry.value,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
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
                      ),
                    ),

                    // ── Center on location button ──────────────────────
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: GestureDetector(
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
                                color: _accent.withOpacity(0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.my_location_rounded,
                            color: _accent,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ─── Info panel ─────────────────────────────────────────
              Expanded(
                flex: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: _bg,
                    border: Border(top: BorderSide(color: _border, width: 1.5)),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ── Metrics chips row ─────────────────────────
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _metricCard(
                              icon: Icons.straighten,
                              iconColor: const Color(0xFF9B7FE8),
                              label: 'Distance',
                              value: RouteMetricsService.formatDistance(
                                RouteMetricsService.calculateRouteDistance(
                                  _pathPoints,
                                ),
                              ),
                            ),
                            if (widget.route.eta != null) ...[
                              const SizedBox(width: 10),
                              _metricCard(
                                icon: Icons.access_time_rounded,
                                iconColor: _accent,
                                label: 'ETA',
                                value: '${widget.route.eta} min',
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
                            if (widget.route.schedule != null) ...[
                              const SizedBox(width: 10),
                              _metricCard(
                                icon: Icons.schedule_outlined,
                                iconColor: const Color(0xFFE89A3C),
                                label: 'Schedule',
                                value: widget.route.schedule!,
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ── Route steps ───────────────────────────────
                      _sectionLabel(
                        'Route Steps (${widget.route.steps.length})',
                      ),
                      ...widget.route.steps.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final step = entry.value;
                        final modeColor = modeColors[step.mode] ?? _accent;

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
                                // Step number + mode icon
                                Column(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: modeColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: modeColor.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Icon(
                                        _getModeIcon(step.mode),
                                        color: modeColor,
                                        size: 18,
                                      ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),

                      // ── Recent reports ────────────────────────────
                      if (_routeReports.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _sectionLabel('Recent Reports'),
                        ..._routeReports.map(
                          (report) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _danger.withOpacity(0.2),
                              ),
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
                                      color: _danger.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Icon(
                                      _getReportIcon(report.type),
                                      color: _danger,
                                      size: 17,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                              fontSize: 12,
                                              color: _textSecondary,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.access_time,
                                              size: 11,
                                              color: _textSecondary,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              _formatTime(report.timestamp),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: _textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
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
}
