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

  static Future<RebuiltContributionRoute> rebuildFromStepControlPoints({
    required List<route_model.Step> steps,
    required List<List<LatLng>> stepControlPoints,
    required bool snapToRoadEnabled,
  }) async {
    if (steps.isEmpty || stepControlPoints.isEmpty) {
      return const RebuiltContributionRoute(
        pathPoints: [],
        stepBoundaries: [],
        stepOrsDistM: [],
        stepOrsDurS: [],
      );
    }

    final usableStepCount =
        steps.length < stepControlPoints.length ? steps.length : stepControlPoints.length;

    final rebuiltPathPoints = <LatLng>[];
    final rebuiltStepBoundaries = <int>[];
    final rebuiltStepOrsDistM = <double?>[];
    final rebuiltStepOrsDurS = <double?>[];

    for (int i = 0; i < usableStepCount; i++) {
      final step = steps[i];
      final controls = _sanitizeStepControlPoints(stepControlPoints[i]);
      if (controls.length < 2) {
        rebuiltStepOrsDistM.add(null);
        rebuiltStepOrsDurS.add(null);
        if (rebuiltPathPoints.isNotEmpty) {
          rebuiltStepBoundaries.add(rebuiltPathPoints.length - 1);
        } else {
          rebuiltStepBoundaries.add(0);
        }
        continue;
      }

      final stepPath = <LatLng>[];
      double? stepOrsDistM = 0.0;
      double? stepOrsDurS = 0.0;

      for (int j = 0; j < controls.length - 1; j++) {
        final origin = controls[j];
        final destination = controls[j + 1];

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

        if (stepPath.isEmpty) {
          stepPath.addAll(segment);
        } else {
          stepPath.addAll(segment.skip(1));
        }

        if (orsDistM == null || orsDurS == null) {
          stepOrsDistM = null;
          stepOrsDurS = null;
        } else if (stepOrsDistM != null && stepOrsDurS != null) {
          stepOrsDistM += orsDistM;
          stepOrsDurS += orsDurS;
        }
      }

      if (stepPath.length < 2) {
        continue;
      }

      if (rebuiltPathPoints.isEmpty) {
        rebuiltPathPoints.addAll(stepPath);
      } else {
        rebuiltPathPoints.addAll(stepPath.skip(1));
      }

      rebuiltStepBoundaries.add(rebuiltPathPoints.length - 1);
      rebuiltStepOrsDistM.add(stepOrsDistM);
      rebuiltStepOrsDurS.add(stepOrsDurS);
    }

    return RebuiltContributionRoute(
      pathPoints: rebuiltPathPoints,
      stepBoundaries: rebuiltStepBoundaries,
      stepOrsDistM: rebuiltStepOrsDistM,
      stepOrsDurS: rebuiltStepOrsDurS,
    );
  }

  static List<LatLng> _sanitizeStepControlPoints(List<LatLng> controls) {
    if (controls.isEmpty) return const [];

    final cleaned = <LatLng>[];
    for (final point in controls) {
      if (cleaned.isEmpty || !_isSamePoint(cleaned.last, point)) {
        cleaned.add(point);
      }
    }

    if (cleaned.length == 1) {
      cleaned.add(cleaned.first);
    }

    return cleaned;
  }

  static bool _isSamePoint(LatLng a, LatLng b) {
    return a.latitude == b.latitude && a.longitude == b.longitude;
  }
}