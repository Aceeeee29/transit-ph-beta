import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

/// Which way the traveler faces, in degrees from north (null until known):
/// the phone's compass on foot, the GPS direction of travel on a ride
/// (the phone may be held sideways in a jeep).
///
/// The compass reports many times a second and jitters, so it's smoothed,
/// and a change of under [_step] degrees isn't passed on.
class Facing extends ValueNotifier<double?> {
  Facing() : super(null);

  /// Faster than this (about 7 km/h) is a ride, not a walk.
  static const rideSpeedMps = 2.0;

  static const _step = 2.0;

  /// How much of each compass reading is taken in (the rest is the
  /// smoothed heading so far).
  static const _smoothing = 0.2;

  StreamSubscription<CompassEvent>? _compass;
  double? _smoothed;
  double _speed = 0;

  /// Listens to the compass; [dispose] stops it.
  void start() {
    _compass ??= FlutterCompass.events?.listen(
      _onCompass,
      onError: (Object e) => debugPrint('[Facing] compass: $e'),
    );
  }

  /// A GPS fix: on a ride, its direction of travel is the facing.
  void onFix(Position position) {
    _speed = position.speed;
    final course = position.heading;
    if (_speed >= rideSpeedMps && course.isFinite && course >= 0) {
      _publish(course);
    }
  }

  void _onCompass(CompassEvent event) {
    final raw = event.heading;
    if (raw == null || !raw.isFinite) return;
    final smoothed = _smoothed;
    _smoothed =
        smoothed == null
            ? _normalize(raw)
            : _normalize(smoothed + difference(smoothed, raw) * _smoothing);
    if (_speed < rideSpeedMps) _publish(_smoothed!);
  }

  void _publish(double heading) {
    final next = _normalize(heading);
    final now = value;
    if (now != null && difference(now, next).abs() < _step) return;
    value = next;
  }

  /// The signed turn from [from] to [to], -180..180.
  static double difference(double from, double to) =>
      (to - from + 540) % 360 - 180;

  static double _normalize(double degrees) => (degrees % 360 + 360) % 360;

  @override
  void dispose() {
    _compass?.cancel();
    super.dispose();
  }
}
