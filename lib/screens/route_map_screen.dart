import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:convert';
import '../models/route.dart' as route_model;
import '../services/gamification_service.dart';
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
  bool? _userVote; // true for upvote, false for downvote, null for no vote
  List<LatLng> _pathPoints = [];

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
    // Increment views for this route
    // Assuming routes are stored in a file or service, update the views count
    // For now, we'll just update the widget's route if possible
    // In a real app, this would be persisted to a database
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
      final file = File('reports.json');
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
      final file = File('reports.json');
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
      // Handle error, perhaps show SnackBar
    }
  }

  void _showReportDialog() {
    String? selectedType;
    String description = '';

    showModalBottomSheet(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Report Issue',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView(
                          children:
                              reportCategories.entries
                                  .map(
                                    (entry) => ExpansionTile(
                                      title: Text(entry.key),
                                      children:
                                          entry.value
                                              .map(
                                                (type) => RadioListTile<String>(
                                                  title: Text(type),
                                                  value: type,
                                                  groupValue: selectedType,
                                                  onChanged:
                                                      (value) => setState(
                                                        () =>
                                                            selectedType =
                                                                value,
                                                      ),
                                                ),
                                              )
                                              .toList(),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                      TextField(
                        onChanged: (val) => description = val,
                        decoration: const InputDecoration(
                          labelText: 'Additional Description (optional)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed:
                                selectedType != null
                                    ? () => _submitReport(
                                      selectedType!,
                                      description,
                                      context,
                                    )
                                    : null,
                            child: const Text('Submit'),
                          ),
                        ],
                      ),
                    ],
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

    // Award points for reporting
    final user = await GamificationService.loadUser();
    final unlockedItems = await GamificationService.incrementReportsSubmitted(
      user,
    );

    // Show achievement notifications
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

    // Generate points by interpolating between start and end
    // Number of segments = number of steps
    final numSegments = widget.route.steps.length;
    final latStep = (end.latitude - start.latitude) / numSegments;
    final lngStep = (end.longitude - start.longitude) / numSegments;

    _pathPoints = [];
    for (int i = 0; i <= numSegments; i++) {
      final lat = start.latitude + latStep * i;
      final lng = start.longitude + lngStep * i;
      _pathPoints.add(LatLng(lat, lng));
    }
  }

  void _vote(bool isUpvote) {
    if (_userVote != null) {
      // User has already voted, don't allow another vote
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
    // In a real app, persist this to a database
  }

  // Favorites functionality removed

  final Map<String, Color> modeColors = {
    'Walk': Colors.green,
    'Jeepney': Colors.blue,
    'Bus': Colors.red,
    'Train': Colors.purple,
    'Tricycle': Colors.orange,
    'FX/Van': Colors.amber,
    'Ferry': Colors.lightBlue,
  };

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
      // New logic for routes with stepBoundaries
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
      // Compute even boundaries for routes without stepBoundaries
      int totalPoints = _pathPoints.length;
      int numSteps = widget.route.steps.length;
      List<int> boundaries = [];
      for (int i = 1; i < numSteps; i++) {
        boundaries.add((i * (totalPoints - 1) / numSteps).round());
      }
      // Use the same logic as new routes
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

    // Add start marker
    if (points.isNotEmpty) {
      routeMarkers.add(
        Marker(
          point: points.first,
          child: const Icon(Icons.location_on, color: Colors.green, size: 40),
        ),
      );
    }

    // Add end marker
    if (points.length > 1) {
      routeMarkers.add(
        Marker(
          point: points.last,
          child: const Icon(Icons.flag, color: Colors.red, size: 40),
        ),
      );
    }

    // Add current location marker
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

  @override
  Widget build(BuildContext context) {
    final center = LatLng(
      (_pathPoints.first.latitude + _pathPoints.last.latitude) / 2,
      (_pathPoints.first.longitude + _pathPoints.last.longitude) / 2,
    );

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(
              '${widget.route.startLocation} to ${widget.route.endLocation}',
            ),
            actions: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _userVote == true
                          ? Icons.arrow_upward
                          : Icons.arrow_upward,
                      color: _userVote == true ? Colors.green : null,
                    ),
                    onPressed: _userVote == null ? () => _vote(true) : null,
                  ),
                  Text('${widget.route.upvotes}'),
                  IconButton(
                    icon: Icon(
                      _userVote == false
                          ? Icons.arrow_downward
                          : Icons.arrow_downward,
                      color: _userVote == false ? Colors.red : null,
                    ),
                    onPressed: _userVote == null ? () => _vote(false) : null,
                  ),
                  Text('${widget.route.downvotes}'),
                  IconButton(
                    icon: const Icon(Icons.report_problem),
                    onPressed: _showReportDialog,
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
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
                            const LatLng(
                              4.5,
                              116.0,
                            ), // Southwest corner (Mindanao area)
                            const LatLng(
                              21.5,
                              127.0,
                            ), // Northeast corner (Batanes + eastern sea)
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
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children:
                              modeColors.entries.map((entry) {
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      color: entry.value,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      entry.key,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                );
                              }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ListView(
                    children: [
                      if (widget.route.eta != null)
                        Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'ETA: ${widget.route.eta} minutes',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      Text(
                        'Route Steps (${widget.route.steps.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ...widget.route.steps.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final step = entry.value;
                        final points =
                            widget.route.pathPoints.isNotEmpty
                                ? widget.route.pathPoints
                                : [
                                  LatLng(
                                    widget.route.startLat ?? 0,
                                    widget.route.startLng ?? 0,
                                  ),
                                  LatLng(
                                    widget.route.endLat ?? 0,
                                    widget.route.endLng ?? 0,
                                  ),
                                ];
                        final startPoint =
                            idx < points.length ? points[idx] : points.first;
                        final endPoint =
                            idx + 1 < points.length
                                ? points[idx + 1]
                                : points.last;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              _getModeIcon(step.mode),
                              color: modeColors[step.mode] ?? Colors.blue,
                            ),
                            title: Text(step.mode),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step.instruction,
                                  softWrap: true,
                                  overflow: TextOverflow.visible,
                                ),
                                if (step.details.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    step.details,
                                    style: const TextStyle(fontSize: 12),
                                    softWrap: true,
                                    overflow: TextOverflow.visible,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                      if (_routeReports.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Recent Reports',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ..._routeReports.map(
                          (report) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(_getReportIcon(report.type)),
                              title: Text(report.type),
                              subtitle: Text(
                                '${report.description ?? ''}\n${_formatTime(report.timestamp)}',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _centerOnCurrentLocation,
            child: const Icon(Icons.my_location),
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
