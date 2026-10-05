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

/// One step's line as pieces between its control points (start, via
/// points, end). Editing a control point re-routes only the pieces that
/// touch it; every other piece keeps its exact geometry.
class StepGeometry {
  final List<LatLng> controls;
  final List<List<LatLng>> pieces;

  const StepGeometry._(this.controls, this.pieces);

  /// Via points derived for a step saved without control points: one about
  /// every [spacingMeters] along its line, so editing one area of an older
  /// route can't re-route the whole step.
  static const spacingMeters = 1000.0;

  /// Splits [path] at [controls] (each matched to the nearest vertex, in
  /// order). Without usable controls, derives them along the path.
  factory StepGeometry.fromPath(List<LatLng> path, List<LatLng> controls) {
    if (path.length < 2) {
      return StepGeometry._(List.of(path), [List.of(path)]);
    }
    final splitIndices = <int>[0];
    if (controls.length >= 2) {
      var from = 1;
      for (final control in controls.sublist(1, controls.length - 1)) {
        if (from >= path.length - 1) break;
        final index = _nearestIndex(path, control, from, path.length - 2);
        splitIndices.add(index);
        from = index + 1;
      }
    } else {
      var since = 0.0;
      for (var i = 1; i < path.length - 1; i++) {
        since += _distance.as(LengthUnit.Meter, path[i - 1], path[i]);
        if (since >= spacingMeters) {
          splitIndices.add(i);
          since = 0;
        }
      }
    }
    splitIndices.add(path.length - 1);

    final pieces = <List<LatLng>>[
      for (var k = 0; k < splitIndices.length - 1; k++)
        path.sublist(splitIndices[k], splitIndices[k + 1] + 1),
    ];
    final pointControls = [for (final i in splitIndices) path[i]];
    // Keep the contributor's own points where they were given.
    if (controls.length == pointControls.length) {
      return StepGeometry._(List.of(controls), pieces);
    }
    return StepGeometry._(pointControls, pieces);
  }

  List<LatLng> get path {
    final out = <LatLng>[];
    for (final piece in pieces) {
      if (out.isNotEmpty && piece.isNotEmpty && out.last == piece.first) {
        out.addAll(piece.skip(1));
      } else {
        out.addAll(piece);
      }
    }
    return out;
  }

  /// The middle of piece [k], where a handle inserts a new via point.
  LatLng pieceMidpoint(int k) {
    final piece = pieces[k];
    if (piece.length < 2) return piece.first;
    var total = 0.0;
    for (var i = 1; i < piece.length; i++) {
      total += _distance.as(LengthUnit.Meter, piece[i - 1], piece[i]);
    }
    var walked = 0.0;
    for (var i = 1; i < piece.length; i++) {
      final seg = _distance.as(LengthUnit.Meter, piece[i - 1], piece[i]);
      if (walked + seg >= total / 2 && seg > 0) {
        final t = (total / 2 - walked) / seg;
        final a = piece[i - 1], b = piece[i];
        return LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        );
      }
      walked += seg;
    }
    return piece.last;
  }

  /// Moves control [k] to [to]; re-routes the (up to two) touching pieces.
  /// The point lands where the routed line actually reaches (on the road,
  /// for vehicles), so both pieces meet there.
  Future<StepGeometry> moveControl(
    int k,
    LatLng to,
    PieceRouter route,
  ) async {
    final controls = List.of(this.controls);
    final pieces = List.of(this.pieces);
    var point = to;
    if (k > 0) {
      pieces[k - 1] = await route(controls[k - 1], to);
      point = pieces[k - 1].last;
    }
    if (k < pieces.length) {
      pieces[k] = await route(point, controls[k + 1]);
      if (k == 0) point = pieces[k].first;
    }
    controls[k] = point;
    return StepGeometry._(controls, pieces);
  }

  /// Adds a via point at [at] inside piece [k], replacing that piece with
  /// two routed through it (meeting where the first one reaches).
  Future<StepGeometry> insertControl(
    int k,
    LatLng at,
    PieceRouter route,
  ) async {
    final first = await route(this.controls[k], at);
    final point = first.last;
    final second = await route(point, this.controls[k + 1]);
    final controls = List.of(this.controls)..insert(k + 1, point);
    final pieces = List.of(this.pieces)..replaceRange(k, k + 1, [first, second]);
    return StepGeometry._(controls, pieces);
  }

  /// Removes via point [k] (never the step's start or end), joining its two
  /// pieces into one routed piece.
  Future<StepGeometry> removeControl(int k, PieceRouter route) async {
    if (k <= 0 || k >= this.controls.length - 1) return this;
    final controls = List.of(this.controls)..removeAt(k);
    final pieces = List.of(this.pieces)
      ..replaceRange(k - 1, k + 1, [
        await route(controls[k - 1], controls[k]),
      ]);
    return StepGeometry._(controls, pieces);
  }

  static const _distance = Distance();

  /// The vertex in [from]..[to] matching [p]: the earliest of those about as
  /// close as the closest, so a route that comes back along the same road
  /// isn't split on its return leg.
  static int _nearestIndex(List<LatLng> path, LatLng p, int from, int to) {
    var bestMeters = double.infinity;
    for (var i = from; i <= to; i++) {
      final m = _distance.as(LengthUnit.Meter, path[i], p);
      if (m < bestMeters) bestMeters = m;
    }
    for (var i = from; i <= to; i++) {
      if (_distance.as(LengthUnit.Meter, path[i], p) <= bestMeters + 10) {
        return i;
      }
    }
    return from;
  }
}

/// Produces the line for one piece between two control points.
typedef PieceRouter = Future<List<LatLng>> Function(LatLng from, LatLng to);

/// The route as it was before a drag edit. Steps whose control points the
/// edit didn't change keep this geometry instead of being re-routed, so
/// moving one handle can't silently move the rest of the route onto other
/// roads.
class ContributionRouteBaseline {
  final List<List<LatLng>> stepControlPoints;
  final List<LatLng> pathPoints;
  final List<int> stepBoundaries;
  final List<double?> stepOrsDistM;
  final List<double?> stepOrsDurS;

  const ContributionRouteBaseline({
    required this.stepControlPoints,
    required this.pathPoints,
    required this.stepBoundaries,
    required this.stepOrsDistM,
    required this.stepOrsDurS,
  });

  /// Step [i]'s existing path when [controls] match its old control points.
  List<LatLng>? unchangedStepPath(int i, List<LatLng> controls) {
    if (i >= stepControlPoints.length || i >= stepBoundaries.length) {
      return null;
    }
    final old = stepControlPoints[i];
    if (old.length != controls.length) return null;
    for (var k = 0; k < old.length; k++) {
      if (old[k] != controls[k]) return null;
    }
    final start = i == 0 ? 0 : stepBoundaries[i - 1];
    final end = stepBoundaries[i];
    if (start < 0 || end >= pathPoints.length || end <= start) return null;
    return pathPoints.sublist(start, end + 1);
  }
}

class ContributeRouteEditService {
  /// Routes one piece: along roads for [mode] when [snapToRoadEnabled]
  /// (straight if the routing services fail), otherwise a straight line.
  /// Vehicle pieces end where the road does, which moves an off-road tap
  /// onto the road; walking pieces keep the exact tapped points, since
  /// footpaths and terminals can be off the mapped roads.
  static PieceRouter pieceRouter({
    required String mode,
    required bool snapToRoadEnabled,
    bool? allowExpressways,
  }) {
    return (from, to) async {
      if (snapToRoadEnabled) {
        try {
          final snap = await RoutingService.snapToRoad(
            origin: from,
            destination: to,
            mode: mode,
            allowExpressways: allowExpressways,
          );
          if (snap != null && snap.polyline.length >= 2) {
            if (mode != 'Walk') return snap.polyline;
            final line = snap.polyline;
            return [
              if (line.first != from) from,
              ...line,
              if (line.last != to) to,
            ];
          }
        } catch (_) {}
      }
      return [from, to];
    };
  }

  static Future<RebuiltContributionRoute> rebuildFromWaypoints({
    required List<route_model.Step> steps,
    required List<LatLng> waypoints,
    required bool snapToRoadEnabled,
    bool? allowExpressways,
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
            allowExpressways: allowExpressways,
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
    bool? allowExpressways,
    ContributionRouteBaseline? baseline,
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
      final keptPath = baseline?.unchangedStepPath(i, stepControlPoints[i]);
      if (keptPath != null) {
        if (rebuiltPathPoints.isEmpty) {
          rebuiltPathPoints.addAll(keptPath);
        } else {
          rebuiltPathPoints.addAll(keptPath.skip(1));
        }
        rebuiltStepBoundaries.add(rebuiltPathPoints.length - 1);
        rebuiltStepOrsDistM.add(
          i < baseline!.stepOrsDistM.length ? baseline.stepOrsDistM[i] : null,
        );
        rebuiltStepOrsDurS.add(
          i < baseline.stepOrsDurS.length ? baseline.stepOrsDurS[i] : null,
        );
        continue;
      }

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
              allowExpressways: allowExpressways,
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