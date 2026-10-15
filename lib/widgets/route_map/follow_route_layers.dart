import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../services/route_follow_engine.dart';
import '../../services/route_follow_guidance.dart';
import '../map/transit_map.dart';

/// Map layers shared by the screens that follow a route.
class FollowRouteLayers {
  static final travelledFill = Colors.grey.shade400;
  static final travelledOutline = Colors.grey.shade600;
  static const connectorColor = Color(0xFF0B8FD6);

  /// The route, one line pair per step range. While following, the part
  /// already travelled is grey and the rest keeps its colour, split exactly
  /// at the traveler's progress point.
  static List<MapLine> routeLines({
    required List<LatLng> path,
    required List<({int start, int end, Color color})> ranges,
    required RouteFollowSnapshot? snapshot,
    required Color outline,
    double outlineWidth = 8.0,
    double fillWidth = 6.0,
  }) {
    if (path.length < 2) return const [];

    List<MapLine> line(List<LatLng> pts, Color fill, Color edge) {
      if (pts.length < 2) return const [];
      return [
        MapLine(pts, color: edge, width: outlineWidth),
        MapLine(pts, color: fill, width: fillWidth),
      ];
    }

    final last = path.length - 1;
    final splitSegment = snapshot?.progressSegment ?? -1;
    final travelled = <MapLine>[];
    final remaining = <MapLine>[];

    for (final range in ranges) {
      final start = range.start.clamp(0, last);
      final end = range.end.clamp(0, last);
      if (end <= start) continue;
      final pts = path.sublist(start, end + 1);
      if (snapshot == null || !snapshot.hasProgress || splitSegment < start) {
        remaining.addAll(line(pts, range.color, outline));
      } else if (snapshot.hasArrived || splitSegment >= end) {
        travelled.addAll(line(pts, travelledFill, travelledOutline));
      } else {
        final cut = snapshot.progressPoint;
        travelled.addAll(
          line(
            [...path.sublist(start, splitSegment + 1), cut],
            travelledFill,
            travelledOutline,
          ),
        );
        remaining.addAll(
          line(
            [cut, ...path.sublist(splitSegment + 1, end + 1)],
            range.color,
            outline,
          ),
        );
      }
    }
    // Remaining on top, so it stays visible where a route doubles back.
    return [...travelled, ...remaining];
  }

  /// Whether the step covering [range] has been passed.
  static bool isRangeCompleted(
    ({int start, int end, Color color}) range,
    RouteFollowSnapshot? snapshot,
  ) {
    if (snapshot == null || !snapshot.hasProgress) return false;
    return snapshot.hasArrived || snapshot.progressSegment >= range.end;
  }

  /// Dotted temporary path to the boarding/rejoin point. It is only a way
  /// back to the route and never part of it.
  static List<MapLine> connectorLines(List<LatLng>? connector) {
    if (connector == null || connector.length < 2) return const [];
    return [
      MapLine(connector, color: Colors.white, width: 7.0),
      MapLine(
        connector,
        color: connectorColor,
        width: 4.0,
        style: MapLineStyle.dotted,
      ),
    ];
  }

  static const detourColor = Color(0xFFE8833A);

  /// The path the vehicle is actually taking while off the route. Shown
  /// as it goes; afterwards the rider can offer it as a correction.
  static List<MapLine> detourLines(List<LatLng>? detour) {
    if (detour == null || detour.length < 2) return const [];
    return [
      MapLine(detour, color: Colors.white, width: 7.0),
      MapLine(
        detour,
        color: detourColor,
        width: 4.5,
        style: MapLineStyle.dashed,
      ),
    ];
  }

  /// The next point to reach: a white ring in the connector's blue.
  static MapDot? targetDot(FollowGuidance guidance) {
    final target = guidance.target;
    if (target == null) return null;
    return MapDot(
      target,
      radius: 9,
      strokeColor: connectorColor,
      strokeWidth: 4,
    );
  }
}
