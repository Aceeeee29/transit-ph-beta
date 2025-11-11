import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/route.dart' as route_model;
import '../services/gamification_service.dart';
import '../widgets/notification_overlay.dart';

class ContributeScreen extends StatefulWidget {
  final void Function(route_model.Route) onRouteSubmitted;

  const ContributeScreen({super.key, required this.onRouteSubmitted});

  @override
  State<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends State<ContributeScreen> {
  final _formKey = GlobalKey<FormState>();
  final MapController _mapController = MapController();

  final TextEditingController _startLocationController =
      TextEditingController();
  final TextEditingController _endLocationController = TextEditingController();
  final TextEditingController _shortDescriptionController =
      TextEditingController();
  final TextEditingController _etaController = TextEditingController();

  List<LatLng> pathPoints = [];
  List<route_model.Step> steps = [];
  List<int> stepBoundaries = [];
  String currentMode = 'Walk';
  String selectionMode = 'start'; // 'start', 'step', 'end', 'done'
  String? selectedRegion;

  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;

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
  void dispose() {
    _startLocationController.dispose();
    _endLocationController.dispose();
    _shortDescriptionController.dispose();
    _etaController.dispose();
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
      // Try to get route from OpenRouteService
      if (pathPoints.isNotEmpty) {
        final lastPoint = pathPoints.last;
        try {
          final routePoints = await _getRouteFromAPI(lastPoint, point);
          if (routePoints.isNotEmpty) {
            setState(() {
              pathPoints.addAll(routePoints);
            });
          } else {
            // Fallback to straight line if API fails
            setState(() {
              pathPoints.add(point);
            });
          }
        } catch (e) {
          // Fallback to straight line if API fails
          setState(() {
            pathPoints.add(point);
          });
        }
        _showStepDialog();
      }
    }
  }

  Future<List<LatLng>> _getRouteFromAPI(LatLng start, LatLng end) async {
    const String apiKey =
        'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjI4YWQ4ZGE2ZWQ3MDRhYjVhY2FlMWZmMWE0MWZkMjIxIiwiaCI6Im11cm11cjY0In0='; // Provided API key
    final url = Uri.parse(
      'https://api.openrouteservice.org/v2/directions/driving-car?api_key=$apiKey&start=${start.longitude},${start.latitude}&end=${end.longitude},${end.latitude}',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coordinates =
            data['features'][0]['geometry']['coordinates'] as List;
        return coordinates.map((coord) => LatLng(coord[1], coord[0])).toList();
      } else {
        throw Exception('Failed to fetch route');
      }
    } catch (e) {
      rethrow;
    }
  }

  void _onRegionChanged(String? region) {
    if (region != null && philippineRegions.containsKey(region)) {
      final bounds = philippineRegions[region]!;

      // Special handling for Philippines - reset to initial view
      if (region == 'Philippines') {
        _mapController.move(const LatLng(12.8797, 121.7740), 6.0);
      } else if (region == 'MIMAROPA Region (Region IV-B)') {
        // Special handling for MIMAROPA - use move instead of fitCamera
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
          (context) => AlertDialog(
            title: const Text('Select Transport Mode for Next Step'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:
                    modes
                        .map(
                          (mode) => ListTile(
                            leading: Icon(
                              _getModeIcon(mode),
                              color: modeColors[mode],
                            ),
                            title: Text(mode),
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
                          ),
                        )
                        .toList(),
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
          (context) => AlertDialog(
            title: Text('Step: $currentMode'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  onChanged: (value) => instruction = value,
                  decoration: const InputDecoration(
                    labelText:
                        'Instruction (e.g., Ride a jeep with Cubao terminal)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (value) => details = value,
                  decoration: const InputDecoration(
                    labelText: 'Details (e.g., Drop off at Gateway Mall)',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  pathPoints.removeLast(); // Remove the point if cancel
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
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
                child: const Text('Save Step'),
              ),
            ],
          ),
    );
  }

  void _showAddAnotherStepDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Another Step?'),
            content: Text(
              'You have added ${steps.length} steps. Add more or finish the route?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showModeDialog();
                },
                child: const Text('Add Another Step'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    selectionMode = 'done';
                  });
                },
                child: const Text('Finish Route'),
              ),
            ],
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
        eta: _etaController.text.isEmpty ? null : _etaController.text,
      );

      widget.onRouteSubmitted(route);

      // Award points for contributing
      final user = await GamificationService.loadUser();
      final unlockedItems =
          await GamificationService.incrementRoutesContributed(user);

      // Show achievement notifications
      if (unlockedItems.isNotEmpty) {
        setState(() {
          _pendingNotifications = unlockedItems;
          _showNotificationOverlay = true;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route submitted for review!')),
      );

      // Reset form
      setState(() {
        pathPoints = [];
        steps = [];
        stepBoundaries = [];
        selectionMode = 'start';
        _startLocationController.clear();
        _endLocationController.clear();
        _shortDescriptionController.clear();
        _etaController.clear();
      });
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text('Contribute a Route')),
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
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
                          userAgentPackageName:
                              'com.example.app.transitph_beta',
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
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 200,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: DropdownButton<String>(
                          value: selectedRegion,
                          hint: const Text('Select Region'),
                          isExpanded: true,
                          underline: const SizedBox(),
                          items:
                              philippineRegions.keys.map((region) {
                                return DropdownMenuItem<String>(
                                  value: region,
                                  child: Text(
                                    region,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              }).toList(),
                          onChanged: _onRegionChanged,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 80,
                      left: 0,
                      right: 0,
                      child: Text(
                        _getInstructionText(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              offset: Offset(1, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _startLocationController,
                        decoration: const InputDecoration(
                          labelText:
                              'Starting Location (tap map to select or type)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _endLocationController,
                        decoration: const InputDecoration(
                          labelText: 'End Location (tap map to select or type)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _shortDescriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Short Description',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                        validator:
                            (value) =>
                                value?.isEmpty ?? true
                                    ? 'Short description is required'
                                    : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _etaController,
                        decoration: const InputDecoration(
                          labelText:
                              'Estimated Time of Arrival (ETA) in minutes',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator:
                            (value) =>
                                value?.isEmpty ?? true
                                    ? 'ETA is required'
                                    : null,
                      ),
                      const SizedBox(height: 16),
                      Text('Steps added: ${steps.length}'),
                      const SizedBox(height: 16),
                      if (selectionMode == 'done')
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _submit,
                            child: const Text(
                              'Submit for Review',
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      if (selectionMode != 'done')
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                pathPoints.clear();
                                steps.clear();
                                stepBoundaries.clear();
                                selectionMode = 'start';
                                _startLocationController.clear();
                                _endLocationController.clear();
                                _shortDescriptionController.clear();
                                _etaController.clear();
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Reset Route',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
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
