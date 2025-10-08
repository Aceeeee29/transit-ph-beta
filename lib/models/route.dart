import 'package:latlong2/latlong.dart';

class Route {
  final String id;
  final String startLocation;
  final String endLocation;
  final String shortDescription;
  final List<Step> steps;
  final double? startLat;
  final double? startLng;
  final double? endLat;
  final double? endLng;
  final List<LatLng> pathPoints;

  Route({
    required this.id,
    required this.startLocation,
    required this.endLocation,
    required this.shortDescription,
    required this.steps,
    this.startLat,
    this.startLng,
    this.endLat,
    this.endLng,
    this.pathPoints = const [],
  });
}

class Step {
  final String mode;
  final String instruction;
  final String details;

  Step({required this.mode, required this.instruction, required this.details});
}
