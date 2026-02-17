import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/route_history_service.dart';
import '../services/route_metrics_service.dart';
import '../services/routing_service.dart';
import '../models/route.dart' as route_model;

class MapControls extends StatefulWidget {
  final RouteHistoryService historyService;
  final List<LatLng> pathPoints;
  final List<route_model.Step> steps;
  final List<int> stepBoundaries;
  final String selectionMode;
  final String currentMode;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onReset;
  final VoidCallback onPreview;
  final Function(bool) onSnapToRoadToggled;
  final bool showPreview;
  final bool snapToRoadEnabled;

  const MapControls({
    super.key,
    required this.historyService,
    required this.pathPoints,
    required this.steps,
    required this.stepBoundaries,
    required this.selectionMode,
    this.currentMode = 'Walk',
    required this.onUndo,
    required this.onRedo,
    required this.onReset,
    required this.onPreview,
    required this.onSnapToRoadToggled,
    this.showPreview = true,
    this.snapToRoadEnabled = true,
  });

  @override
  State<MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends State<MapControls> {
  bool _showMetrics = true;
  bool _expanded = false;

  String _getModeText(String mode) {
    switch (mode) {
      case 'start':
        return 'Select Start Point';
      case 'step':
        return 'Add Route Points';
      case 'done':
        return 'Route Complete';
      default:
        return 'Select Mode';
    }
  }

  Color _getModeColor(String mode) {
    switch (mode) {
      case 'start':
        return Colors.green;
      case 'step':
        return Colors.blue;
      case 'done':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate total distance and ETA
    final totalDistance = RouteMetricsService.calculateRouteDistance(
      widget.pathPoints,
    );
    final formattedDistance = RouteMetricsService.formatDistance(totalDistance);

    final modes = widget.steps.map((step) => step.mode).toList();
    final eta = RouteMetricsService.calculateEta(
      widget.pathPoints,
      modes,
      widget.stepBoundaries,
    );
    final formattedEta = RouteMetricsService.formatEta(eta);

    final fare = RouteMetricsService.calculateFareEstimate(
      widget.pathPoints,
      modes,
      widget.stepBoundaries,
    );

    return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: _expanded ? 220 : 60,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Expand/Collapse button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_expanded)
                    // Mode indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getModeColor(widget.selectionMode),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _getModeText(widget.selectionMode),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      _expanded ? Icons.chevron_left : Icons.chevron_right,
                    ),
                    onPressed: () {
                      setState(() {
                        _expanded = !_expanded;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 20,
                  ),
                ],
              ),

              if (_expanded) ...[
                const SizedBox(height: 8),

                // Current transport mode indicator (only in step mode)
                if (widget.selectionMode == 'step') ...[
                  Row(
                    children: [
                      Icon(
                        _getModeIcon(widget.currentMode),
                        color: _getModeIconColor(widget.currentMode),
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Mode: ${widget.currentMode}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Snap to road toggle
                if (widget.selectionMode == 'step') ...[
                  Row(
                    children: [
                      const Text('Snap to Road:'),
                      const SizedBox(width: 4),
                      Switch(
                        value: widget.snapToRoadEnabled,
                        onChanged: widget.onSnapToRoadToggled,
                        activeThumbColor: Colors.blue,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],

                // Route metrics toggle
                if (widget.pathPoints.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Route Metrics:'),
                      IconButton(
                        icon: Icon(
                          _showMetrics
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _showMetrics = !_showMetrics;
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        iconSize: 20,
                      ),
                    ],
                  ),

                  // Route metrics
                  if (_showMetrics) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.straighten, size: 16),
                        const SizedBox(width: 4),
                        Text('Distance: $formattedDistance'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 16),
                        const SizedBox(width: 4),
                        Text('ETA: $formattedEta'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.attach_money, size: 16),
                        const SizedBox(width: 4),
                        Text('Fare: $fare'),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                ],

                // Controls - Using Wrap for better layout handling
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    // Undo button
                    SizedBox(
                      width: 40,
                      child: IconButton(
                        onPressed:
                            widget.historyService.canUndo
                                ? widget.onUndo
                                : null,
                        icon: const Icon(Icons.undo, size: 18),
                        tooltip: 'Undo',
                        color:
                            widget.historyService.canUndo
                                ? Colors.blue
                                : Colors.grey,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    ),
                    // Redo button
                    SizedBox(
                      width: 40,
                      child: IconButton(
                        onPressed:
                            widget.historyService.canRedo
                                ? widget.onRedo
                                : null,
                        icon: const Icon(Icons.redo, size: 18),
                        tooltip: 'Redo',
                        color:
                            widget.historyService.canRedo
                                ? Colors.blue
                                : Colors.grey,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    ),
                    // Reset button
                    SizedBox(
                      width: 40,
                      child: IconButton(
                        onPressed:
                            widget.pathPoints.isNotEmpty
                                ? widget.onReset
                                : null,
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: 'Reset',
                        color:
                            widget.pathPoints.isNotEmpty
                                ? Colors.red
                                : Colors.grey,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    ),
                    // Preview button
                    if (widget.showPreview && widget.pathPoints.isNotEmpty)
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          onPressed: widget.onPreview,
                          icon: const Icon(Icons.preview, size: 18),
                          tooltip: 'Preview Route',
                          color: Colors.green,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                        ),
                      ),
                  ],
                ),
              ] else ...[
                // Vertical controls for collapsed mode
                const SizedBox(height: 8),
                if (widget.historyService.canUndo)
                  IconButton(
                    onPressed: widget.onUndo,
                    icon: const Icon(Icons.undo),
                    tooltip: 'Undo',
                    color: Colors.blue,
                  ),
                if (widget.historyService.canRedo)
                  IconButton(
                    onPressed: widget.onRedo,
                    icon: const Icon(Icons.redo),
                    tooltip: 'Redo',
                    color: Colors.blue,
                  ),
                if (widget.pathPoints.isNotEmpty)
                  IconButton(
                    onPressed: widget.onReset,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Reset',
                    color: Colors.red,
                  ),
                if (widget.showPreview && widget.pathPoints.isNotEmpty)
                  IconButton(
                    onPressed: widget.onPreview,
                    icon: const Icon(Icons.preview),
                    tooltip: 'Preview Route',
                    color: Colors.green,
                  ),
              ],
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideX(
          begin: -0.2,
          end: 0,
          duration: 300.ms,
          curve: Curves.easeOutQuad,
        );
  }

  IconData _getModeIcon(String mode) {
    switch (mode) {
      case 'Walk':
        return Icons.directions_walk;
      case 'Jeepney':
        return Icons.directions_bus;
      case 'Bus':
        return Icons.directions_bus_filled;
      case 'Train':
        return Icons.train;
      case 'Tricycle':
        return Icons.pedal_bike;
      case 'FX/Van':
        return Icons.directions_car;
      case 'Ferry':
        return Icons.directions_boat;
      default:
        return Icons.directions_walk;
    }
  }

  Color _getModeIconColor(String mode) {
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

/// Widget to show a live preview of the route as it's being drawn
class RoutePreviewOverlay extends StatelessWidget {
  final LatLng startPoint;
  final LatLng endPoint;
  final String transportMode;

  const RoutePreviewOverlay({
    super.key,
    required this.startPoint,
    required this.endPoint,
    required this.transportMode,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate distance between points
    final distance = const Distance().as(
      LengthUnit.Kilometer,
      startPoint,
      endPoint,
    );

    // Calculate ETA based on transport mode
    final etaMinutes = _calculateEta(distance, transportMode);

    return Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getModeIcon(transportMode),
                        color: _getModeColor(transportMode),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${distance.toStringAsFixed(2)} km',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.schedule),
                      const SizedBox(width: 8),
                      Text(
                        '$etaMinutes min',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 200.ms)
        .slideY(
          begin: 0.5,
          end: 0,
          duration: 300.ms,
          curve: Curves.easeOutQuad,
        );
  }

  int _calculateEta(double distanceKm, String mode) {
    double speedKmh;

    switch (mode) {
      case 'Walk':
        speedKmh = 5.0;
        break;
      case 'Jeepney':
        speedKmh = 20.0;
        break;
      case 'Bus':
        speedKmh = 25.0;
        break;
      case 'Train':
        speedKmh = 40.0;
        break;
      case 'Tricycle':
        speedKmh = 15.0;
        break;
      case 'FX/Van':
        speedKmh = 30.0;
        break;
      case 'Ferry':
        speedKmh = 20.0;
        break;
      default:
        speedKmh = 5.0;
    }

    final hours = distanceKm / speedKmh;
    return (hours * 60).ceil();
  }

  IconData _getModeIcon(String mode) {
    switch (mode) {
      case 'Walk':
        return Icons.directions_walk;
      case 'Jeepney':
        return Icons.directions_bus;
      case 'Bus':
        return Icons.directions_bus_filled;
      case 'Train':
        return Icons.train;
      case 'Tricycle':
        return Icons.pedal_bike;
      case 'FX/Van':
        return Icons.directions_car;
      case 'Ferry':
        return Icons.directions_boat;
      default:
        return Icons.directions_walk;
    }
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
