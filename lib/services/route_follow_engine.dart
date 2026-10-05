import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

enum RouteFollowStatus { onRoute, awayFromRoute, arrived }

/// Where the traveler is relative to the followed route after one GPS fix.
class RouteFollowSnapshot {
  final RouteFollowStatus status;
  final LatLng rawPosition;

  /// Closest point on the route to [rawPosition] (null before the first fix).
  final LatLng? matchedPosition;
  final double distanceFromRouteMeters;

  /// Whether progress has been established at least once. Until then the
  /// whole route is still ahead.
  final bool hasProgress;
  final double progressMeters;

  /// Progress lies on the segment between path[progressSegment] and
  /// path[progressSegment + 1], at [progressPoint].
  final int progressSegment;
  final LatLng progressPoint;
  final double totalMeters;

  /// When [status] last changed, e.g. how long the traveler has been away.
  final DateTime statusSince;

  const RouteFollowSnapshot({
    required this.status,
    required this.statusSince,
    required this.rawPosition,
    required this.matchedPosition,
    required this.distanceFromRouteMeters,
    required this.hasProgress,
    required this.progressMeters,
    required this.progressSegment,
    required this.progressPoint,
    required this.totalMeters,
  });

  bool get hasArrived => status == RouteFollowStatus.arrived;

  double get remainingMeters => math.max(0, totalMeters - progressMeters);

  /// The position to draw: on the line while the traveler is on the route,
  /// so normal GPS scatter doesn't show them beside it; raw GPS otherwise,
  /// so a real deviation stays visible.
  LatLng get displayPosition =>
      status == RouteFollowStatus.onRoute && matchedPosition != null
          ? matchedPosition!
          : rawPosition;
}

/// Matches GPS fixes onto a route polyline and tracks progress along it.
///
/// Fixes are projected onto segments (not vertices), and normally only onto
/// the stretch just behind/ahead of current progress, so routes that loop or
/// come back along the same road don't make progress jump to the far leg.
/// Progress only moves forward and only while the traveler is on the route.
class RouteFollowEngine {
  /// Base distance from the line that still counts as "on the route".
  static const onRouteMeters = 40.0;
  static const maxOnRouteMeters = 65.0;

  /// Consecutive fixes needed to flip between on/away, so one noisy fix
  /// doesn't toggle the state.
  static const awayAfterFixes = 3;
  static const backAfterFixes = 2;

  static const searchBehindMeters = 60.0;
  static const searchAheadMeters = 600.0;

  /// Fast travel between fixes (e.g. GPS dropping out under a flyover)
  /// widens the forward search by this speed times the gap.
  static const _maxTravelSpeedMps = 25.0;

  /// When several stretches match about equally well, prefer the earliest.
  static const _tieMeters = 15.0;

  static const arrivalMeters = 30.0;

  /// Arrival also needs most of the route covered, so a loop route whose
  /// start and end coincide doesn't finish the moment it starts.
  static const _arrivalProgressFraction = 0.85;

  final List<LatLng> path;
  final List<double> _cumulative;

  RouteFollowStatus? _status;
  DateTime _statusSince = DateTime.now();
  int _awayCount = 0;
  int _backCount = 0;
  bool _hasProgress = false;
  double _progress = 0;
  int _progressSegment = 0;
  late LatLng _progressPoint;
  DateTime? _lastMatchedAt;
  RouteFollowSnapshot? _last;

  RouteFollowEngine(List<LatLng> path)
    : assert(path.length >= 2),
      path = List.unmodifiable(path),
      _cumulative = _cumulativeMeters(path) {
    _progressPoint = this.path.first;
  }

  double get totalMeters => _cumulative.last;

  RouteFollowSnapshot? get lastSnapshot => _last;

  /// Where along the route the traveler is being guided to join it (the
  /// boarding or rejoin point). When the route passes the traveler's
  /// position more than once, joining prefers the pass nearest this.
  double? expectedJoinMeters;

  /// Index of the segment containing the point [meters] along the route.
  int segmentAt(double meters) =>
      _firstSegmentEndingAfter(meters.clamp(0, totalMeters).toDouble());

  /// Distance along the route of vertex [index].
  double alongAt(int index) => _cumulative[index.clamp(0, path.length - 1)];

  /// The point [meters] along the route.
  LatLng pointAt(double meters) {
    if (meters <= 0) return path.first;
    if (meters >= totalMeters) return path.last;
    final i = _firstSegmentEndingAfter(meters);
    final len = _cumulative[i + 1] - _cumulative[i];
    final t = len <= 0 ? 0.0 : (meters - _cumulative[i]) / len;
    final a = path[i], b = path[i + 1];
    return LatLng(
      a.latitude + t * (b.latitude - a.latitude),
      a.longitude + t * (b.longitude - a.longitude),
    );
  }

  /// Closest point to [p] on the route between distances [fromMeters] and
  /// [toMeters] along it (clamped to that range).
  RouteMatch? nearestInRange(LatLng p, double fromMeters, double toMeters) {
    if (toMeters < fromMeters) return null;
    RouteMatch? best;
    for (var i = _firstSegmentEndingAfter(fromMeters); i < path.length - 1; i++) {
      if (_cumulative[i] > toMeters) break;
      var m = _project(p, i);
      if (m.along < fromMeters || m.along > toMeters) {
        final along = m.along < fromMeters ? fromMeters : toMeters;
        final point = pointAt(along);
        m = RouteMatch(
          segment: i,
          distance: _haversineMeters(p, point),
          along: along,
          point: point,
        );
      }
      if (best == null || m.distance < best.distance) best = m;
    }
    return best;
  }

  RouteFollowSnapshot update(
    LatLng position, {
    double accuracyMeters = 0,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    if (_status == RouteFollowStatus.arrived) {
      return _last = _snapshot(position, _last?.matchedPosition, 0);
    }

    final tolerance = (onRouteMeters + accuracyMeters * 0.5).clamp(
      onRouteMeters,
      maxOnRouteMeters,
    );

    RouteMatch? match;
    if (_hasProgress) {
      final gapSeconds =
          _lastMatchedAt == null
              ? 0.0
              : now.difference(_lastMatchedAt!).inMilliseconds / 1000.0;
      final ahead = math.max(
        searchAheadMeters,
        gapSeconds * _maxTravelSpeedMps,
      );
      match = _bestMatch(
        position,
        _progress - searchBehindMeters,
        _progress + ahead,
      );
    }
    if (match == null || match.distance > tolerance) {
      // Not established yet, or lost near current progress: look along the
      // rest of the route (never behind progress) for a good match.
      final wide = _bestMatch(
        position,
        _hasProgress ? _progress : 0,
        double.infinity,
        preferEarliest: true,
      );
      if (wide != null && (match == null || wide.distance <= tolerance)) {
        match = wide;
      }
    }

    final distance = match?.distance ?? double.infinity;
    final isWithin = distance <= tolerance;
    _updateStatus(isWithin, now);

    if (isWithin && match != null) {
      _lastMatchedAt = now;
      if (!_hasProgress || match.along > _progress) {
        _hasProgress = true;
        _progress = match.along;
        _progressSegment = match.segment;
        _progressPoint = match.point;
      }
    }

    if (_hasArrived(position, accuracyMeters)) {
      _setStatus(RouteFollowStatus.arrived, now);
      _progress = totalMeters;
      _progressSegment = path.length - 2;
      _progressPoint = path.last;
    }

    return _last = _snapshot(position, match?.point, distance);
  }

  void _updateStatus(bool isWithin, DateTime now) {
    if (isWithin) {
      _awayCount = 0;
      if (_status == RouteFollowStatus.onRoute) return;
      _backCount++;
      if (_status == null || _backCount >= backAfterFixes) {
        _setStatus(RouteFollowStatus.onRoute, now);
        _backCount = 0;
      }
    } else {
      _backCount = 0;
      if (_status == RouteFollowStatus.awayFromRoute) return;
      _awayCount++;
      if (_status == null || _awayCount >= awayAfterFixes) {
        _setStatus(RouteFollowStatus.awayFromRoute, now);
        _awayCount = 0;
      }
    }
  }

  void _setStatus(RouteFollowStatus status, DateTime now) {
    if (_status == status) return;
    _status = status;
    _statusSince = now;
  }

  bool _hasArrived(LatLng position, double accuracyMeters) {
    if (!_hasProgress) return false;
    final needed = math.min(
      totalMeters - arrivalMeters,
      totalMeters * _arrivalProgressFraction,
    );
    if (_progress < needed) return false;
    final radius = math.max(arrivalMeters, math.min(accuracyMeters, 50.0));
    return _haversineMeters(position, path.last) <= radius;
  }

  RouteFollowSnapshot _snapshot(
    LatLng position,
    LatLng? matched,
    double distance,
  ) {
    return RouteFollowSnapshot(
      status: _status ?? RouteFollowStatus.awayFromRoute,
      statusSince: _statusSince,
      rawPosition: position,
      matchedPosition: matched,
      distanceFromRouteMeters: distance,
      hasProgress: _hasProgress,
      progressMeters: _progress,
      progressSegment: _progressSegment,
      progressPoint: _progressPoint,
      totalMeters: totalMeters,
    );
  }

  /// Closest projection of [p] onto segments overlapping the along-route
  /// range [from, to]. With [preferEarliest], one of the near-equal matches
  /// instead: the one nearest [expectedJoinMeters] if set, else the
  /// earliest, so first locking onto a loop route picks its start rather
  /// than its end.
  RouteMatch? _bestMatch(
    LatLng p,
    double from,
    double to, {
    bool preferEarliest = false,
  }) {
    final candidates = <RouteMatch>[];
    RouteMatch? best;
    for (var i = _firstSegmentEndingAfter(from); i < path.length - 1; i++) {
      if (_cumulative[i] > to) break;
      final m = _project(p, i);
      candidates.add(m);
      if (best == null || m.distance < best.distance) best = m;
    }
    if (best == null || !preferEarliest) return best;
    final limit = best.distance + _tieMeters;
    final close = candidates.where((m) => m.distance <= limit);
    final hint = expectedJoinMeters;
    if (hint == null) return close.first;
    return close.reduce(
      (a, b) => (a.along - hint).abs() <= (b.along - hint).abs() ? a : b,
    );
  }

  int _firstSegmentEndingAfter(double along) {
    if (along <= 0) return 0;
    var lo = 0;
    var hi = path.length - 2;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_cumulative[mid + 1] < along) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Projects [p] onto segment [i] in a local flat frame centred on [p]
  /// (accurate to well under a metre at city scale).
  RouteMatch _project(LatLng p, int i) {
    final a = path[i];
    final b = path[i + 1];
    final cosLat = math.cos(p.latitude * math.pi / 180);
    double x(LatLng q) =>
        (q.longitude - p.longitude) * math.pi / 180 * _earthRadius * cosLat;
    double y(LatLng q) => (q.latitude - p.latitude) * math.pi / 180 * _earthRadius;

    final ax = x(a), ay = y(a);
    final abx = x(b) - ax, aby = y(b) - ay;
    final len2 = abx * abx + aby * aby;
    final t = len2 == 0 ? 0.0 : ((-ax * abx - ay * aby) / len2).clamp(0.0, 1.0);
    final cx = ax + t * abx, cy = ay + t * aby;

    return RouteMatch(
      segment: i,
      distance: math.sqrt(cx * cx + cy * cy),
      along: _cumulative[i] + t * (_cumulative[i + 1] - _cumulative[i]),
      point: LatLng(
        a.latitude + t * (b.latitude - a.latitude),
        a.longitude + t * (b.longitude - a.longitude),
      ),
    );
  }

  static const _earthRadius = 6371008.8;

  static List<double> _cumulativeMeters(List<LatLng> path) {
    final result = List<double>.filled(path.length, 0);
    for (var i = 1; i < path.length; i++) {
      result[i] = result[i - 1] + _haversineMeters(path[i - 1], path[i]);
    }
    return result;
  }

  static double _haversineMeters(LatLng a, LatLng b) {
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * _earthRadius * math.asin(math.min(1, math.sqrt(h)));
  }
}

class RouteMatch {
  final int segment;
  final double distance;
  final double along;
  final LatLng point;

  const RouteMatch({
    required this.segment,
    required this.distance,
    required this.along,
    required this.point,
  });
}
