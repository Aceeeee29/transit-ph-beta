import 'package:latlong2/latlong.dart';

/// A handle on the drawing map inside a step: a via point (drag to move,
/// long-press to remove) or the "+" in the middle of a piece (drag to add a
/// via point there; [controlIndex] is then the piece's index). The map
/// draws them as `MapHandle`s.
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
