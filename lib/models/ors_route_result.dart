import 'package:latlong2/latlong.dart';

/// Represents a parsed response from the OpenRouteService Directions API.
/// This is an intermediate model — it gets converted into your app's
/// [Route] model before being shown to the user or stored in Firestore.
class OrsRouteResult {
  /// Total distance in meters
  final double distanceMeters;

  /// Total duration in seconds
  final double durationSeconds;

  /// Decoded polyline points for drawing on the map
  final List<LatLng> polyline;

  /// Turn-by-turn instruction steps parsed from ORS
  final List<OrsStep> steps;

  /// Bounding box: [minLon, minLat, maxLon, maxLat]
  final List<double> bbox;

  const OrsRouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.polyline,
    required this.steps,
    required this.bbox,
  });

  /// Human-readable distance string (e.g. "3.2 km" or "450 m")
  String get distanceLabel {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.toInt()} m';
  }

  /// Human-readable duration string (e.g. "25 mins" or "1 hr 10 mins")
  String get durationLabel {
    final totalMinutes = (durationSeconds / 60).round();
    if (totalMinutes >= 60) {
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      return minutes > 0 ? '$hours hr $minutes mins' : '$hours hr';
    }
    return '$totalMinutes mins';
  }

  /// Serialise to a plain Map for Firestore storage
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

  /// Deserialise from a Firestore document
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

/// A single turn-by-turn instruction step from ORS
class OrsStep {
  /// Human-readable instruction (e.g. "Turn left onto Rizal Ave")
  final String instruction;

  /// Distance of this step in meters
  final double distanceMeters;

  /// Duration of this step in seconds
  final double durationSeconds;

  const OrsStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
        'instruction': instruction,
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
      };

  factory OrsStep.fromJson(Map<String, dynamic> json) => OrsStep(
        instruction: json['instruction'] as String,
        distanceMeters: (json['distanceMeters'] as num).toDouble(),
        durationSeconds: (json['durationSeconds'] as num).toDouble(),
      );
}