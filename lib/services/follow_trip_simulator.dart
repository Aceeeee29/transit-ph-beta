import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'active_navigation_service.dart';
import 'route_follow_engine.dart';

/// Debug builds only: plays a trip along the followed route through
/// [ActiveNavigationService] in place of real GPS, to test following,
/// boarding guidance and rerouting without leaving home.
class FollowTripSimulator {
  FollowTripSimulator._();
  static final FollowTripSimulator instance = FollowTripSimulator._();

  static const walkSpeedKmh = 5.0;
  static const _startAwayMeters = 250.0;
  static const _detourOffsetMeters = 120.0;
  static const _detourLengthMeters = 250.0;
  static const _tick = Duration(seconds: 1);

  final ValueNotifier<bool> isRunning = ValueNotifier(false);
  Timer? _timer;
  final _random = math.Random();

  /// [speedKmh] is the travel speed along the route; [timeScale] speeds the
  /// playback up without changing the reported speed. With [startAway] the
  /// trip begins off the route and walks to it; with [detour] it leaves the
  /// route partway and comes back further on, at [speedKmh].
  void start({
    required List<LatLng> path,
    required double speedKmh,
    double timeScale = 1,
    bool startAway = false,
    bool detour = false,
    double jitterMeters = 0,
  }) {
    if (!kDebugMode || path.length < 2) return;
    stop();

    final legs = _buildTrip(
      RouteFollowEngine(path),
      speedMps: speedKmh / 3.6,
      startAway: startAway,
      detour: detour,
    );
    if (legs.isEmpty) return;

    final navigation = ActiveNavigationService.instance;
    navigation.beginSimulation();
    isRunning.value = true;

    var legIndex = 0;
    var metersIntoLeg = 0.0;
    _timer = Timer.periodic(_tick, (_) {
      if (!navigation.isSimulating) {
        stop();
        return;
      }
      var leg = legs[legIndex];
      metersIntoLeg += leg.speedMps * _tick.inMilliseconds / 1000 * timeScale;
      while (metersIntoLeg > leg.lengthMeters && legIndex < legs.length - 1) {
        metersIntoLeg -= leg.lengthMeters;
        leg = legs[++legIndex];
      }
      final done =
          legIndex == legs.length - 1 && metersIntoLeg >= leg.lengthMeters;
      final point = leg.pointAt(math.min(metersIntoLeg, leg.lengthMeters));
      navigation.feedSimulatedPosition(
        _position(_jitter(point, jitterMeters), leg, metersIntoLeg),
      );
      if (done || navigation.hasArrived) stop();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (isRunning.value) isRunning.value = false;
    ActiveNavigationService.instance.endSimulation();
  }

  List<_Leg> _buildTrip(
    RouteFollowEngine route, {
    required double speedMps,
    required bool startAway,
    required bool detour,
  }) {
    final legs = <_Leg>[];
    final total = route.totalMeters;
    final joinAt = startAway ? total * 0.4 : 0.0;

    if (startAway) {
      legs.add(
        _Leg([_offset(route, joinAt, _startAwayMeters), route.pointAt(joinAt)],
            walkSpeedKmh / 3.6),
      );
    }

    final rideFrom = joinAt;
    var detourFrom = double.infinity;
    var detourTo = double.infinity;
    if (detour) {
      detourFrom = rideFrom + (total - rideFrom) * 0.3;
      detourTo = math.min(detourFrom + _detourLengthMeters, total * 0.9);
    }

    final ride = <LatLng>[];
    for (var m = rideFrom; m < total; m += 15) {
      if (m >= detourFrom && m < detourTo) {
        ride.addAll(_detourPoints(route, detourFrom, detourTo));
        m = detourTo;
      }
      ride.add(route.pointAt(m));
    }
    ride.add(route.path.last);
    legs.add(_Leg(ride, speedMps));
    return legs.where((l) => l.lengthMeters > 0).toList();
  }

  /// Out to the side of the route, along it, and back in.
  List<LatLng> _detourPoints(RouteFollowEngine route, double from, double to) {
    final points = <LatLng>[route.pointAt(from)];
    for (var m = from; m <= to; m += 25) {
      points.add(_offset(route, m, _detourOffsetMeters));
    }
    return points;
  }

  /// The point [sideMeters] to the right of the route at [along].
  LatLng _offset(RouteFollowEngine route, double along, double sideMeters) {
    final a = route.pointAt(math.max(0, along - 5));
    final b = route.pointAt(math.min(route.totalMeters, along + 5));
    final bearing = const Distance().bearing(a, b);
    return const Distance().offset(route.pointAt(along), sideMeters, bearing + 90);
  }

  LatLng _jitter(LatLng point, double meters) {
    if (meters <= 0) return point;
    return const Distance().offset(
      point,
      _random.nextDouble() * meters,
      _random.nextDouble() * 360,
    );
  }

  Position _position(LatLng point, _Leg leg, double metersIntoLeg) {
    final ahead = leg.pointAt(math.min(metersIntoLeg + 5, leg.lengthMeters));
    final heading = (const Distance().bearing(point, ahead) + 360) % 360;
    return Position(
      latitude: point.latitude,
      longitude: point.longitude,
      timestamp: DateTime.now(),
      accuracy: 8,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: heading,
      headingAccuracy: 10,
      speed: leg.speedMps,
      speedAccuracy: 1,
    );
  }
}

class _Leg {
  final RouteFollowEngine _line;
  final double speedMps;

  _Leg(List<LatLng> points, this.speedMps)
    : _line = RouteFollowEngine(
        points.length >= 2 ? points : [points.first, points.first],
      );

  double get lengthMeters => _line.totalMeters;
  LatLng pointAt(double meters) => _line.pointAt(meters);
}
