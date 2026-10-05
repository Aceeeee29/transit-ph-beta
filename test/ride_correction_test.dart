import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/models/ors_route_result.dart';
import 'package:transitph_beta/services/active_navigation_service.dart';
import 'package:transitph_beta/services/ride_correction.dart';

const _origin = LatLng(14.6575, 120.9839);

LatLng _at(double eastM, double northM) {
  const mPerDegLat = 111320.0;
  final mPerDegLng = mPerDegLat * math.cos(_origin.latitude * math.pi / 180);
  return LatLng(
    _origin.latitude + northM / mPerDegLat,
    _origin.longitude + eastM / mPerDegLng,
  );
}

/// 2 km north in 100 m vertices.
final _path = [for (var i = 0; i <= 20; i++) _at(0, i * 100.0)];

Future<List<LatLng>?> _noSnap(List<LatLng> points) async => null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RideCorrection.splice', () {
    test('replaces only the deviated stretch and shifts boundaries', () async {
      // Left at 600 m, rejoined at 1000 m, riding 150 m east of the line.
      final ride = [_at(0, 600), _at(150, 700), _at(150, 900), _at(0, 1000)];
      final result = await RideCorrection.splice(
        path: _path,
        stepBoundaries: const [5, 15, 20],
        deviations: [
          RideDeviation(
            fromMeters: 600,
            toMeters: 1000,
            points: ride,
            lengthMeters: 700,
          ),
        ],
        snap: _noSnap,
      );

      // Before the stretch: untouched.
      expect(result.path.sublist(0, 6), _path.sublist(0, 6));
      // The ride is in the line.
      expect(result.path, contains(_at(150, 700)));
      expect(result.path, isNot(contains(_path[8])));
      // After the stretch: the original line again, ending at the end.
      expect(result.path.last, _path.last);
      expect(result.boundaries.first, 5);
      expect(result.boundaries.last, result.path.length - 1);
      expect(result.path[result.boundaries[1]], _path[15]);
      expect(result.changed, {1});
    });

    test('a ride that never rejoined replaces the rest of the route', () async {
      final ride = [_at(0, 1200), _at(200, 1400), _at(400, 1500)];
      final result = await RideCorrection.splice(
        path: _path,
        stepBoundaries: const [20],
        deviations: [
          RideDeviation(
            fromMeters: 1200,
            toMeters: null,
            points: ride,
            lengthMeters: 600,
          ),
        ],
        snap: _noSnap,
      );

      expect(result.path.last, _at(400, 1500));
      expect(result.boundaries.single, result.path.length - 1);
    });
  });

  group('deviation tracking while following', () {
    final navigation = ActiveNavigationService.instance;
    final route = OrsRouteResult(
      distanceMeters: 2000,
      durationSeconds: 600,
      polyline: _path,
      steps: const [],
      bbox: const [],
    );

    Position fix(LatLng p, DateTime t, double speed) => Position(
      latitude: p.latitude,
      longitude: p.longitude,
      timestamp: t,
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: 0,
    );

    /// Rides north to 500 m, leaves 150 m east for 500 m, comes back at
    /// 1100 m and continues; one fix per [stepM] metres at [speed].
    List<RideDeviation> ride(double speed) {
      navigation.start(
        FollowTarget.generated(
          route,
          originName: 'A',
          destinationName: 'B',
        ),
      );
      navigation.beginSimulation();
      var t = DateTime(2026, 10, 2, 8);
      void go(LatLng p) {
        t = t.add(Duration(milliseconds: (20 / speed * 1000).round()));
        navigation.feedSimulatedPosition(fix(p, t, speed));
      }

      for (var y = 0.0; y <= 500; y += 20) {
        go(_at(0, y));
      }
      for (var y = 500.0; y <= 1100; y += 20) {
        go(_at(150, y));
      }
      for (var y = 1100.0; y <= 1600; y += 20) {
        go(_at(0, y));
      }
      final deviations = navigation.finishDeviations();
      navigation.stop();
      return deviations;
    }

    test('a vehicle taking another road is recorded', () {
      final deviations = ride(8);
      expect(deviations, hasLength(1));
      expect(deviations.single.fromMeters, closeTo(500, 60));
      expect(deviations.single.toMeters, closeTo(1100, 60));
      expect(deviations.single.lengthMeters, greaterThan(500));
    });

    test('walking off the route is not a correction', () {
      expect(ride(1.2), isEmpty);
    });
  });
}
