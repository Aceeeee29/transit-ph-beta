import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../models/route.dart' as route_model;
import '../services/route_metrics_service.dart';

class RoutePreview extends StatelessWidget {
  final route_model.Route route;
  final VoidCallback onEdit;
  final VoidCallback onSubmit;
  
  const RoutePreview({
    super.key,
    required this.route,
    required this.onEdit,
    required this.onSubmit,
  });
  
  @override
  Widget build(BuildContext context) {
    // Calculate route metrics
    final totalDistance = RouteMetricsService.calculateRouteDistance(route.pathPoints);
    final formattedDistance = RouteMetricsService.formatDistance(totalDistance);
    
    final modes = route.steps.map((step) => step.mode).toList();
    final eta = RouteMetricsService.calculateEta(
      route.pathPoints, 
      modes, 
      route.stepBoundaries,
    );
    final formattedEta = RouteMetricsService.formatEta(eta);
    
    final fare = RouteMetricsService.calculateFareEstimate(
      route.pathPoints, 
      modes, 
      route.stepBoundaries,
    );
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Preview'),
        actions: [
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit, color: Colors.white),
            label: const Text('Edit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Map preview
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _getRouteCenter(),
                initialZoom: _calculateZoomLevel(),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.app.transitph_beta',
                ),
                PolylineLayer(polylines: _buildPolylines()),
                MarkerLayer(markers: _buildMarkers()),
              ],
            ),
          ),
          
          // Route details
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${route.startLocation} to ${route.endLocation}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  route.shortDescription,
                  style: const TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Route metrics
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMetricItem(Icons.straighten, formattedDistance),
                    _buildMetricItem(Icons.schedule, formattedEta),
                    _buildMetricItem(Icons.attach_money, fare),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Steps summary
                const Text(
                  'Steps:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: route.steps.length,
                  itemBuilder: (context, index) {
                    final step = route.steps[index];
                    return ListTile(
                      leading: _getModeIcon(step.mode),
                      title: Text(step.instruction),
                      subtitle: Text(step.details),
                      dense: true,
                    );
                  },
                ),
                const SizedBox(height: 16),
                
                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Submit Route',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMetricItem(IconData icon, String text) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(height: 4),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  List<Polyline> _buildPolylines() {
    List<Polyline> polylines = [];
    
    for (int i = 0; i < route.steps.length; i++) {
      final step = route.steps[i];
      final color = _getModeColor(step.mode);
      
      final startIdx = (i == 0) ? 0 : route.stepBoundaries[i - 1];
      final endIdx = (i < route.stepBoundaries.length)
          ? route.stepBoundaries[i]
          : route.pathPoints.length - 1;
      
      if (endIdx > startIdx) {
        final stepPoints = route.pathPoints.sublist(startIdx, endIdx + 1);
        
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
  
  List<Marker> _buildMarkers() {
    List<Marker> markers = [];
    
    // Start marker
    if (route.pathPoints.isNotEmpty) {
      markers.add(
        Marker(
          point: route.pathPoints.first,
          child: const Icon(
            Icons.location_on,
            color: Colors.green,
            size: 40,
          ),
        ),
      );
    }
    
    // End marker
    if (route.pathPoints.length > 1) {
      markers.add(
        Marker(
          point: route.pathPoints.last,
          child: const Icon(
            Icons.flag,
            color: Colors.red,
            size: 40,
          ),
        ),
      );
    }
    
    // Step boundary markers
    for (int i = 0; i < route.stepBoundaries.length; i++) {
      final boundaryIdx = route.stepBoundaries[i];
      if (boundaryIdx < route.pathPoints.length) {
        markers.add(
          Marker(
            point: route.pathPoints[boundaryIdx],
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 2),
              ),
              width: 24,
              height: 24,
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    
    return markers;
  }
  
  LatLng _getRouteCenter() {
    if (route.pathPoints.isEmpty) {
      // Default to Philippines center if no points
      return const LatLng(12.8797, 121.7740);
    }
    
    // Calculate the center of the route
    double sumLat = 0;
    double sumLng = 0;
    
    for (final point in route.pathPoints) {
      sumLat += point.latitude;
      sumLng += point.longitude;
    }
    
    return LatLng(
      sumLat / route.pathPoints.length,
      sumLng / route.pathPoints.length,
    );
  }
  
  double _calculateZoomLevel() {
    if (route.pathPoints.length < 2) {
      return 13.0; // Default zoom for single point
    }
    
    // Find the bounding box of the route
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;
    
    for (final point in route.pathPoints) {
      minLat = point.latitude < minLat ? point.latitude : minLat;
      maxLat = point.latitude > maxLat ? point.latitude : maxLat;
      minLng = point.longitude < minLng ? point.longitude : minLng;
      maxLng = point.longitude > maxLng ? point.longitude : maxLng;
    }
    
    // Calculate the span
    final latSpan = maxLat - minLat;
    final lngSpan = maxLng - minLng;
    
    // Determine zoom level based on span
    // These values are approximate and may need adjustment
    if (latSpan > 0.5 || lngSpan > 0.5) {
      return 10.0; // Very large route
    } else if (latSpan > 0.2 || lngSpan > 0.2) {
      return 12.0; // Large route
    } else if (latSpan > 0.05 || lngSpan > 0.05) {
      return 13.0; // Medium route
    } else if (latSpan > 0.01 || lngSpan > 0.01) {
      return 14.0; // Small route
    } else {
      return 15.0; // Very small route
    }
  }
  
  Widget _getModeIcon(String mode) {
    IconData iconData;
    Color color;
    
    switch (mode) {
      case 'Walk':
        iconData = Icons.directions_walk;
        color = Colors.green;
        break;
      case 'Jeepney':
        iconData = Icons.directions_bus;
        color = Colors.blue;
        break;
      case 'Bus':
        iconData = Icons.directions_bus_filled;
        color = Colors.red;
        break;
      case 'Train':
        iconData = Icons.train;
        color = Colors.purple;
        break;
      case 'Tricycle':
        iconData = Icons.pedal_bike;
        color = Colors.orange;
        break;
      case 'FX/Van':
        iconData = Icons.directions_car;
        color = Colors.amber;
        break;
      case 'Ferry':
        iconData = Icons.directions_boat;
        color = Colors.lightBlue;
        break;
      default:
        iconData = Icons.directions_walk;
        color = Colors.green;
    }
    
    return Icon(iconData, color: color);
  }
  
  Color _getModeColor(String mode) {
    switch (mode) {
      case 'Walk':
        return Colors.green;
      case 'Jeepney':
        return Colors.blue;
      case 'Bus':
        return Colors.red;
      case 'Train':
        return Colors.purple;
      case 'Tricycle':
        return Colors.orange;
      case 'FX/Van':
        return Colors.amber;
      case 'Ferry':
        return Colors.lightBlue;
      default:
        return Colors.green;
    }
  }
}
