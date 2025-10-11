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
  final String? eta;
  final List<Report> reports;

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
    this.eta,
    this.reports = const [],
  });
}

class Step {
  final String mode;
  final String instruction;
  final String details;

  Step({required this.mode, required this.instruction, required this.details});
}

class Report {
  final String type;
  final String? description;
  final DateTime timestamp;

  Report({required this.type, this.description, required this.timestamp});
}
