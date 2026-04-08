import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../models/route.dart' as route_model;
import '../services/route_metrics_service.dart';

class RoutePreview extends StatelessWidget {
  final route_model.Route route;
  final VoidCallback? onEdit;
  final VoidCallback? onSubmit;
  final bool readOnly;

  const RoutePreview({
    super.key,
    required this.route,
    this.onEdit,
    this.onSubmit,
    this.readOnly = false,
  }) : assert(
          readOnly || (onEdit != null && onSubmit != null),
          'onEdit and onSubmit are required when readOnly is false',
        );

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _green = Color(0xFF3EC97A);

  @override
  Widget build(BuildContext context) {
    // Distance: prefer ORS-derived distance string, fall back to haversine calculation
    final formattedDistance = () {
      if (route.distanceMeters != null && route.distanceMeters! > 0) {
        return RouteMetricsService.formatDistanceMeters(route.distanceMeters!);
      }

      final parsedKm = RouteMetricsService.parseDistanceToKm(route.distance);
      if (parsedKm != null) {
        return RouteMetricsService.formatDistance(parsedKm);
      }

      return RouteMetricsService.formatDistance(
        RouteMetricsService.calculateRouteDistance(route.pathPoints),
      );
    }();

    // Prefer ORS-derived ETA/fare stored on the route over recalculating
    final formattedEta = route.eta != null && route.eta!.isNotEmpty
      ? RouteMetricsService.formatEtaLabel(route.eta)
        : RouteMetricsService.formatEta(RouteMetricsService.calculateEta(
            route.pathPoints,
            route.steps.map((s) => s.mode).toList(),
            route.stepBoundaries,
          ));

    final fare = (route.price != null && route.price!.isNotEmpty)
        ? route.price!
        : RouteMetricsService.calculateFareEstimate(
            route.pathPoints,
            route.steps.map((s) => s.mode).toList(),
            route.stepBoundaries,
          );

    return Scaffold(
      backgroundColor: _bg,
      // ─── AppBar ────────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: Builder(
          builder:
              (context) => GestureDetector(
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
        ),
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
                Icons.preview_rounded,
                color: _accent,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Route Preview',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          if (!readOnly && onEdit != null)
            GestureDetector(
              onTap: onEdit,
              child: Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _border),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.edit_outlined, color: _textSecondary, size: 14),
                    SizedBox(width: 5),
                    Text(
                      'Edit',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
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
          // ─── Map ─────────────────────────────────────────────────────────
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

          // ─── Details panel ────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: _surface,
              border: Border(top: BorderSide(color: _border, width: 1.5)),
              boxShadow: [
                BoxShadow(
                  color: _accent.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Route title ──────────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _accentSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.alt_route,
                          color: _accent,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.radio_button_checked,
                                  size: 11,
                                  color: _green,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    route.startLocation,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: _textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 11,
                                  color: _accent,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    route.endLocation,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: _textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (route.shortDescription.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                route.shortDescription,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _textSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── Metrics row ──────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      children: [
                        _metricCell(
                          icon: Icons.straighten,
                          color: const Color(0xFF9B7FE8),
                          label: 'Distance',
                          value: formattedDistance,
                        ),
                        _vDivider(),
                        _metricCell(
                          icon: Icons.schedule_outlined,
                          color: _accent,
                          label: 'ETA',
                          value: formattedEta,
                        ),
                        _vDivider(),
                        _metricCell(
                          icon: Icons.payments_outlined,
                          color: _green,
                          label: 'Fare',
                          value: fare,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Steps summary ────────────────────────────────────────
                  const Text(
                    'STEPS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: route.steps.length,
                    itemBuilder: (context, index) {
                      final step = route.steps[index];
                      final modeColor = _getModeColor(step.mode);
                      final modeIconData = _getModeIconData(step.mode);
                      final isLast = index == route.steps.length - 1;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Timeline column
                          Column(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: modeColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: modeColor.withOpacity(0.3),
                                  ),
                                ),
                                child: Icon(
                                  modeIconData,
                                  color: modeColor,
                                  size: 16,
                                ),
                              ),
                              if (!isLast)
                                Container(
                                  width: 2,
                                  height: 24,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _border,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    step.mode,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: modeColor,
                                    ),
                                  ),
                                  Text(
                                    step.instruction,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: _textPrimary,
                                      height: 1.4,
                                    ),
                                  ),
                                  if (step.details.isNotEmpty)
                                    Text(
                                      step.details,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: _textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  if (!readOnly && onSubmit != null) ...[
                    const SizedBox(height: 16),

                    // ── Submit button ────────────────────────────────────────
                    GestureDetector(
                      onTap: () async {
                      final confirm = await showDialog<bool>(
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
                                    // Dialog header
                                    Container(
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        18,
                                        16,
                                        16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _surface,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(20),
                                            ),
                                        border: Border(
                                          bottom: BorderSide(color: _border),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: _green.withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(9),
                                            ),
                                            child: Icon(
                                              Icons.send_rounded,
                                              color: _green,
                                              size: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          const Text(
                                            'Confirm Submission',
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
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        children: [
                                          const Text(
                                            'Are you sure you want to submit this route for review?',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: _textSecondary,
                                              height: 1.5,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 18),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: GestureDetector(
                                                  onTap:
                                                      () => Navigator.pop(
                                                        context,
                                                        false,
                                                      ),
                                                  child: Container(
                                                    height: 44,
                                                    decoration: BoxDecoration(
                                                      color: _surface,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            11,
                                                          ),
                                                      border: Border.all(
                                                        color: _border,
                                                      ),
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: const Text(
                                                      'Cancel',
                                                      style: TextStyle(
                                                        color: _textSecondary,
                                                        fontWeight:
                                                            FontWeight.w600,
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
                                                      () => Navigator.pop(
                                                        context,
                                                        true,
                                                      ),
                                                  child: Container(
                                                    height: 44,
                                                    decoration: BoxDecoration(
                                                      gradient:
                                                          const LinearGradient(
                                                            colors: [
                                                              Color(0xFF3EC97A),
                                                              Color(0xFF6DDDA0),
                                                            ],
                                                            begin:
                                                                Alignment
                                                                    .centerLeft,
                                                            end:
                                                                Alignment
                                                                    .centerRight,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            11,
                                                          ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: _green
                                                              .withOpacity(0.3),
                                                          blurRadius: 10,
                                                          offset: const Offset(
                                                            0,
                                                            3,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: const Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Icon(
                                                          Icons.send_rounded,
                                                          color: Colors.white,
                                                          size: 15,
                                                        ),
                                                        SizedBox(width: 6),
                                                        Text(
                                                          'Submit',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.w700,
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
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      );
                        if (confirm == true) {
                          onSubmit!.call();
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 17,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Submit Route',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
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
    );
  }

  // ─── Metric cell ────────────────────────────────────────────────────────────
  Widget _metricCell({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() {
    return Container(width: 1, height: 40, color: _border);
  }

  // ─── Map helpers (functions unchanged) ────────────────────────────────────
  List<Polyline> _buildPolylines() {
    List<Polyline> polylines = [];

    for (int i = 0; i < route.steps.length; i++) {
      final step = route.steps[i];
      final color = _getModeColor(step.mode);

      final startIdx = (i == 0) ? 0 : route.stepBoundaries[i - 1];
      final endIdx =
          (i < route.stepBoundaries.length)
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
          child: const Icon(Icons.location_on, color: Colors.green, size: 40),
        ),
      );
    }

    // End marker
    if (route.pathPoints.length > 1) {
      markers.add(
        Marker(
          point: route.pathPoints.last,
          child: const Icon(Icons.flag, color: Colors.red, size: 40),
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
                color: _surface,
                shape: BoxShape.circle,
                border: Border.all(color: _accent, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              width: 24,
              height: 24,
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: _accent,
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

  IconData _getModeIconData(String mode) {
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

  // _getModeIcon renamed to _getModeIconData above — kept for polylines
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
