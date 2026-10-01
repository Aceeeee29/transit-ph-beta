import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/route_follow_engine.dart';
import '../../services/route_follow_guidance.dart';

/// Map layers shared by the screens that follow a route.
class FollowRouteLayers {
  static final travelledFill = Colors.grey.shade400;
  static final travelledOutline = Colors.grey.shade600;
  static const connectorColor = Color(0xFF2E7CF6);

  /// The route, one polyline pair per step range. While following, the part
  /// already travelled is grey and the rest keeps its colour, split exactly
  /// at the traveler's progress point.
  static List<Polyline> routeLines({
    required List<LatLng> path,
    required List<({int start, int end, Color color})> ranges,
    required RouteFollowSnapshot? snapshot,
    required Color outline,
    double outlineWidth = 8.0,
    double fillWidth = 6.0,
  }) {
    if (path.length < 2) return const [];

    List<Polyline> line(List<LatLng> pts, Color fill, Color edge) {
      if (pts.length < 2) return const [];
      return [
        Polyline(
          points: pts,
          color: edge,
          strokeWidth: outlineWidth,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        Polyline(
          points: pts,
          color: fill,
          strokeWidth: fillWidth,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      ];
    }

    final last = path.length - 1;
    final splitSegment = snapshot?.progressSegment ?? -1;
    final travelled = <Polyline>[];
    final remaining = <Polyline>[];

    for (final range in ranges) {
      final start = range.start.clamp(0, last);
      final end = range.end.clamp(0, last);
      if (end <= start) continue;
      final pts = path.sublist(start, end + 1);
      if (snapshot == null ||
          !snapshot.hasProgress ||
          splitSegment < start) {
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

  /// Dashed temporary path to the boarding/rejoin point. It is only a way
  /// back to the route and never part of it.
  static List<Polyline> connectorLines(List<LatLng>? connector) {
    if (connector == null || connector.length < 2) return const [];
    return [
      Polyline(
        points: connector,
        color: Colors.white,
        strokeWidth: 7.0,
        strokeCap: StrokeCap.round,
      ),
      Polyline(
        points: connector,
        color: connectorColor,
        strokeWidth: 4.0,
        strokeCap: StrokeCap.round,
        pattern: const StrokePattern.dotted(spacingFactor: 1.6),
      ),
    ];
  }

  static Marker? targetMarker(FollowGuidance guidance) {
    final target = guidance.target;
    if (target == null) return null;
    return Marker(
      point: target,
      width: 26,
      height: 26,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: connectorColor, width: 4),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
      ),
    );
  }
}
