import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// A rider's report of a problem on a route (fare hike, route changed,
/// cancelled service…), kept in Firestore `route_reports` so every route
/// on the same road shows it, not just the one it was filed on.
///
/// A report shows for a day ([expiresAt]); a moderator can keep it longer
/// ([kept]) or remove it.
class RouteIssueReport {
  final String id;
  final String routeId;

  /// "Start → End" of the route it was filed on.
  final String routeLabel;
  final String type;
  final String? description;
  final String reporterId;

  /// The reported route's line, for matching other routes on the same road.
  final List<LatLng> path;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool kept;

  const RouteIssueReport({
    required this.id,
    required this.routeId,
    required this.routeLabel,
    required this.type,
    this.description,
    required this.reporterId,
    required this.path,
    required this.createdAt,
    required this.expiresAt,
    this.kept = false,
  });

  bool get isActive => kept || expiresAt.isAfter(DateTime.now());

  factory RouteIssueReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    DateTime time(Object? value) =>
        value is Timestamp ? value.toDate() : DateTime.now();
    final points = data['path'] as List? ?? const [];
    return RouteIssueReport(
      id: doc.id,
      routeId: data['routeId'] as String? ?? '',
      routeLabel: data['routeLabel'] as String? ?? '',
      type: data['type'] as String? ?? 'Other',
      description: (data['description'] as String?)?.trim(),
      reporterId: data['reporterId'] as String? ?? '',
      path: [
        for (final p in points)
          if (p is Map && p['lat'] is num && p['lng'] is num)
            LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
      ],
      createdAt: time(data['createdAt']),
      expiresAt: time(data['expiresAt']),
      kept: data['kept'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'routeId': routeId,
    'routeLabel': routeLabel,
    'type': type,
    if (description != null && description!.isNotEmpty)
      'description': description,
    'reporterId': reporterId,
    'path': [
      for (final p in path) {'lat': p.latitude, 'lng': p.longitude},
    ],
    'createdAt': Timestamp.fromDate(createdAt),
    'expiresAt': Timestamp.fromDate(expiresAt),
    'kept': kept,
  };
}
