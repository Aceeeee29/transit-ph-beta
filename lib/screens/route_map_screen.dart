import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:convert';
import '../models/route.dart' as route_model;

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

  List<Polyline> get polylines {
    final Map<String, Color> modeColors = {
      'Walk': Colors.green,
      'Jeepney': Colors.blue,
      'Bus': Colors.red,
      'Train': Colors.purple,
      'Tricycle': Colors.orange,
      'FX/Van': Colors.amber,
      'Ferry': Colors.lightBlue,
    };

    List<Polyline> polylines = [];
    final points =
        widget.route.pathPoints.isNotEmpty
            ? widget.route.pathPoints
            : [
              LatLng(widget.route.startLat ?? 0, widget.route.startLng ?? 0),
              LatLng(widget.route.endLat ?? 0, widget.route.endLng ?? 0),
            ];

    for (int i = 0; i < widget.route.steps.length; i++) {
      final step = widget.route.steps[i];
      final color = modeColors[step.mode] ?? Colors.blue;
      final startIdx = i;
      final endIdx = i + 1;
      if (endIdx < points.length) {
        polylines.add(
          Polyline(
            points: [points[startIdx], points[endIdx]],
            color: color,
            strokeWidth: 4.0,
          ),
        );
      }
    }
    // Connect last step to end if more points
    if (widget.route.steps.length < points.length - 1) {
      polylines.add(
        Polyline(
          points: [points[widget.route.steps.length], points.last],
          color: Colors.grey,
          strokeWidth: 3.0,
        ),
      );
    }
    return polylines;
  }

  List<Marker> get markers {
    List<Marker> routeMarkers = [];
    final points =
        widget.route.pathPoints.isNotEmpty
            ? widget.route.pathPoints
            : [
              LatLng(widget.route.startLat ?? 0, widget.route.startLng ?? 0),
              LatLng(widget.route.endLat ?? 0, widget.route.endLng ?? 0),
            ];

    routeMarkers.addAll(
      points.asMap().entries.map((entry) {
        final index = entry.key;
        final point = entry.value;
        IconData icon = Icons.location_on;
        Color color = Colors.green;
        if (index == 0) {
          icon = Icons.location_on;
          color = Colors.green; // Start
        } else if (index == points.length - 1) {
          icon = Icons.flag;
          color = Colors.red; // End
        } else {
          // Intermediate for steps
          final stepIndex = index - 1;
          if (stepIndex < widget.route.steps.length) {
            final stepMode = widget.route.steps[stepIndex].mode;
            icon = _getModeIcon(stepMode);
            color =
                [
                  Colors.green,
                  Colors.blue,
                  Colors.red,
                  Colors.purple,
                  Colors.orange,
                  Colors.amber,
                  Colors.lightBlue,
                ][stepIndex % 7]; // Fallback colors if needed
          } else {
            icon = Icons.location_on;
            color = Colors.grey;
          }
        }
        return Marker(point: point, child: Icon(icon, color: color, size: 40));
      }),
    );

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
    final points =
        widget.route.pathPoints.isNotEmpty
            ? widget.route.pathPoints
            : [
              LatLng(
                widget.route.startLat ?? 12.8797,
                widget.route.startLng ?? 121.7740,
              ),
              LatLng(
                widget.route.endLat ?? 12.8797,
                widget.route.endLng ?? 121.7740,
              ),
            ];

    final center = LatLng(
      (points.first.latitude + points.last.latitude) / 2,
      (points.first.longitude + points.last.longitude) / 2,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.route.startLocation} to ${widget.route.endLocation}',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.report_problem),
            onPressed: _showReportDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 13.0,
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
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.app.transitph_beta',
                ),
                MarkerLayer(markers: markers),
                PolylineLayer(polylines: polylines),
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
                            const Icon(Icons.access_time, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              'ETA: ${widget.route.eta} minutes',
                              style: Theme.of(context).textTheme.titleMedium,
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
                        idx + 1 < points.length ? points[idx + 1] : points.last;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          _getModeIcon(step.mode),
                          color:
                              [
                                Colors.green,
                                Colors.blue,
                                Colors.red,
                                Colors.purple,
                                Colors.orange,
                                Colors.amber,
                                Colors.lightBlue,
                              ][idx % 7],
                        ),
                        title: Text(step.mode),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(step.instruction),
                            if (step.details.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                step.details,
                                style: const TextStyle(fontSize: 12),
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
    );
  }
}
