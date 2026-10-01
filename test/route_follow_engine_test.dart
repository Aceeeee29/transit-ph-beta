import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/services/route_follow_engine.dart';

// Monumento-ish origin; offsets are in metres east (x) / north (y).
const _origin = LatLng(14.6575, 120.9839);

LatLng _at(double eastM, double northM) {
  const mPerDegLat = 111320.0;
  final mPerDegLng = mPerDegLat * math.cos(_origin.latitude * math.pi / 180);
  return LatLng(
    _origin.latitude + northM / mPerDegLat,
    _origin.longitude + eastM / mPerDegLng,
  );
}

void main() {
  group('RouteFollowEngine', () {
    // 1 km straight north, with only its two end vertices — progress must
    // still be smooth along a sparse segment.
    final straight = [_at(0, 0), _at(0, 1000)];

    test('projects onto the segment, not the nearest vertex', () {
      final engine = RouteFollowEngine(straight);
      final s = engine.update(_at(12, 400));

      expect(s.status, RouteFollowStatus.onRoute);
      expect(s.progressMeters, closeTo(400, 2));
      expect(s.distanceFromRouteMeters, closeTo(12, 1));
      // Drawn on the line, not 12 m beside it.
      expect(s.displayPosition.longitude, closeTo(_origin.longitude, 1e-6));
    });

    test('progress never moves backwards on GPS jitter', () {
      final engine = RouteFollowEngine(straight);
      engine.update(_at(0, 300));
      final s = engine.update(_at(5, 285));
      expect(s.progressMeters, closeTo(300, 2));
    });

    test('far from the route: no progress, away after a few fixes', () {
      final engine = RouteFollowEngine(straight);
      for (var i = 0; i < 3; i++) {
        final s = engine.update(_at(800, 500));
        expect(s.hasProgress, isFalse);
        expect(s.status, RouteFollowStatus.awayFromRoute);
        expect(s.displayPosition, _at(800, 500));
      }
    });

    test('one stray fix does not flip the state', () {
      final engine = RouteFollowEngine(straight);
      engine.update(_at(0, 100));
      final stray = engine.update(_at(150, 120));
      expect(stray.status, RouteFollowStatus.onRoute);
      expect(stray.progressMeters, closeTo(100, 2));

      engine.update(_at(150, 140));
      final away = engine.update(_at(150, 160));
      expect(away.status, RouteFollowStatus.awayFromRoute);
      expect(away.displayPosition, _at(150, 160));
    });

    test('arrives near the end of the route', () {
      final engine = RouteFollowEngine(straight);
      engine.update(_at(0, 500));
      engine.update(_at(0, 900));
      final s = engine.update(_at(3, 990));
      expect(s.hasArrived, isTrue);
      expect(s.remainingMeters, 0);
    });

    // Out along x = 0, back along x = 25 (opposite side of the road), ending
    // where it started — like a jeepney loop.
    final loop = [
      _at(0, 0),
      _at(0, 400),
      _at(0, 800),
      _at(25, 800),
      _at(25, 400),
      _at(25, 0),
      _at(0, 0),
    ];

    test('loop route: starting at the shared start/end is not arrival', () {
      final engine = RouteFollowEngine(loop);
      final s = engine.update(_at(2, 5));
      expect(s.hasArrived, isFalse);
      expect(s.progressMeters, lessThan(50));
    });

    test('loop route: outbound fixes stay on the outbound leg', () {
      final engine = RouteFollowEngine(loop);
      engine.update(_at(2, 5));
      // Halfway between the two legs' lines, but a little closer to the
      // return leg: a global nearest search would jump to it.
      final s = engine.update(_at(14, 300));
      expect(s.progressMeters, closeTo(300, 5));
    });

    test('loop route: arrives only after coming back', () {
      final engine = RouteFollowEngine(loop);
      engine.update(_at(0, 0));
      for (final north in [200.0, 400.0, 600.0, 800.0]) {
        expect(engine.update(_at(0, north)).hasArrived, isFalse);
      }
      for (final north in [600.0, 400.0, 200.0, 20.0]) {
        expect(engine.update(_at(25, north)).hasArrived, isFalse);
      }
      expect(engine.update(_at(5, 0)).hasArrived, isTrue);
    });

    test('joining mid-route after starting away from it', () {
      final engine = RouteFollowEngine(straight);
      engine.update(_at(300, 600));
      final s = engine.update(_at(10, 600));
      expect(s.hasProgress, isTrue);
      expect(s.progressMeters, closeTo(600, 2));
    });

    test('after a GPS gap, progress can catch up beyond the usual window', () {
      final long = [_at(0, 0), _at(0, 3000)];
      final engine = RouteFollowEngine(long);
      final t0 = DateTime(2026, 10, 1, 8);
      engine.update(_at(0, 100), at: t0);
      final s = engine.update(
        _at(0, 1500),
        at: t0.add(const Duration(seconds: 90)),
      );
      expect(s.progressMeters, closeTo(1500, 2));
    });
  });
}
