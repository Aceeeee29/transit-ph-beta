import 'package:latlong2/latlong.dart';

/// Removes the side trips road snapping adds to a ride's line.
///
/// Why this exists: many transit-feed stops sit a little off the main
/// road, on a side street. Snapping a ride through its stops then drives
/// into that side street to reach the stop and straight back out, so the
/// line grows a spike at each such stop, or a small box where a one-way
/// street makes it circle the block. The vehicle never goes there.
///
/// We find where the line comes back to (nearly) the same spot within a
/// short distance and cut out the stretch in between.
class RidePathCleanup {
  RidePathCleanup._();

  /// Coming back within this distance of an earlier point closes a side
  /// trip.
  static const _returnMeters = 20.0;

  /// Side trips are short. A longer stretch that comes back to the same
  /// spot is more likely the real route, so it stays.
  static const _maxSideTripMeters = 1000.0;

  /// Shorter than this isn't a side trip, just points close together.
  static const _minSideTripMeters = 40.0;

  static const _distance = Distance();

  /// [path] with every side trip cut out. Both ends are kept.
  static List<LatLng> removeSpurs(List<LatLng> path) {
    if (path.length < 4) return path;
    final out = <LatLng>[];
    var i = 0;
    while (i < path.length) {
      out.add(path[i]);
      final back = _furthestReturn(path, i);
      i = back ?? i + 1;
    }
    return out;
  }

  /// The furthest point after [from], within [_maxSideTripMeters] along the
  /// line, that comes back to [from]'s spot after a real side trip. Taking
  /// the furthest one removes side trips inside side trips in one cut.
  static int? _furthestReturn(List<LatLng> path, int from) {
    final start = path[from];
    var along = 0.0;
    int? found;
    for (var j = from + 1; j < path.length - 1; j++) {
      along += _distance.as(LengthUnit.Meter, path[j - 1], path[j]);
      if (along > _maxSideTripMeters) break;
      if (along < _minSideTripMeters) continue;
      if (_distance.as(LengthUnit.Meter, start, path[j]) <= _returnMeters) {
        found = j;
      }
    }
    return found;
  }
}
