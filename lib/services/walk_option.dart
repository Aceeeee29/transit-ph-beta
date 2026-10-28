import 'package:latlong2/latlong.dart';

/// When walking the whole way is offered as a route option, and which
/// rides are worth taking instead.
///
/// The route search always builds trips with at least one ride, so a
/// destination 200 m away came back as "walk 450 m to a jeep, ride a loop,
/// walk back past where you started".
///
/// Walks are judged by a real walking path, never the straight line: two
/// places 250 m apart can be 1.2 km on foot around a river or walled
/// subdivision.
class WalkOption {
  WalkOption._();

  /// Walks up to this long are offered as an option of their own.
  static const maxMinutes = 30.0;

  static const _walkSpeedKmh = 5.0;

  static const _distance = Distance(roundResult: false);

  /// Whether [from] and [to] are close enough that walking might be an
  /// option, so a walking path is worth asking for. Walking is never
  /// shorter than the straight line.
  static bool worthAsking(LatLng from, LatLng to) =>
      _minutesFor(_distance.as(LengthUnit.Meter, from, to)) <= maxMinutes;

  /// Minutes to walk [path] (a real walking path), when short enough to
  /// offer.
  static double? offered(List<LatLng> path) {
    var meters = 0.0;
    for (var i = 1; i < path.length; i++) {
      meters += _distance.as(LengthUnit.Meter, path[i - 1], path[i]);
    }
    final walk = _minutesFor(meters);
    return walk <= maxMinutes ? walk : null;
  }

  static double _minutesFor(double meters) =>
      meters / 1000 / _walkSpeedKmh * 60;

  /// Whether a ride option taking [rideMinutes] is worth showing next to
  /// walking the whole way in [walkMinutes]: any ride that gets there
  /// sooner, since riders take a short jeep ride to skip the heat or rain.
  static bool rideWorthIt(double rideMinutes, double walkMinutes) =>
      rideMinutes < walkMinutes;
}
