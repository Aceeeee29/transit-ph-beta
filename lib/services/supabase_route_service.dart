import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseRouteService {
  static final _client = Supabase.instance.client;

  // ── Find nearest stop to a LatLng ─────────────────────────────────────────
  static Future<Map<String, dynamic>?> findNearestStop(
    LatLng point, {
    double radiusKm = 0.5,
  }) async {
    // Bounding box search first (Supabase doesn't have native geo queries)
    final latDelta = radiusKm / 111.0;
    final lngDelta = radiusKm / (111.0 * math.cos(point.latitude * math.pi / 180));

    final results = await _client
        .from('stops')
        .select('stop_id, stop_name, stop_lat, stop_lon')
        .gte('stop_lat', point.latitude - latDelta)
        .lte('stop_lat', point.latitude + latDelta)
        .gte('stop_lon', point.longitude - lngDelta)
        .lte('stop_lon', point.longitude + lngDelta);

    if (results.isEmpty) return null;

    // Find the actual closest by haversine
    results.sort((a, b) {
      final distA = _haversineKm(
        point, LatLng(a['stop_lat'], a['stop_lon']));
      final distB = _haversineKm(
        point, LatLng(b['stop_lat'], b['stop_lon']));
      return distA.compareTo(distB);
    });

    return results.first;
  }

  // ── Find trips connecting two stops ───────────────────────────────────────
  static Future<List<Map<String, dynamic>>> findTripsBetween(
    String originStopId,
    String destStopId,
  ) async {
    // Get all trips + sequences for origin stop
    final originTimes = await _client
        .from('stop_times')
        .select('trip_id, stop_sequence')
        .eq('stop_id', originStopId);

    if (originTimes.isEmpty) return [];

    final tripIds = originTimes.map((e) => e['trip_id'].toString()).toList();
    final originSeqMap = {
      for (var t in originTimes)
        t['trip_id'].toString(): t['stop_sequence'] as int
    };

    // Get matching trips that also serve dest stop
    final destTimes = await _client
        .from('stop_times')
        .select('trip_id, stop_sequence')
        .eq('stop_id', destStopId)
        .inFilter('trip_id', tripIds);

    // Filter: dest sequence must be AFTER origin sequence
    final validTripIds = destTimes
        .where((d) =>
            (d['stop_sequence'] as int) >
            (originSeqMap[d['trip_id'].toString()] ?? 0))
        .map((d) => d['trip_id'].toString())
        .toList();

    if (validTripIds.isEmpty) return [];

    // Get route info for valid trips
    final trips = await _client
        .from('trips')
        .select('trip_id, route_id, shape_id, direction_id')
        .inFilter('trip_id', validTripIds);

    final routeIds = trips.map((t) => t['route_id'].toString()).toSet().toList();

    final routes = await _client
        .from('routes')
        .select('route_id, route_short_name, route_long_name, route_color, route_type')
        .inFilter('route_id', routeIds);

    final routeMap = {for (var r in routes) r['route_id'].toString(): r};

    // Combine trip + route info
    return trips.map((t) {
      final route = routeMap[t['route_id'].toString()] ?? {};
      return {
        ...t,
        'route_short_name': route['route_short_name'],
        'route_long_name':  route['route_long_name'],
        'route_color':      route['route_color'],
        'route_type':       route['route_type'],
      };
    }).toList();
  }

  // ── Get shape polyline for a trip ─────────────────────────────────────────
  static Future<List<LatLng>> getShapePolyline(String shapeId) async {
    final points = await _client
        .from('shapes')
        .select('shape_pt_lat, shape_pt_lon, shape_pt_sequence')
        .eq('shape_id', shapeId)
        .order('shape_pt_sequence');

    return points
        .map((p) => LatLng(
              (p['shape_pt_lat'] as num).toDouble(),
              (p['shape_pt_lon'] as num).toDouble(),
            ))
        .toList();
  }

  // ── Get all stops along a trip ────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getStopsForTrip(
      String tripId) async {
    final stopTimes = await _client
        .from('stop_times')
        .select('stop_id, stop_sequence, arrival_time, departure_time')
        .eq('trip_id', tripId)
        .order('stop_sequence');

    final stopIds = stopTimes.map((s) => s['stop_id'].toString()).toList();

    final stops = await _client
        .from('stops')
        .select('stop_id, stop_name, stop_lat, stop_lon')
        .inFilter('stop_id', stopIds);

    final stopMap = {for (var s in stops) s['stop_id'].toString(): s};

    return stopTimes.map((st) {
      final stop = stopMap[st['stop_id'].toString()] ?? {};
      return {
        ...st,
        'stop_name': stop['stop_name'],
        'stop_lat':  stop['stop_lat'],
        'stop_lon':  stop['stop_lon'],
      };
    }).toList();
  }

  // ── Haversine helper ──────────────────────────────────────────────────────
  static double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}