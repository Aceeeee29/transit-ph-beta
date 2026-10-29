import 'package:latlong2/latlong.dart';

/// Decides when "walk the whole way" is shown as an option, and which ride
/// options are still worth showing next to it.
///
/// Why this exists: the route search always puts at least one ride in a
/// trip. So for a place only 200 m away, it once suggested "walk 450 m to
/// a jeep, ride it around a loop, then walk back past where you started".
///
/// We always judge a walk by its real walking path, not a straight line.
/// Two places 250 m apart on the map can be a 1.2 km walk, for example
/// when there's a river or a walled subdivision in between.
class WalkOption {
  WalkOption._();

  /// "Walk the whole way" is only offered for walks up to 30 minutes.
  static const maxMinutes = 30.0;

  static const _walkSpeedKmh = 5.0;

  static const _distance = Distance(roundResult: false);

  /// A quick check before asking the server for a walking path: could this
  /// trip possibly be walkable? A real walk is never shorter than the
  /// straight line, so if even the straight line takes over 30 minutes,
  /// there's no point asking.
  static bool worthAsking(LatLng from, LatLng to) =>
      _minutesFor(_distance.as(LengthUnit.Meter, from, to)) <= maxMinutes;

  /// How many minutes it takes to walk [path] (a real walking path).
  /// Returns null if it's too long to offer as "walk the whole way".
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

  /// Should a ride option that takes [rideMinutes] be shown next to
  /// walking the whole way ([walkMinutes])? Yes, as long as the ride gets
  /// there sooner. Even a short jeep ride is worth it to skip the heat or
  /// rain. A ride slower than walking (like the loop above) is hidden.
  static bool rideWorthIt(double rideMinutes, double walkMinutes) =>
      rideMinutes < walkMinutes;
}
