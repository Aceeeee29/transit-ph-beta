import 'package:flutter/material.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';

class DraggableStepBodyHandle {
  final int stepIndex;
  final int controlIndex;
  final LatLng point;

  const DraggableStepBodyHandle({
    required this.stepIndex,
    required this.controlIndex,
    required this.point,
  });
}

class DraggableStepMarkersLayer extends StatelessWidget {
  final List<LatLng> boundaryWaypoints;
  final List<DraggableStepBodyHandle> bodyHandles;
  final void Function(int index, LatLng nextPoint) onBoundaryDragEnd;
  final void Function(
    int stepIndex,
    int controlIndex,
    LatLng nextPoint,
  ) onBodyDragEnd;
  final Color accent;

  const DraggableStepMarkersLayer({
    super.key,
    required this.boundaryWaypoints,
    required this.bodyHandles,
    required this.onBoundaryDragEnd,
    required this.onBodyDragEnd,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (boundaryWaypoints.isEmpty && bodyHandles.isEmpty) {
      return const SizedBox.shrink();
    }

    return DragMarkers(
      markers: [
        for (int i = 0; i < boundaryWaypoints.length; i++)
          DragMarker(
            key: ValueKey(
              'boundary-$i-${boundaryWaypoints[i].latitude}-${boundaryWaypoints[i].longitude}',
            ),
            point: boundaryWaypoints[i],
            size: const Size(46, 46),
            useLongPress: false,
            onDragEnd: (details, latLng) => onBoundaryDragEnd(i, latLng),
            onLongDragEnd: (details, latLng) => onBoundaryDragEnd(i, latLng),
            builder: (ctx, pos, isDragging) {
              final isEndpoint = i == 0 || i == boundaryWaypoints.length - 1;
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
        for (final handle in bodyHandles)
          DragMarker(
            key: ValueKey(
              'body-${handle.stepIndex}-${handle.controlIndex}-${handle.point.latitude}-${handle.point.longitude}',
            ),
            point: handle.point,
            size: const Size(32, 32),
            useLongPress: false,
            onDragEnd: (details, latLng) =>
                onBodyDragEnd(handle.stepIndex, handle.controlIndex, latLng),
            onLongDragEnd: (details, latLng) =>
                onBodyDragEnd(handle.stepIndex, handle.controlIndex, latLng),
            builder: (ctx, pos, isDragging) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: isDragging ? 26 : 22,
                height: isDragging ? 26 : 22,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.9),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: isDragging ? 8 : 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}