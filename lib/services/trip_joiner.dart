import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/ors_route_result.dart';
import '../models/route.dart' as route_model;
import 'fare_matrix.dart';
import 'follow_legs.dart';

/// One trip out of two: the way to a rider route's start (generated), then
/// the rider route itself, so it can be followed in one go ("VGC → Monumento
/// + Monumento → STI").
class TripJoiner {
  TripJoiner._();

  /// [toStart] followed by [route], whose line [routePath] is split into its
  /// steps by [stepRanges] (path indices, as the route view draws them).
  static OrsRouteResult join({
    required OrsRouteResult toStart,
    required route_model.Route route,
    required List<LatLng> routePath,
    required List<({int start, int end})> stepRanges,
  }) {
    final offset = toStart.polyline.length;
    final polyline = [...toStart.polyline, ...routePath];
    final label = '${route.startLocation} → ${route.endLocation}';
    final routeSteps = <OrsStep>[];
    for (var i = 0; i < stepRanges.length; i++) {
      final range = stepRanges[i];
      final step = i < route.steps.length ? route.steps[i] : null;
      final mode = step?.mode ?? 'Jeepney';
      final meters = _length(
        routePath.sublist(
          range.start,
          math.min(range.end + 1, routePath.length),
        ),
      );
      final note = step?.instruction.trim() ?? '';
      routeSteps.add(
        OrsStep(
          instruction:
              mode == 'Walk'
                  ? 'Walk along the community route $label'
                      '${note.isEmpty ? '' : ' — "$note"'}'
                  : 'Ride $mode along the community route $label'
                      '${note.isEmpty ? '' : ' — "$note"'}',
          distanceMeters: meters,
          durationSeconds: meters / 1000 / _speedKmh(mode) * 3600,
          suggestedMode: mode,
          estimatedFare:
              mode == 'Walk'
                  ? 0
                  : step?.actualFare ?? PhFareCalculator.compute(mode, meters),
          wayPointStart: offset + range.start,
          wayPointEnd: offset + range.end,
          isCommunity: true,
          fromName: FollowLegs.riderStepEnds(route, i).from,
          toName: FollowLegs.riderStepEnds(route, i).to,
        ),
      );
    }

    final routeMeters = routeSteps.fold(0.0, (s, e) => s + e.distanceMeters);
    final routeSeconds = routeSteps.fold(0.0, (s, e) => s + e.durationSeconds);
    final routeFare = routeSteps.fold(0.0, (s, e) => s + e.estimatedFare);
    return OrsRouteResult(
      distanceMeters: toStart.distanceMeters + routeMeters,
      // Plus a few minutes to change rides.
      durationSeconds: toStart.durationSeconds + routeSeconds + 180,
      polyline: polyline,
      steps: [
        // The way there ends at the rider route's start.
        for (var i = 0; i < toStart.steps.length; i++)
          i == toStart.steps.length - 1 && toStart.steps[i].toName == null
              ? _endingAt(toStart.steps[i], route.startLocation)
              : toStart.steps[i],
        ...routeSteps,
      ],
      bbox: _bbox(polyline),
      estimatedFarePhp: toStart.baseFarePhp + routeFare,
    );
  }

  static OrsStep _endingAt(OrsStep step, String toName) => OrsStep(
    instruction: step.instruction,
    distanceMeters: step.distanceMeters,
    durationSeconds: step.durationSeconds,
    suggestedMode: step.suggestedMode,
    estimatedFare: step.estimatedFare,
    wayPointStart: step.wayPointStart,
    wayPointEnd: step.wayPointEnd,
    isCommunity: step.isCommunity,
    fromName: step.fromName,
    toName: toName,
    isEstimatedPath: step.isEstimatedPath,
  );

  /// "VGC Terminal → Monumento + Monumento → STI Caloocan".
  static String title({
    required String firstFrom,
    required route_model.Route route,
  }) =>
      '$firstFrom → ${route.startLocation} + '
      '${route.startLocation} → ${route.endLocation}';

  static double _speedKmh(String mode) => switch (mode) {
    'Walk' => 5,
    'Tricycle' => 12,
    'Jeepney' => 17,
    'Ferry' => 18,
    'Bus' => 26,
    'FX/Van' => 28,
    'Train' => 40,
    _ => 17,
  };

  static double _length(List<LatLng> path) {
    const d = Distance();
    var total = 0.0;
    for (var i = 0; i < path.length - 1; i++) {
      total += d.as(LengthUnit.Meter, path[i], path[i + 1]);
    }
    return total;
  }

  static List<double> _bbox(List<LatLng> points) {
    if (points.isEmpty) return const [];
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    return [
      lngs.reduce(math.min),
      lats.reduce(math.min),
      lngs.reduce(math.max),
      lats.reduce(math.max),
    ];
  }
}
