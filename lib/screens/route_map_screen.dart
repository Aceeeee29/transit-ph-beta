import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/route.dart' as route_model;

class RouteMapScreen extends StatelessWidget {
  final route_model.Route route;

  const RouteMapScreen({super.key, required this.route});

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
        route.pathPoints.isNotEmpty
            ? route.pathPoints
            : [
              LatLng(route.startLat ?? 0, route.startLng ?? 0),
              LatLng(route.endLat ?? 0, route.endLng ?? 0),
            ];

    for (int i = 0; i < route.steps.length; i++) {
      final step = route.steps[i];
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
    if (route.steps.length < points.length - 1) {
      polylines.add(
        Polyline(
          points: [points[route.steps.length], points.last],
          color: Colors.grey,
          strokeWidth: 3.0,
        ),
      );
    }
    return polylines;
  }

  List<Marker> get markers {
    final points =
        route.pathPoints.isNotEmpty
            ? route.pathPoints
            : [
              LatLng(route.startLat ?? 0, route.startLng ?? 0),
              LatLng(route.endLat ?? 0, route.endLng ?? 0),
            ];

    return points.asMap().entries.map((entry) {
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
        if (stepIndex < route.steps.length) {
          final stepMode = route.steps[stepIndex].mode;
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
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final points =
        route.pathPoints.isNotEmpty
            ? route.pathPoints
            : [
              LatLng(route.startLat ?? 12.8797, route.startLng ?? 121.7740),
              LatLng(route.endLat ?? 12.8797, route.endLng ?? 121.7740),
            ];

    final center = LatLng(
      (points.first.latitude + points.last.latitude) / 2,
      (points.first.longitude + points.last.longitude) / 2,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${route.startLocation} to ${route.endLocation}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Route Steps (${route.steps.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...route.steps.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final step = entry.value;
                  final points =
                      route.pathPoints.isNotEmpty
                          ? route.pathPoints
                          : [
                            LatLng(route.startLat ?? 0, route.startLng ?? 0),
                            LatLng(route.endLat ?? 0, route.endLng ?? 0),
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
                          Text(
                            'From: ${startPoint.latitude.toStringAsFixed(4)}, ${startPoint.longitude.toStringAsFixed(4)} '
                            'To: ${endPoint.latitude.toStringAsFixed(4)}, ${endPoint.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
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
      ),
    );
  }
}
