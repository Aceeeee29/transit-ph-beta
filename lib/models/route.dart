import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

enum RouteApprovalStatus { pending, approved, rejected }

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
  final String? price;
  final String? distance;
  final String? schedule;
  final String? imageUrl;
  final List<String> audienceTags;
  final List<Report> reports;
  final List<int> stepBoundaries;
  final String? contributorId;
  final double? distanceMeters;
  int views;
  int upvotes;
  int downvotes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final RouteApprovalStatus approvalStatus;
  final bool isEdited;
  final DateTime? editedAt;
  final int editCount;

  /// Set on a rider's suggested correction: the id of the route it
  /// corrects. Approving it merges its line into that route.
  final String? correctionOf;

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
    this.price,
    this.distance,
    this.schedule,
    this.imageUrl,
    this.audienceTags = const [],
    this.reports = const [],
    this.stepBoundaries = const [],
    this.contributorId,
    this.distanceMeters,
    this.views = 0,
    this.upvotes = 0,
    this.downvotes = 0,
    this.createdAt,
    this.updatedAt,
    this.approvalStatus = RouteApprovalStatus.pending,
    this.isEdited = false,
    this.editedAt,
    this.editCount = 0,
    this.correctionOf,
  });

  bool get isApproved => approvalStatus == RouteApprovalStatus.approved;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startLocation': startLocation,
      'endLocation': endLocation,
      'shortDescription': shortDescription,
      'steps': steps
          .map(
            (s) => {
              'mode': s.mode,
              'instruction': s.instruction,
              'details': s.details,
              'is24_7': s.is24_7,
              'startTime': s.startTime,
              'endTime': s.endTime,
              'actualFare': s.actualFare,
              'alternateRouteSuggestion': s.alternateRouteSuggestion,
              if (s.boarding != null) 'boarding': s.boarding!.name,
              if (s.stops.isNotEmpty)
                'stops': s.stops.map((stop) => stop.toJson()).toList(),
              if (s.controlPoints.isNotEmpty)
                'controlPoints':
                    s.controlPoints
                        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
                        .toList(),
            },
          )
          .toList(),
      'startLat': startLat,
      'startLng': startLng,
      'endLat': endLat,
      'endLng': endLng,
      'pathPoints': pathPoints
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList(),
      'stepBoundaries': stepBoundaries,
      'eta': eta,
      'price': price,
      'distance': distance,
      'schedule': schedule,
      'imageUrl': imageUrl,
      'audienceTags': audienceTags,
      'distanceMeters': distanceMeters,
      'reports': reports
          .map(
            (r) => {
              'type': r.type,
              'description': r.description,
              'timestamp': r.timestamp.millisecondsSinceEpoch,
            },
          )
          .toList(),
      'contributorId': contributorId,
      'views': views,
      'upvotes': upvotes,
      'downvotes': downvotes,
      'approvalStatus': approvalStatus.name,
      'isEdited': isEdited,
      'editedAt': editedAt != null ? Timestamp.fromDate(editedAt!) : null,
      'editCount': editCount,
      if (correctionOf != null) 'correctionOf': correctionOf,
    };
  }

  factory Route.fromJson(Map<String, dynamic> json) {
    RouteApprovalStatus parsedStatus = RouteApprovalStatus.approved;
    final rawStatus = json['approvalStatus'] as String?;
    if (rawStatus != null) {
      parsedStatus = RouteApprovalStatus.values.firstWhere(
        (e) => e.name == rawStatus,
        orElse: () => RouteApprovalStatus.approved,
      );
    }

    double? asNullableDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return Route(
      id: json['id'],
      startLocation: json['startLocation'],
      endLocation: json['endLocation'],
      shortDescription: json['shortDescription'],
      steps: (json['steps'] as List)
          .map(
            (s) => Step(
              mode: s['mode'],
              instruction: s['instruction'],
              details: s['details'],
              is24_7: s['is24_7'] as bool? ?? true,
              startTime: s['startTime'] as String?,
              endTime: s['endTime'] as String?,
                actualFare: (s['actualFare'] as num?)?.toDouble(),
              alternateRouteSuggestion:
                  s['alternateRouteSuggestion'] as String?,
              boarding: StepBoarding.parse(s['boarding']),
              stops: RouteStop.listFromJson(s['stops']),
              controlPoints: [
                for (final p in (s['controlPoints'] as List? ?? const []))
                  if (p is Map && p['lat'] is num && p['lng'] is num)
                    LatLng(
                      (p['lat'] as num).toDouble(),
                      (p['lng'] as num).toDouble(),
                    ),
              ],
            ),
          )
          .toList(),
      startLat: asNullableDouble(json['startLat']),
      startLng: asNullableDouble(json['startLng']),
      endLat: asNullableDouble(json['endLat']),
      endLng: asNullableDouble(json['endLng']),
      pathPoints: (json['pathPoints'] as List)
          .map(
            (p) => LatLng(
              asNullableDouble(p['lat']) ?? 0.0,
              asNullableDouble(p['lng']) ?? 0.0,
            ),
          )
          .toList(),
      stepBoundaries:
          (json['stepBoundaries'] as List?)?.map((b) => b as int).toList() ??
          [],
      eta: json['eta'],
      price: json['price'],
      distance: json['distance'],
      schedule: json['schedule'],
      imageUrl: json['imageUrl'],
      audienceTags: List<String>.from(json['audienceTags'] ?? const []),
      distanceMeters: json['distanceMeters'] != null
          ? (json['distanceMeters'] as num).toDouble()
          : null,
      reports: (json['reports'] as List)
          .map(
            (r) => Report(
              type: r['type'],
              description: r['description'],
              timestamp: DateTime.fromMillisecondsSinceEpoch(r['timestamp']),
            ),
          )
          .toList(),
      contributorId: json['contributorId'],
      views: json['views'] is int
          ? json['views']
          : int.tryParse(json['views']?.toString() ?? '0') ?? 0,
      upvotes: json['upvotes'] is int
          ? json['upvotes']
          : int.tryParse(json['upvotes']?.toString() ?? '0') ?? 0,
      downvotes: json['downvotes'] is int
          ? json['downvotes']
          : int.tryParse(json['downvotes']?.toString() ?? '0') ?? 0,
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: json['updatedAt'] != null
          ? (json['updatedAt'] as Timestamp).toDate()
          : null,
      approvalStatus: parsedStatus,
      isEdited: json['isEdited'] as bool? ?? false,
      editedAt: json['editedAt'] != null
          ? (json['editedAt'] as Timestamp).toDate()
          : null,
      editCount: json['editCount'] is int
          ? json['editCount']
          : int.tryParse(json['editCount']?.toString() ?? '0') ?? 0,
      correctionOf: json['correctionOf'] as String?,
    );
  }
}

class Step {
  final String mode;
  final String instruction;
  final String details;
  final bool is24_7;
  final String? startTime;
  final String? endTime;
  final double? actualFare;
  final String? alternateRouteSuggestion;

  /// Where passengers can board and get off along this step. Null for
  /// steps saved before this existed, treated as [StepBoarding.flexible].
  final StepBoarding? boarding;

  /// Recognised stops on this step; optional even when [boarding] is
  /// designated.
  final List<RouteStop> stops;

  /// The points the contributor's line passes through, in order (start,
  /// via points, end). Each piece between two of them was snapped or drawn
  /// on its own, so editing one point re-routes only its neighbouring
  /// pieces. Empty for steps saved before this existed.
  final List<LatLng> controlPoints;

  Step({
    required this.mode,
    required this.instruction,
    required this.details,
    this.is24_7 = true,
    this.startTime,
    this.endTime,
    this.actualFare,
    this.alternateRouteSuggestion,
    this.boarding,
    this.stops = const [],
    this.controlPoints = const [],
  });

  /// Default pickup rule for a new step of [mode]: buses, trains and FX/vans
  /// mostly stop at designated places; jeepneys and tricycles stop on
  /// request almost anywhere.
  static StepBoarding defaultBoardingFor(String mode) {
    switch (mode) {
      case 'Bus':
      case 'Train':
      case 'FX/Van':
        return StepBoarding.designated;
      default:
        return StepBoarding.flexible;
    }
  }

  /// Passengers can only board/get off at [stops] — or, when none are
  /// mapped yet, only at the step's two ends (its terminals). Trains always
  /// work this way. Steps saved before [boarding] existed stay flexible.
  bool get usesDesignatedStops =>
      mode == 'Train' || boarding == StepBoarding.designated;

  Step copyWith({
    String? instruction,
    String? details,
    StepBoarding? boarding,
    List<RouteStop>? stops,
    List<LatLng>? controlPoints,
  }) {
    return Step(
      mode: mode,
      instruction: instruction ?? this.instruction,
      details: details ?? this.details,
      is24_7: is24_7,
      startTime: startTime,
      endTime: endTime,
      actualFare: actualFare,
      alternateRouteSuggestion: alternateRouteSuggestion,
      boarding: boarding ?? this.boarding,
      stops: stops ?? this.stops,
      controlPoints: controlPoints ?? this.controlPoints,
    );
  }
}

enum StepBoarding {
  /// Board and get off anywhere along the line (flagging down a jeepney).
  flexible,

  /// Board and get off only at designated stops.
  designated;

  static StepBoarding? parse(dynamic value) {
    for (final v in StepBoarding.values) {
      if (v.name == value) return v;
    }
    return null;
  }
}

/// A recognised stop on a step. Its place along the route is worked out
/// from its coordinates, so editing the route's shape can't misplace it.
class RouteStop {
  final double lat;
  final double lng;
  final String name;
  final bool pickup;
  final bool dropoff;

  const RouteStop({
    required this.lat,
    required this.lng,
    required this.name,
    this.pickup = true,
    this.dropoff = true,
  });

  LatLng get point => LatLng(lat, lng);

  RouteStop copyWith({String? name, bool? pickup, bool? dropoff}) => RouteStop(
    lat: lat,
    lng: lng,
    name: name ?? this.name,
    pickup: pickup ?? this.pickup,
    dropoff: dropoff ?? this.dropoff,
  );

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'name': name,
    'pickup': pickup,
    'dropoff': dropoff,
  };

  static List<RouteStop> listFromJson(dynamic value) {
    if (value is! List) return const [];
    final stops = <RouteStop>[];
    for (final raw in value) {
      if (raw is! Map) continue;
      final lat = (raw['lat'] as num?)?.toDouble();
      final lng = (raw['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      stops.add(
        RouteStop(
          lat: lat,
          lng: lng,
          name: raw['name']?.toString() ?? '',
          pickup: raw['pickup'] as bool? ?? true,
          dropoff: raw['dropoff'] as bool? ?? true,
        ),
      );
    }
    return stops;
  }
}

class Report {
  final String type;
  final String? description;
  final DateTime timestamp;

  Report({required this.type, this.description, required this.timestamp});
}