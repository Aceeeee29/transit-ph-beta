import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/services/route_follow_engine.dart';
import 'package:transitph_beta/services/route_follow_guidance.dart';

// Offsets in metres east (x) / north (y) of a CAMANAVA origin.
const _origin = LatLng(14.6575, 120.9839);

LatLng _at(double eastM, double northM) {
  const mPerDegLat = 111320.0;
  final mPerDegLng = mPerDegLat * math.cos(_origin.latitude * math.pi / 180);
  return LatLng(
    _origin.latitude + northM / mPerDegLat,
    _origin.longitude + eastM / mPerDegLng,
  );
}

final _t0 = DateTime(2026, 10, 1, 8);

FollowGuidance _plan(
  RouteFollowEngine engine,
  List<FollowStep> steps,
  LatLng position, {
  double speedMps = 1.2,
  Duration after = Duration.zero,
}) {
  final at = _t0.add(after);
  final snapshot = engine.update(position, at: at);
  return FollowGuidancePlanner.plan(
    engine: engine,
    snapshot: snapshot,
    steps: steps,
    speedMps: speedMps,
    now: at,
  );
}

void main() {
  // 2 km due north in 100 m vertices: a jeepney step then a walk step.
  final path = [for (var i = 0; i <= 20; i++) _at(0, i * 100.0)];
  const jeepThenWalk = [
    FollowStep(mode: 'Jeepney', startIndex: 0, endIndex: 15),
    FollowStep(mode: 'Walk', startIndex: 15, endIndex: 20),
  ];

  group('approach (not on the route yet)', () {
    test('a flexible route passing nearby: board at the nearest point', () {
      final engine = RouteFollowEngine(path);
      final g = _plan(engine, jeepThenWalk, _at(300, 600));

      expect(g.kind, FollowGuidanceKind.approach);
      expect(g.mode, 'Jeepney');
      expect(g.isRouteStart, isFalse);
      expect(g.targetAlongMeters, closeTo(600, 2));
      expect(g.distanceMeters, closeTo(300, 3));
    });

    test('nothing within 500 m: head to the official start', () {
      final engine = RouteFollowEngine(path);
      final g = _plan(engine, jeepThenWalk, _at(900, 600));

      expect(g.kind, FollowGuidanceKind.approach);
      expect(g.isRouteStart, isTrue);
      expect(g.target, path.first);
    });

    test('never suggests boarding in the last 200 m', () {
      final engine = RouteFollowEngine(path);
      final g = _plan(engine, jeepThenWalk, _at(150, 1950));

      expect(g.targetAlongMeters, lessThanOrEqualTo(1800 + 1));
    });

    test('trains are boarded at the station, not mid-line', () {
      const trainSteps = [
        FollowStep(mode: 'Walk', startIndex: 0, endIndex: 5),
        FollowStep(mode: 'Train', startIndex: 5, endIndex: 20),
      ];
      final engine = RouteFollowEngine(path);
      // Beside the line at 700 m: the nearest boardable point is the
      // station at 500 m, not the track right next to you.
      final g = _plan(engine, trainSteps, _at(200, 700));

      expect(g.boardsAtStation, isTrue);
      expect(g.target, path[5]);
    });

    test('joining the route ends the approach', () {
      final engine = RouteFollowEngine(path);
      _plan(engine, jeepThenWalk, _at(300, 600));
      final g = _plan(engine, jeepThenWalk, _at(5, 600));
      expect(g.kind, FollowGuidanceKind.none);
    });
  });

  group('off route after starting', () {
    RouteFollowEngine started() {
      final engine = RouteFollowEngine(path);
      _plan(engine, jeepThenWalk, _at(0, 0));
      _plan(engine, jeepThenWalk, _at(0, 300));
      return engine;
    }

    List<FollowGuidance> leave(
      RouteFollowEngine engine,
      LatLng to, {
      double speedMps = 1.2,
      int seconds = 12,
    }) => [
      for (var s = 1; s <= seconds; s++)
        _plan(
          engine,
          jeepThenWalk,
          to,
          speedMps: speedMps,
          after: Duration(seconds: s),
        ),
    ];

    test('no reroute for the first few seconds off the route', () {
      final engine = started();
      final g = leave(engine, _at(120, 400), seconds: 5).last;
      expect(g.kind, FollowGuidanceKind.none);
    });

    test('on foot: rejoin at the nearest point ahead', () {
      final engine = started();
      final g = leave(engine, _at(120, 400)).last;

      expect(g.kind, FollowGuidanceKind.rejoin);
      expect(g.targetAlongMeters, closeTo(400, 2));
    });

    test('never rejoins behind current progress', () {
      final engine = started();
      final g = leave(engine, _at(120, 150)).last;

      expect(g.kind, FollowGuidanceKind.rejoin);
      expect(g.targetAlongMeters, greaterThanOrEqualTo(300 - 1));
    });

    test('at vehicle speed: a likely detour, not walking directions', () {
      final engine = started();
      final g = leave(engine, _at(120, 400), speedMps: 8).last;

      expect(g.kind, FollowGuidanceKind.vehicleDetour);
      expect(g.target, isNull);
    });
  });

  test('the expected join point decides between two passes of a loop', () {
    // Out along x = 0, back along x = 30.
    final loop = [
      _at(0, 0),
      _at(0, 800),
      _at(30, 800),
      _at(30, 0),
    ];
    final engine = RouteFollowEngine(loop);
    engine.expectedJoinMeters = 830 + 400; // the return leg at y = 400
    final s = engine.update(_at(15, 400), at: _t0);
    expect(s.progressMeters, closeTo(1230, 3));
  });
}
