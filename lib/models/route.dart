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
  final String? price;
  final String? schedule;
  final String? imageUrl;
  final List<Report> reports;
  final List<int> stepBoundaries;
  final String? contributorId;
  int views;
  int upvotes;
  int downvotes;
  bool bookmarked;

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
    this.schedule,
    this.imageUrl,
    this.reports = const [],
    this.stepBoundaries = const [],
    this.contributorId,
    this.views = 0,
    this.upvotes = 0,
    this.downvotes = 0,
    this.bookmarked = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startLocation': startLocation,
      'endLocation': endLocation,
      'shortDescription': shortDescription,
      'steps':
          steps
              .map(
                (s) => {
                  'mode': s.mode,
                  'instruction': s.instruction,
                  'details': s.details,
                },
              )
              .toList(),
      'startLat': startLat,
      'startLng': startLng,
      'endLat': endLat,
      'endLng': endLng,
      'pathPoints':
          pathPoints
              .map((p) => {'lat': p.latitude, 'lng': p.longitude})
              .toList(),
      'stepBoundaries': stepBoundaries,
      'eta': eta,
      'price': price,
      'schedule': schedule,
      'imageUrl': imageUrl,
      'reports':
          reports
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
      'bookmarked': bookmarked,
    };
  }

  factory Route.fromJson(Map<String, dynamic> json) {
    return Route(
      id: json['id'],
      startLocation: json['startLocation'],
      endLocation: json['endLocation'],
      shortDescription: json['shortDescription'],
      steps:
          (json['steps'] as List)
              .map(
                (s) => Step(
                  mode: s['mode'],
                  instruction: s['instruction'],
                  details: s['details'],
                ),
              )
              .toList(),
      startLat: json['startLat'],
      startLng: json['startLng'],
      endLat: json['endLat'],
      endLng: json['endLng'],
      pathPoints:
          (json['pathPoints'] as List)
              .map((p) => LatLng(p['lat'], p['lng']))
              .toList(),
      stepBoundaries:
          (json['stepBoundaries'] as List?)?.map((b) => b as int).toList() ??
          [],
      eta: json['eta'],
      price: json['price'],
      schedule: json['schedule'],
      imageUrl: json['imageUrl'],
      reports:
          (json['reports'] as List)
              .map(
                (r) => Report(
                  type: r['type'],
                  description: r['description'],
                  timestamp: DateTime.fromMillisecondsSinceEpoch(
                    r['timestamp'],
                  ),
                ),
              )
              .toList(),
      contributorId: json['contributorId'],
      views:
          json['views'] is int
              ? json['views']
              : int.tryParse(json['views']?.toString() ?? '0') ?? 0,
      upvotes:
          json['upvotes'] is int
              ? json['upvotes']
              : int.tryParse(json['upvotes']?.toString() ?? '0') ?? 0,
      downvotes:
          json['downvotes'] is int
              ? json['downvotes']
              : int.tryParse(json['downvotes']?.toString() ?? '0') ?? 0,
      bookmarked: json['bookmarked'] ?? false,
    );
  }
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
