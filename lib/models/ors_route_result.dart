import 'package:latlong2/latlong.dart';

class OrsRouteResult {
  final double distanceMeters;

  final double durationSeconds;

  final List<LatLng> polyline;

  final List<OrsStep> steps;

  final List<double> bbox;

  const OrsRouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.polyline,
    required this.steps,
    required this.bbox,
  });

  String get distanceLabel {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.toInt()} m';
  }

  String get durationLabel {
    final totalMinutes = (durationSeconds / 60).round();
    if (totalMinutes >= 60) {
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      return minutes > 0 ? '$hours hr $minutes mins' : '$hours hr';
    }
    return '$totalMinutes mins';
  }

  Map<String, dynamic> toJson() {
    return {
      'distanceMeters': distanceMeters,
      'durationSeconds': durationSeconds,
      'polyline': polyline
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList(),
      'steps': steps.map((s) => s.toJson()).toList(),
      'bbox': bbox,
    };
  }

  factory OrsRouteResult.fromJson(Map<String, dynamic> json) {
    return OrsRouteResult(
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
      polyline: (json['polyline'] as List)
          .map((p) => LatLng(
                (p['lat'] as num).toDouble(),
                (p['lng'] as num).toDouble(),
              ))
          .toList(),
      steps: (json['steps'] as List)
          .map((s) => OrsStep.fromJson(s as Map<String, dynamic>))
          .toList(),
      bbox: (json['bbox'] as List).map((v) => (v as num).toDouble()).toList(),
    );
  }
}

class OrsStep {
  final String instruction;
  final double distanceMeters;
  final double durationSeconds;
  final String suggestedMode;
  final double estimatedFare;
  final int wayPointStart;
  final int wayPointEnd;

  const OrsStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
    this.suggestedMode = 'Jeepney',
    this.estimatedFare = 0.0,
    this.wayPointStart = 0,
    this.wayPointEnd = 0,
  });

  Map<String, dynamic> toJson() => {
        'instruction': instruction,
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'suggestedMode': suggestedMode,
        'estimatedFare': estimatedFare,
        'wayPointStart': wayPointStart,
        'wayPointEnd': wayPointEnd,
      };

  factory OrsStep.fromJson(Map<String, dynamic> json) => OrsStep(
        instruction: json['instruction'] as String,
        distanceMeters: (json['distanceMeters'] as num).toDouble(),
        durationSeconds: (json['durationSeconds'] as num).toDouble(),
        suggestedMode: json['suggestedMode'] as String? ?? 'Jeepney',
        estimatedFare: (json['estimatedFare'] as num?)?.toDouble() ?? 0.0,
        wayPointStart: json['wayPointStart'] as int? ?? 0,
        wayPointEnd: json['wayPointEnd'] as int? ?? 0,
      );
}