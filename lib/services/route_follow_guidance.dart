import 'package:latlong2/latlong.dart';

import '../data/camanava_places.dart';
import 'route_follow_engine.dart';

/// A designated stop on a followed step.
class FollowStop {
  final LatLng point;
  final String name;
  final bool pickup;
  final bool dropoff;

  const FollowStop({
    required this.point,
    required this.name,
    this.pickup = true,
    this.dropoff = true,
  });
}

/// One step of a followed route, as a range of path indices.
class FollowStep {
  /// Null when the route carries no step data.
  final String? mode;
  final int startIndex;
  final int endIndex;

  /// Passengers board/get off only at [stops] (or, for a train step with
  /// none listed, its two ends). Otherwise pickup is flexible anywhere
  /// along the step's line.
  final bool designatedStops;
  final List<FollowStop> stops;

  const FollowStep({
    required this.mode,
    required this.startIndex,
    required this.endIndex,
    bool? designatedStops,
    this.stops = const [],
  }) : designatedStops = designatedStops ?? mode == 'Train';

  bool get isWalk => mode == 'Walk';
  bool get isTrain => mode == 'Train';
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

  /// [target] is a designated stop (or station) rather than any point on
  /// the line.
  final bool atDesignatedStop;

  /// The designated stop's name, when it has one.
  final String? stopName;
  final bool isRouteStart;

  /// A recognisable place near [target], if any.
  final String? placeName;

  const FollowGuidance({
    required this.kind,
    this.target,
    this.targetAlongMeters = 0,
    this.distanceMeters = 0,
    this.mode,
    this.atDesignatedStop = false,
    this.stopName,
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
    // Boarding this close to the end isn't worth suggesting.
    final latestJoin = engine.totalMeters - _minRideAfterJoinMeters;
    _Target? best;
    for (final step in steps) {
      final target = _boardingPoint(engine, position, step, latestJoin);
      if (target == null) continue;
      if (target.match.distance > approachRadiusMeters) continue;
      if (best == null || target.match.distance < best.match.distance) {
        best = target;
      }
    }

    if (best == null) {
      final start = engine.path.first;
      return _guidance(
        FollowGuidanceKind.approach,
        _Target(
          RouteMatch(
            segment: 0,
            distance: _distance.as(LengthUnit.Meter, position, start),
            along: 0,
            point: start,
          ),
          steps.first,
        ),
      );
    }
    return _guidance(FollowGuidanceKind.approach, best);
  }

  /// Where [step] can be boarded closest to [position], no later than
  /// [latestJoin] along the route: its nearest pickup stop when it has
  /// designated stops, otherwise the nearest point on its line.
  static _Target? _boardingPoint(
    RouteFollowEngine engine,
    LatLng position,
    FollowStep step,
    double latestJoin,
  ) {
    final from = engine.alongAt(step.startIndex);
    if (from > latestJoin) return null;
    if (step.designatedStops) {
      _Target? best;
      for (final stop in _stopsOf(engine, step, pickup: true)) {
        if (stop.match.along > latestJoin) continue;
        final distance = _distance.as(LengthUnit.Meter, position, stop.point);
        if (best == null || distance < best.match.distance) {
          best = stop.withDistance(distance);
        }
      }
      return best;
    }
    final to = engine.alongAt(step.endIndex);
    final match = engine.nearestInRange(
      position,
      from,
      to < latestJoin ? to : latestJoin,
    );
    return match == null ? null : _Target(match, step);
  }

  /// Never behind current progress: the next stop ahead on a step with
  /// designated stops, otherwise the nearest point ahead on the current
  /// step, or anywhere ahead if that step is out of reach.
  static FollowGuidance _rejoin(
    RouteFollowEngine engine,
    RouteFollowSnapshot snapshot,
    LatLng position,
    List<FollowStep> steps,
  ) {
    final progress = snapshot.progressMeters;
    final current = _stepAtSegment(steps, snapshot.progressSegment);

    _Target? target;
    if (current.designatedStops) {
      // The vehicle only stops at its stops, so never send the traveler to
      // an arbitrary point on the line: the next stop ahead, however far,
      // else the step's end.
      final ahead = _stopsOf(
        engine,
        current,
        pickup: true,
      ).where((stop) => stop.match.along > progress);
      final stop =
          ahead.isNotEmpty
              ? ahead.first
              : _Target(
                RouteMatch(
                  segment: current.endIndex,
                  distance: 0,
                  along: engine.alongAt(current.endIndex),
                  point: engine.path[current.endIndex],
                ),
                current,
                isStop: true,
              );
      return _guidance(
        FollowGuidanceKind.rejoin,
        stop.withDistance(_distance.as(LengthUnit.Meter, position, stop.point)),
      );
    } else {
      final match = engine.nearestInRange(
        position,
        progress,
        engine.alongAt(current.endIndex),
      );
      if (match != null) target = _Target(match, current);
    }
    if (target == null || target.match.distance > approachRadiusMeters) {
      final ahead = engine.nearestInRange(position, progress, engine.totalMeters);
      if (ahead != null &&
          (target == null || ahead.distance < target.match.distance)) {
        target = _Target(ahead, _stepAtSegment(steps, ahead.segment));
      }
    }
    if (target == null) return FollowGuidance.none;
    return _guidance(FollowGuidanceKind.rejoin, target);
  }

  /// The pickup (or drop-off) stops of a designated [step] in order along
  /// the route; a train step without listed stations uses its two ends.
  static List<_Target> _stopsOf(
    RouteFollowEngine engine,
    FollowStep step, {
    required bool pickup,
  }) {
    final from = engine.alongAt(step.startIndex);
    final to = engine.alongAt(step.endIndex);
    if (step.stops.isEmpty) {
      return [
        for (final index in [step.startIndex, step.endIndex])
          _Target(
            RouteMatch(
              segment: index,
              distance: 0,
              along: engine.alongAt(index),
              point: engine.path[index],
            ),
            step,
            isStop: true,
          ),
      ];
    }
    final stops = <_Target>[];
    for (final stop in step.stops) {
      if (pickup ? !stop.pickup : !stop.dropoff) continue;
      final onLine = engine.nearestInRange(stop.point, from, to);
      if (onLine == null) continue;
      stops.add(
        _Target(
          RouteMatch(
            segment: onLine.segment,
            distance: 0,
            along: onLine.along,
            point: stop.point,
          ),
          step,
          isStop: true,
          stopName: stop.name,
        ),
      );
    }
    stops.sort((a, b) => a.match.along.compareTo(b.match.along));
    return stops;
  }

  static FollowGuidance _guidance(FollowGuidanceKind kind, _Target target) {
    final match = target.match;
    return FollowGuidance(
      kind: kind,
      target: match.point,
      targetAlongMeters: match.along,
      distanceMeters: match.distance,
      mode: target.step.mode,
      atDesignatedStop: target.isStop,
      stopName: target.stopName,
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

/// A candidate boarding/rejoin point and the step it belongs to.
class _Target {
  final RouteMatch match;
  final FollowStep step;
  final bool isStop;
  final String? stopName;

  const _Target(this.match, this.step, {this.isStop = false, this.stopName});

  LatLng get point => match.point;

  _Target withDistance(double distance) => _Target(
    RouteMatch(
      segment: match.segment,
      distance: distance,
      along: match.along,
      point: match.point,
    ),
    step,
    isStop: isStop,
    stopName: stopName,
  );
}
