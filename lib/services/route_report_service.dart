import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/notification.dart';
import '../models/route_issue_report.dart';
import 'notifications_service.dart';
import 'route_service.dart';

/// Route reports, shared by everyone: a report filed on one route shows on
/// every route and generated trip that rides the same road, and the riders
/// who contributed those routes are told.
class RouteReportService {
  RouteReportService._();

  static const collection = 'route_reports';

  /// How long a report shows unless a moderator keeps it.
  static const lifetime = Duration(days: 1);

  /// Road two routes must share for a report on one to show on the other.
  static const minSharedMeters = 300.0;

  /// A point of a route this close to the reported line is on the same road.
  static const _sameRoadMeters = 30.0;

  /// Points kept of a reported line (the stored copy).
  static const _maxStoredPoints = 300;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static List<RouteIssueReport>? _active;
  static DateTime _activeAt = DateTime(0);

  /// Files a report on the route [routeId] (line [path]) and tells the
  /// contributors of the routes that share its road.
  static Future<RouteIssueReport> submit({
    required String routeId,
    required String routeLabel,
    required List<LatLng> path,
    required String type,
    String? description,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to report a route.');
    final now = DateTime.now();
    final doc = _db.collection(collection).doc();
    final report = RouteIssueReport(
      id: doc.id,
      routeId: routeId,
      routeLabel: routeLabel,
      type: type,
      description: description,
      reporterId: uid,
      path: _thin(path, _maxStoredPoints),
      createdAt: now,
      expiresAt: now.add(lifetime),
    );
    await doc.set(report.toJson());
    _active = [...?_active, report];
    // Telling contributors must not hold up (or undo) the report.
    unawaited(_notifyContributors(report));
    return report;
  }

  /// Reports still showing: under a day old, or kept by a moderator.
  static Future<List<RouteIssueReport>> active({bool refresh = false}) async {
    final cached = _active;
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(_activeAt) < const Duration(minutes: 2)) {
      return cached.where((r) => r.isActive).toList();
    }
    try {
      final snapshot =
          await _db
              .collection(collection)
              .where('expiresAt', isGreaterThan: Timestamp.now())
              .get();
      final reports = snapshot.docs.map(RouteIssueReport.fromDoc).toList();
      _active = reports;
      _activeAt = DateTime.now();
      return reports;
    } catch (e) {
      debugPrint('[RouteReports] Load failed: $e');
      return cached?.where((r) => r.isActive).toList() ?? const [];
    }
  }

  /// Active reports on the road [path] rides, newest first.
  static Future<List<RouteIssueReport>> affecting(List<LatLng> path) async {
    if (path.length < 2) return const [];
    final reports = await active();
    return reportsOnRoad(path, reports);
  }

  /// [reports] whose line shares at least [minSharedMeters] of road with
  /// [path], newest first.
  @visibleForTesting
  static List<RouteIssueReport> reportsOnRoad(
    List<LatLng> path,
    List<RouteIssueReport> reports,
  ) {
    final found = [
      for (final r in reports)
        if (r.isActive && sharedMeters(path, r.path) >= minSharedMeters) r,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return found;
  }

  /// For moderators: every report still showing, as it changes.
  static Stream<List<RouteIssueReport>> watchActive() {
    return _db
        .collection(collection)
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .snapshots()
        .map(
          (s) =>
              s.docs.map(RouteIssueReport.fromDoc).toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  /// Moderator: keep showing until removed.
  static Future<void> keep(String id) async {
    await _db.collection(collection).doc(id).update({
      'kept': true,
      'expiresAt': Timestamp.fromDate(DateTime(2100)),
    });
    _active = null;
  }

  /// Moderator: stop showing it now.
  static Future<void> remove(String id) async {
    await _db.collection(collection).doc(id).delete();
    _active = null;
  }

  // ─── Same road ─────────────────────────────────────────────────────────────

  /// How much of [route] (meters, along it) runs on [reported]'s road.
  static double sharedMeters(List<LatLng> route, List<LatLng> reported) {
    if (route.length < 2 || reported.length < 2) return 0;
    final box = _Box.around(reported, _sameRoadMeters);
    var shared = 0.0;
    for (var i = 0; i < route.length - 1; i++) {
      final a = route[i];
      final b = route[i + 1];
      final length = _meters(a, b);
      if (length == 0) continue;
      // Sampled about every 25 m, so long straight pieces count properly.
      final pieces = math.max(1, (length / 25).ceil());
      final piece = length / pieces;
      for (var k = 0; k < pieces; k++) {
        final t = (k + 0.5) / pieces;
        final p = LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        );
        if (box.contains(p) && _nearLine(p, reported, _sameRoadMeters)) {
          shared += piece;
        }
      }
    }
    return shared;
  }

  static bool _nearLine(LatLng p, List<LatLng> line, double meters) {
    for (var i = 0; i < line.length - 1; i++) {
      if (_toSegmentMeters(p, line[i], line[i + 1]) <= meters) return true;
    }
    return false;
  }

  /// Meters from [p] to the segment [a]–[b] (flat-earth, fine at city size).
  static double _toSegmentMeters(LatLng p, LatLng a, LatLng b) {
    final cos = math.cos(p.latitude * math.pi / 180);
    double x(LatLng q) => q.longitude * 111320 * cos;
    double y(LatLng q) => q.latitude * 110540;
    final ax = x(a), ay = y(a), bx = x(b), by = y(b), px = x(p), py = y(p);
    final dx = bx - ax, dy = by - ay;
    final lengthSq = dx * dx + dy * dy;
    var t = lengthSq == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / lengthSq;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
  }

  static double _meters(LatLng a, LatLng b) =>
      const Distance().as(LengthUnit.Meter, a, b);

  /// At most [max] of [path]'s points, ends kept.
  static List<LatLng> _thin(List<LatLng> path, int max) {
    if (path.length <= max) return path;
    final step = (path.length - 1) / (max - 1);
    return [for (var i = 0; i < max; i++) path[(i * step).round()]];
  }

  // ─── Contributors ──────────────────────────────────────────────────────────

  static Future<void> _notifyContributors(RouteIssueReport report) async {
    try {
      final routes = await RouteService.getAllRoutes();
      for (final route in routes) {
        final contributor = route.contributorId;
        if (contributor == null ||
            contributor.isEmpty ||
            contributor == report.reporterId) {
          continue;
        }
        final onRoad =
            route.id == report.routeId ||
            sharedMeters(route.pathPoints, report.path) >= minSharedMeters;
        if (!onRoad) continue;
        final label = '${route.startLocation} → ${route.endLocation}';
        await NotificationsService.addNotification(
          NotificationModel(
            id: '${report.id}_${route.id}',
            userId: contributor,
            type: 'route_reported',
            routeId: route.id,
            fromUserId: report.reporterId,
            timestamp: DateTime.now(),
            message:
                route.id == report.routeId
                    ? 'A rider reported "${report.type}" on your route $label.'
                    : 'A rider reported "${report.type}" on ${report.routeLabel}, '
                        'which shares the road with your route $label.',
          ),
        );
      }
    } catch (e) {
      debugPrint('[RouteReports] Notifying contributors failed: $e');
    }
  }
}

class _Box {
  final double minLat, maxLat, minLng, maxLng;
  const _Box(this.minLat, this.maxLat, this.minLng, this.maxLng);

  factory _Box.around(List<LatLng> points, double meters) {
    var minLat = points.first.latitude, maxLat = minLat;
    var minLng = points.first.longitude, maxLng = minLng;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    final dLat = meters / 110540;
    final dLng = meters / (111320 * math.cos(minLat * math.pi / 180));
    return _Box(minLat - dLat, maxLat + dLat, minLng - dLng, maxLng + dLng);
  }

  bool contains(LatLng p) =>
      p.latitude >= minLat &&
      p.latitude <= maxLat &&
      p.longitude >= minLng &&
      p.longitude <= maxLng;
}
