import 'package:latlong2/latlong.dart';

/// When walking the whole way is offered as a route option, and which
/// rides are worth taking instead.
///
/// The route search always builds trips with at least one ride, so a
/// destination 200 m away came back as "walk 450 m to a jeep, ride a loop,
/// walk back past where you started".
class WalkOption {
  WalkOption._();

  /// Walks up to this long are offered as an option of their own.
  static const maxMinutes = 30.0;

  /// A ride must beat walking the whole way by at least this much.
  static const minRideSavingMinutes = 5.0;

  static const _walkSpeedKmh = 5.0;

  /// Streets go around blocks: about this much longer than a straight line
  /// (the route search's own estimate).
  static const _roadFactor = 1.3;

  /// Estimated minutes to walk from [from] to [to].
  static double minutes(LatLng from, LatLng to) {
    final km = const Distance(
      roundResult: false,
    ).as(LengthUnit.Kilometer, from, to);
    return km * _roadFactor / _walkSpeedKmh * 60;
  }

  /// Minutes to walk [from] → [to] when that's short enough to offer.
  static double? offered(LatLng from, LatLng to) {
    final walk = minutes(from, to);
    return walk <= maxMinutes ? walk : null;
  }

  /// Whether a ride option taking [rideMinutes] is worth showing next to
  /// walking the whole way in [walkMinutes].
  static bool rideWorthIt(double rideMinutes, double walkMinutes) =>
      rideMinutes <= walkMinutes - minRideSavingMinutes;
}
