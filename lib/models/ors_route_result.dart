import 'package:latlong2/latlong.dart';

class OrsRouteResult {
  final double distanceMeters;

  final double durationSeconds;

  final List<LatLng> polyline;

  final List<OrsStep> steps;

  final List<double> bbox;

  /// The trip's fare before any discount, when it was worked out with the
  /// option it was drawn from, so the route shows the same fare as the list.
  /// Null means the sum of the steps' fares.
  final double? estimatedFarePhp;

  const OrsRouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.polyline,
    required this.steps,
    required this.bbox,
    this.estimatedFarePhp,
  });

  /// The fare before any discount: [estimatedFarePhp], or the steps' sum.
  double get baseFarePhp =>
      estimatedFarePhp ??
      steps.fold(0.0, (sum, step) => sum + step.estimatedFare);

  OrsRouteResult copyWith({double? durationSeconds, double? estimatedFarePhp}) {
    return OrsRouteResult(
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      polyline: polyline,
      steps: steps,
      bbox: bbox,
      estimatedFarePhp: estimatedFarePhp ?? this.estimatedFarePhp,
    );
  }

  bool get usesCommunityRoutes => steps.any((s) => s.isCommunity);

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
      'polyline':
          polyline.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      'steps': steps.map((s) => s.toJson()).toList(),
      'bbox': bbox,
      if (estimatedFarePhp != null) 'estimatedFarePhp': estimatedFarePhp,
    };
  }

  factory OrsRouteResult.fromJson(Map<String, dynamic> json) {
    return OrsRouteResult(
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
      polyline:
          (json['polyline'] as List)
              .map(
                (p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ),
              )
              .toList(),
      steps:
          (json['steps'] as List)
              .map((s) => OrsStep.fromJson(s as Map<String, dynamic>))
              .toList(),
      bbox: (json['bbox'] as List).map((v) => (v as num).toDouble()).toList(),
      estimatedFarePhp: (json['estimatedFarePhp'] as num?)?.toDouble(),
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

  /// True for rides taken from an admin-approved community route.
  final bool isCommunity;

  /// Where the step starts and ends ("Monumento"), when known; the follow
  /// card says "Ride to Monumento".
  final String? fromName;
  final String? toName;

  /// A walk with no real path found: its line is just the two ends and its
  /// length an estimate, so the map draws it dashed.
  final bool isEstimatedPath;

  const OrsStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
    this.suggestedMode = 'Jeepney',
    this.estimatedFare = 0.0,
    this.wayPointStart = 0,
    this.wayPointEnd = 0,
    this.isCommunity = false,
    this.fromName,
    this.toName,
    this.isEstimatedPath = false,
  });

  Map<String, dynamic> toJson() => {
    'instruction': instruction,
    'distanceMeters': distanceMeters,
    'durationSeconds': durationSeconds,
    'suggestedMode': suggestedMode,
    'estimatedFare': estimatedFare,
    'wayPointStart': wayPointStart,
    'wayPointEnd': wayPointEnd,
    'isCommunity': isCommunity,
    if (fromName != null) 'fromName': fromName,
    if (toName != null) 'toName': toName,
    if (isEstimatedPath) 'isEstimatedPath': true,
  };

  factory OrsStep.fromJson(Map<String, dynamic> json) => OrsStep(
    instruction: json['instruction'] as String,
    distanceMeters: (json['distanceMeters'] as num).toDouble(),
    durationSeconds: (json['durationSeconds'] as num).toDouble(),
    suggestedMode: json['suggestedMode'] as String? ?? 'Jeepney',
    estimatedFare: (json['estimatedFare'] as num?)?.toDouble() ?? 0.0,
    wayPointStart: json['wayPointStart'] as int? ?? 0,
    wayPointEnd: json['wayPointEnd'] as int? ?? 0,
    isCommunity: json['isCommunity'] as bool? ?? false,
    fromName: json['fromName'] as String?,
    toName: json['toName'] as String?,
    isEstimatedPath: json['isEstimatedPath'] as bool? ?? false,
  );
}
