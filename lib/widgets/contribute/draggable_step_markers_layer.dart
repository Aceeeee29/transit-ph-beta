import 'package:flutter/material.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';

class DraggableStepMarkersLayer extends StatelessWidget {
  final List<LatLng> waypoints;
  final void Function(int index, LatLng nextPoint) onWaypointDragEnd;
  final Color accent;

  const DraggableStepMarkersLayer({
    super.key,
    required this.waypoints,
    required this.onWaypointDragEnd,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (waypoints.isEmpty) {
      return const SizedBox.shrink();
    }

    return DragMarkers(
      markers: [
        for (int i = 0; i < waypoints.length; i++)
          DragMarker(
            key: ValueKey('waypoint-$i-${waypoints[i].latitude}-${waypoints[i].longitude}'),
            point: waypoints[i],
            size: const Size(46, 46),
            useLongPress: false,
            onDragEnd: (details, latLng) => onWaypointDragEnd(i, latLng),
            onLongDragEnd: (details, latLng) => onWaypointDragEnd(i, latLng),
            builder: (ctx, pos, isDragging) {
              final isEndpoint = i == 0 || i == waypoints.length - 1;
              final fillColor = isEndpoint
                  ? (i == 0 ? Colors.green : Colors.red)
                  : accent;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: isDragging ? 40 : 36,
                height: isDragging ? 40 : 36,
                decoration: BoxDecoration(
                  color: fillColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.20),
                      blurRadius: isDragging ? 10 : 7,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}