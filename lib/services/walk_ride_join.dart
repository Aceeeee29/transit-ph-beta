import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Joins walks to rides where the walk actually meets the ride's line.
///
/// The router boards and leaves rides at fixed points (stops, or nodes
/// ~300 m apart on rider routes), and the walk is routed on real streets
/// to that point. When the street walk reaches the ride's road early, it
/// used to keep walking along it to the stop, and the ride then drove back
/// over the same stretch. For rides you can hail anywhere on the road, the
/// rider instead boards where the walk first touches the line, and gets off
/// where the next walk last touches it.
class WalkRideJoin {
  WalkRideJoin._();

  /// Walking this close to a ride's line counts as standing on its road.
  static const onLineM = 20.0;

  /// Smaller savings aren't worth moving a stop the router chose.
  static const _minGainM = 15.0;

  /// A ride left shorter than this keeps its original ends.
  static const _minRideM = 100.0;

  /// Moved further than this, the stop's name no longer fits.
  static const _renameAfterM = 150.0;

  /// Walk samples are taken this far apart, so a walk that crosses the
  /// ride's road between two of its points still touches it.
  static const _sampleM = 8.0;

  /// Modes riders flag down anywhere along the road. Buses, trains and
  /// ferries keep their stops.
  static bool canHail(String mode) =>
      mode == 'Jeepney' || mode == 'Tricycle' || mode == 'FX/Van';

  /// [walk] leads to the start of [ride]. If it reaches the ride's line
  /// sooner, the walk stops there and the ride starts there instead.
  /// Null when nothing changes.
  static ({List<LatLng> walk, List<LatLng> ride})? board(
    List<LatLng> walk,
    List<LatLng> ride,
  ) {
    if (walk.length < 2 || ride.length < 2) return null;
    final line = _Line(ride);
    final total = line.along.last;
    if (total < _minRideM * 2) return null;

    final walkLength = _length(walk);
    for (final sample in _samples(walk)) {
      final hit = line.nearest(
        sample.point,
        after: 0,
        before: total - _minRideM,
      );
      if (hit.distanceM > onLineM) continue;
      final onLine = line.pointAt(hit.along);
      final newWalk = [
        ...walk.take(sample.segment + 1),
        if (_m(sample.point, walk[sample.segment]) > 0.5) sample.point,
        onLine,
      ];
      if (_length(newWalk) + _minGainM > walkLength) return null;
      return (walk: newWalk, ride: line.slice(hit.along, total));
    }
    return null;
  }

  /// [walk] leads away from the end of [ride]. If it touches the ride's
  /// line again (often walking back along it), the rider gets off at the
  /// last such point instead. Null when nothing changes.
  static ({List<LatLng> ride, List<LatLng> walk})? alight(
    List<LatLng> ride,
    List<LatLng> walk,
  ) {
    if (walk.length < 2 || ride.length < 2) return null;
    final line = _Line(ride);
    final total = line.along.last;
    if (total < _minRideM * 2) return null;

    final walkLength = _length(walk);
    final samples = _samples(walk).toList();
    for (final sample in samples.reversed) {
      final hit = line.nearest(sample.point, after: _minRideM, before: total);
      if (hit.distanceM > onLineM) continue;
      final onLine = line.pointAt(hit.along);
      final newWalk = [
        onLine,
        if (_m(sample.point, walk[sample.segment + 1]) > 0.5) sample.point,
        ...walk.skip(sample.segment + 1),
      ];
      if (_length(newWalk) + _minGainM > walkLength) return null;
      return (ride: line.slice(0, hit.along), walk: newWalk);
    }
    return null;
  }

  /// [name] kept unless the stop moved more than [_renameAfterM] from
  /// [was]; then "the stop near X" becomes "the spot near X".
  static String renamed(String name, LatLng was, LatLng now) {
    if (_m(was, now) <= _renameAfterM) return name;
    const prefix = 'the stop near ';
    final landmark =
        name.startsWith(prefix) ? name.substring(prefix.length) : name;
    return 'the spot near $landmark';
  }

  /// Points every ~[_sampleM] along [walk], each with the segment it's on.
  static Iterable<({LatLng point, int segment})> _samples(
    List<LatLng> walk,
  ) sync* {
    for (var i = 0; i < walk.length - 1; i++) {
      final a = walk[i];
      final b = walk[i + 1];
      final steps = math.max(1, (_m(a, b) / _sampleM).ceil());
      for (var k = 0; k < steps; k++) {
        final t = k / steps;
        yield (
          point: LatLng(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
          ),
          segment: i,
        );
      }
    }
    yield (point: walk.last, segment: walk.length - 2);
  }

  static double _length(List<LatLng> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += _m(points[i - 1], points[i]);
    }
    return total;
  }

  static double _m(LatLng a, LatLng b) =>
      const Distance(roundResult: false).as(LengthUnit.Meter, a, b);
}

/// A path in local meters, measured along its length.
class _Line {
  _Line(this.points)
    : _origin = points.first,
      _cosLat = math.cos(points.first.latitude * math.pi / 180) {
    _xy = [for (final p in points) _toXy(p)];
    along = [0.0];
    for (var i = 1; i < _xy.length; i++) {
      along.add(along.last + _len(_xy[i - 1], _xy[i]));
    }
  }

  final List<LatLng> points;
  final LatLng _origin;
  final double _cosLat;
  late final List<(double, double)> _xy;

  /// Meters from the start to each point.
  late final List<double> along;

  static const _mPerDegLat = 110540.0;
  static const _mPerDegLng = 111320.0;

  (double, double) _toXy(LatLng p) => (
    (p.longitude - _origin.longitude) * _cosLat * _mPerDegLng,
    (p.latitude - _origin.latitude) * _mPerDegLat,
  );

  LatLng _toLatLng((double, double) xy) => LatLng(
    _origin.latitude + xy.$2 / _mPerDegLat,
    _origin.longitude + xy.$1 / (_cosLat * _mPerDegLng),
  );

  static double _len((double, double) a, (double, double) b) =>
      math.sqrt(math.pow(b.$1 - a.$1, 2) + math.pow(b.$2 - a.$2, 2));

  (double, double) _xyAt(double at) {
    for (var i = 1; i < along.length; i++) {
      if (at <= along[i] || i == along.length - 1) {
        final seg = along[i] - along[i - 1];
        final t = seg == 0 ? 0.0 : ((at - along[i - 1]) / seg).clamp(0.0, 1.0);
        final a = _xy[i - 1];
        final b = _xy[i];
        return (a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t);
      }
    }
    return _xy.last;
  }

  /// The point [at] meters along the path.
  LatLng pointAt(double at) => _toLatLng(_xyAt(at));

  /// The closest point to [p] between [after] and [before] meters along.
  ({double along, double distanceM}) nearest(
    LatLng p, {
    required double after,
    required double before,
  }) {
    final q = _toXy(p);
    var best = (along: after, distanceM: _len(q, _xyAt(after)));
    if (before <= after) return best;
    for (var i = 1; i < _xy.length; i++) {
      final s0 = along[i - 1];
      final s1 = along[i];
      if (s1 < after || s0 > before) continue;
      final a = _xy[i - 1];
      final b = _xy[i];
      final dx = b.$1 - a.$1;
      final dy = b.$2 - a.$2;
      final seg2 = dx * dx + dy * dy;
      final t =
          seg2 == 0 ? 0.0 : ((q.$1 - a.$1) * dx + (q.$2 - a.$2) * dy) / seg2;
      final at = (s0 + t.clamp(0.0, 1.0) * (s1 - s0)).clamp(after, before);
      final u = s1 == s0 ? 0.0 : (at - s0) / (s1 - s0);
      final d = _len(q, (a.$1 + dx * u, a.$2 + dy * u));
      if (d < best.distanceM) best = (along: at, distanceM: d);
    }
    return best;
  }

  /// The path between [from] and [to] meters along, cut points included.
  List<LatLng> slice(double from, double to) {
    final out = <LatLng>[from <= 0 ? points.first : pointAt(from)];
    for (var i = 0; i < points.length; i++) {
      if (along[i] > from && along[i] < to) out.add(points[i]);
    }
    out.add(to >= along.last ? points.last : pointAt(to));
    return out;
  }
}
