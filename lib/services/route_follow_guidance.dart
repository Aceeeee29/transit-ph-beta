import 'package:latlong2/latlong.dart';

import '../data/camanava_places.dart';
import 'route_follow_engine.dart';

/// One step of a followed route, as a range of path indices.
class FollowStep {
  /// Null when the route carries no step data.
  final String? mode;
  final int startIndex;
  final int endIndex;

  const FollowStep({
    required this.mode,
    required this.startIndex,
    required this.endIndex,
  });

  bool get isWalk => mode == 'Walk';

  /// Trains can only be boarded at stations. Until routes carry their own
  /// stops, a train step's stations are its two ends; every other step is
  /// treated as flexible pickup anywhere along its line.
  bool get boardsOnlyAtStations => mode == 'Train';
}

enum FollowGuidanceKind {
  none,

  /// Not on the route yet: head to the boarding point.
  approach,

  /// Off the route on foot: head back to the rejoin point.
  rejoin,

  /// Off the route at vehicle speed: the vehicle is probably detouring, so
  /// no walking directions.
  vehicleDetour,
}

class FollowGuidance {
  final FollowGuidanceKind kind;
  final LatLng? target;

  /// Distance along the route of [target].
  final double targetAlongMeters;

  /// Straight-line distance from the traveler to [target].
  final double distanceMeters;

  /// Mode of the step at [target].
  final String? mode;
  final bool boardsAtStation;
  final bool isRouteStart;

  /// A recognisable place near [target], if any.
  final String? placeName;

  const FollowGuidance({
    required this.kind,
    this.target,
    this.targetAlongMeters = 0,
    this.distanceMeters = 0,
    this.mode,
    this.boardsAtStation = false,
    this.isRouteStart = false,
    this.placeName,
  });

  static const none = FollowGuidance(kind: FollowGuidanceKind.none);
}

/// Decides what to tell a traveler who isn't on the route they're following.
class FollowGuidancePlanner {
  /// A boarding point this close counts as "the route passes near you";
  /// otherwise the traveler is sent to the route's official start.
  static const approachRadiusMeters = 500.0;

  /// Off-route for at least this long before rerouting, so a brief GPS
  /// wander doesn't trigger it.
  static const rejoinAfter = Duration(seconds: 8);

  /// About 15 km/h: faster than this, the traveler is on a vehicle.
  static const vehicleSpeedMps = 4.2;

  /// Boarding this close to the end isn't worth suggesting.
  static const _minRideAfterJoinMeters = 200.0;

  static const _distance = Distance();

  static FollowGuidance plan({
    required RouteFollowEngine engine,
    required RouteFollowSnapshot snapshot,
    required List<FollowStep> steps,
    required double speedMps,
    DateTime? now,
  }) {
    if (snapshot.hasArrived) return FollowGuidance.none;
    final usableSteps = _normalizeSteps(steps, engine.path.length);
    final position = snapshot.rawPosition;

    if (!snapshot.hasProgress) {
      return _approach(engine, position, usableSteps);
    }
    if (snapshot.status != RouteFollowStatus.awayFromRoute) {
      return FollowGuidance.none;
    }
    final awayFor = (now ?? DateTime.now()).difference(snapshot.statusSince);
    if (awayFor < rejoinAfter) return FollowGuidance.none;
    if (speedMps >= vehicleSpeedMps) {
      return const FollowGuidance(kind: FollowGuidanceKind.vehicleDetour);
    }
    return _rejoin(engine, snapshot, position, usableSteps);
  }

  static FollowGuidance _approach(
    RouteFollowEngine engine,
    LatLng position,
    List<FollowStep> steps,
  ) {
    RouteMatch? best;
    FollowStep? bestStep;
    // Boarding this close to the end isn't worth suggesting.
    final latestJoin = engine.totalMeters - _minRideAfterJoinMeters;
    for (final step in steps) {
      final match = _boardingPoint(engine, position, step, latestJoin);
      if (match == null) continue;
      if (match.distance > approachRadiusMeters) continue;
      if (best == null || match.distance < best.distance) {
        best = match;
        bestStep = step;
      }
    }

    if (best == null || bestStep == null) {
      final start = engine.path.first;
      return _guidance(
        FollowGuidanceKind.approach,
        RouteMatch(
          segment: 0,
          distance: _distance.as(LengthUnit.Meter, position, start),
          along: 0,
          point: start,
        ),
        steps.first,
      );
    }
    return _guidance(FollowGuidanceKind.approach, best, bestStep);
  }

  /// Where [step] can be boarded closest to [position], no later than
  /// [latestJoin] along the route: its start station for trains, otherwise
  /// the nearest point on its line.
  static RouteMatch? _boardingPoint(
    RouteFollowEngine engine,
    LatLng position,
    FollowStep step,
    double latestJoin,
  ) {
    final from = engine.alongAt(step.startIndex);
    if (from > latestJoin) return null;
    if (step.boardsOnlyAtStations) {
      final station = engine.path[step.startIndex];
      return RouteMatch(
        segment: step.startIndex,
        distance: _distance.as(LengthUnit.Meter, position, station),
        along: from,
        point: station,
      );
    }
    final to = engine.alongAt(step.endIndex);
    return engine.nearestInRange(
      position,
      from,
      to < latestJoin ? to : latestJoin,
    );
  }

  /// Never behind current progress: the next station for trains, otherwise
  /// the nearest point ahead on the current step, or anywhere ahead if that
  /// step is out of reach.
  static FollowGuidance _rejoin(
    RouteFollowEngine engine,
    RouteFollowSnapshot snapshot,
    LatLng position,
    List<FollowStep> steps,
  ) {
    final progress = snapshot.progressMeters;
    final current = _stepAtSegment(steps, snapshot.progressSegment);

    RouteMatch? match;
    if (current.boardsOnlyAtStations) {
      final station = engine.path[current.endIndex];
      match = RouteMatch(
        segment: current.endIndex,
        distance: _distance.as(LengthUnit.Meter, position, station),
        along: engine.alongAt(current.endIndex),
        point: station,
      );
    } else {
      match = engine.nearestInRange(
        position,
        progress,
        engine.alongAt(current.endIndex),
      );
    }
    if (match == null || match.distance > approachRadiusMeters) {
      final ahead = engine.nearestInRange(position, progress, engine.totalMeters);
      if (ahead != null && (match == null || ahead.distance < match.distance)) {
        match = ahead;
      }
    }
    if (match == null) return FollowGuidance.none;
    return _guidance(
      FollowGuidanceKind.rejoin,
      match,
      _stepAtSegment(steps, match.segment),
    );
  }

  static FollowGuidance _guidance(
    FollowGuidanceKind kind,
    RouteMatch match,
    FollowStep step,
  ) {
    return FollowGuidance(
      kind: kind,
      target: match.point,
      targetAlongMeters: match.along,
      distanceMeters: match.distance,
      mode: step.mode,
      boardsAtStation: step.boardsOnlyAtStations,
      isRouteStart: match.along <= 1,
      placeName: nearestCamanavaPlaceName(match.point),
    );
  }

  static FollowStep _stepAtSegment(List<FollowStep> steps, int segment) {
    for (final step in steps) {
      if (segment >= step.startIndex && segment < step.endIndex) return step;
    }
    return segment < steps.first.startIndex ? steps.first : steps.last;
  }

  /// Valid, in-bounds steps; one mode-less step over the whole path when
  /// none are usable.
  static List<FollowStep> _normalizeSteps(List<FollowStep> steps, int length) {
    final last = length - 1;
    final valid = [
      for (final s in steps)
        if (s.startIndex >= 0 && s.endIndex <= last && s.endIndex > s.startIndex)
          s,
    ];
    return valid.isNotEmpty
        ? valid
        : [FollowStep(mode: null, startIndex: 0, endIndex: last)];
  }
}
