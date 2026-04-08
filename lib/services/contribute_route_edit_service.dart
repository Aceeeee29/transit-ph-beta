import 'package:latlong2/latlong.dart';

import '../models/route.dart' as route_model;
import 'routing_service.dart';

class RebuiltContributionRoute {
  final List<LatLng> pathPoints;
  final List<int> stepBoundaries;
  final List<double?> stepOrsDistM;
  final List<double?> stepOrsDurS;

  const RebuiltContributionRoute({
    required this.pathPoints,
    required this.stepBoundaries,
    required this.stepOrsDistM,
    required this.stepOrsDurS,
  });
}

class ContributeRouteEditService {
  static Future<RebuiltContributionRoute> rebuildFromWaypoints({
    required List<route_model.Step> steps,
    required List<LatLng> waypoints,
    required bool snapToRoadEnabled,
  }) async {
    if (steps.isEmpty || waypoints.length < 2) {
      return const RebuiltContributionRoute(
        pathPoints: [],
        stepBoundaries: [],
        stepOrsDistM: [],
        stepOrsDurS: [],
      );
    }

    final usableStepCount =
        steps.length < (waypoints.length - 1) ? steps.length : (waypoints.length - 1);

    final rebuiltPathPoints = <LatLng>[];
    final rebuiltStepBoundaries = <int>[];
    final rebuiltStepOrsDistM = <double?>[];
    final rebuiltStepOrsDurS = <double?>[];

    for (int i = 0; i < usableStepCount; i++) {
      final step = steps[i];
      final origin = waypoints[i];
      final destination = waypoints[i + 1];

      List<LatLng> segment = [origin, destination];
      double? orsDistM;
      double? orsDurS;

      if (snapToRoadEnabled) {
        try {
          final snap = await RoutingService.snapToRoad(
            origin: origin,
            destination: destination,
            mode: step.mode,
          );
          if (snap != null && snap.polyline.length >= 2) {
            segment = snap.polyline;
            orsDistM = snap.distanceMeters;
            orsDurS = snap.durationSeconds;
          }
        } catch (_) {
          // Keep fallback straight segment when snap API fails.
        }
      }

      if (rebuiltPathPoints.isEmpty) {
        rebuiltPathPoints.addAll(segment);
      } else {
        rebuiltPathPoints.addAll(segment.skip(1));
      }

      rebuiltStepBoundaries.add(rebuiltPathPoints.length - 1);
      rebuiltStepOrsDistM.add(orsDistM);
      rebuiltStepOrsDurS.add(orsDurS);
    }

    return RebuiltContributionRoute(
      pathPoints: rebuiltPathPoints,
      stepBoundaries: rebuiltStepBoundaries,
      stepOrsDistM: rebuiltStepOrsDistM,
      stepOrsDurS: rebuiltStepOrsDurS,
    );
  }
}