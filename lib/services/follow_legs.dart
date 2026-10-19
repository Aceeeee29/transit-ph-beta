import '../models/route.dart' as route_model;
import 'route_follow_engine.dart';
import 'route_follow_guidance.dart';

/// Where the traveler is within the followed route's steps ("legs").
class FollowLegProgress {
  /// The step being travelled now.
  final int index;

  /// Distance left to the end of that step.
  final double metersLeft;

  /// The whole step's length.
  final double legMeters;

  const FollowLegProgress({
    required this.index,
    required this.metersLeft,
    required this.legMeters,
  });

  /// "Get off soon": a ride step long enough to matter, nearly done.
  bool isGetOffSoon(List<FollowStep> steps) {
    if (index >= steps.length) return false;
    final mode = steps[index].mode;
    return mode != null &&
        mode != 'Walk' &&
        legMeters >= FollowLegs.getOffMinLegMeters &&
        metersLeft <= FollowLegs.getOffWarnMeters;
  }
}

class FollowLegs {
  FollowLegs._();

  /// How far before the end of a ride the "Get off soon" hint shows.
  static const getOffWarnMeters = 300.0;

  /// Rides shorter than this get no hint; it would show from the start.
  static const getOffMinLegMeters = 600.0;

  /// Where step [index] of a rider route starts and ends, when known: its
  /// first/last designated stop, else the route's own ends for the first
  /// and last step, else the neighbouring step's stop.
  static ({String? from, String? to}) riderStepEnds(
    route_model.Route route,
    int index,
  ) {
    final steps = route.steps;
    if (index < 0 || index >= steps.length) return (from: null, to: null);
    String? named(String? name) {
      final trimmed = name?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    }

    String? firstStop(route_model.Step step) =>
        step.usesDesignatedStops && step.stops.isNotEmpty
            ? named(step.stops.first.name)
            : null;
    String? lastStop(route_model.Step step) =>
        step.usesDesignatedStops && step.stops.isNotEmpty
            ? named(step.stops.last.name)
            : null;

    final step = steps[index];
    final from =
        firstStop(step) ??
        (index == 0 ? named(route.startLocation) : lastStop(steps[index - 1]));
    final to =
        lastStop(step) ??
        (index == steps.length - 1
            ? named(route.endLocation)
            : firstStop(steps[index + 1]));
    return (from: from, to: to);
  }

  /// The step containing [progressMeters]: the first one that ends ahead
  /// of it. Steps of no length (a transfer on the spot) are passed over.
  /// Past the end, the last step with nothing left.
  static FollowLegProgress? locate({
    required RouteFollowEngine engine,
    required List<FollowStep> steps,
    required double progressMeters,
  }) {
    if (steps.isEmpty) return null;
    for (var i = 0; i < steps.length; i++) {
      final start = engine.alongAt(steps[i].startIndex);
      final end = engine.alongAt(steps[i].endIndex);
      if (end - start <= 0) continue;
      if (end > progressMeters + 1) {
        return FollowLegProgress(
          index: i,
          metersLeft: end - progressMeters.clamp(start, end),
          legMeters: end - start,
        );
      }
    }
    final last = steps.length - 1;
    final start = engine.alongAt(steps[last].startIndex);
    final end = engine.alongAt(steps[last].endIndex);
    return FollowLegProgress(
      index: last,
      metersLeft: 0,
      legMeters: end - start,
    );
  }
}
