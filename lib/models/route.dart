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
              'alternateRouteSuggestion': s.alternateRouteSuggestion,
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
              alternateRouteSuggestion:
                  s['alternateRouteSuggestion'] as String?,
            ),
          )
          .toList(),
      startLat: json['startLat'],
      startLng: json['startLng'],
      endLat: json['endLat'],
      endLng: json['endLng'],
      pathPoints: (json['pathPoints'] as List)
          .map((p) => LatLng(p['lat'], p['lng']))
          .toList(),
      stepBoundaries:
          (json['stepBoundaries'] as List?)?.map((b) => b as int).toList() ??
          [],
      eta: json['eta'],
      price: json['price'],
      distance: json['distance'],
      schedule: json['schedule'],
      imageUrl: json['imageUrl'],
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
  final String? alternateRouteSuggestion;

  Step({
    required this.mode,
    required this.instruction,
    required this.details,
    this.is24_7 = true,
    this.startTime,
    this.endTime,
    this.alternateRouteSuggestion,
  });
}

class Report {
  final String type;
  final String? description;
  final DateTime timestamp;

  Report({required this.type, this.description, required this.timestamp});
}