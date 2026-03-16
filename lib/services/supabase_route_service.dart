import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A single vehicle ride between two stops.
class TransitLeg {
  final String tripId;
  final String routeId;
  final String? shapeId;
  final String? routeShortName;
  final String? routeLongName;
  final String? routeColor;
  final int?    routeType;
  final String  boardStopId;
  final String  alightStopId;
  final String  boardStopName;
  final String  alightStopName;
  final double  boardLat;
  final double  boardLon;
  final double  alightLat;
  final double  alightLon;

  const TransitLeg({
    required this.tripId,
    required this.routeId,
    this.shapeId,
    this.routeShortName,
    this.routeLongName,
    this.routeColor,
    this.routeType,
    required this.boardStopId,
    required this.alightStopId,
    required this.boardStopName,
    required this.alightStopName,
    required this.boardLat,
    required this.boardLon,
    required this.alightLat,
    required this.alightLon,
  });
}

/// 1 leg = direct, 2 legs = one transfer.
class TripPlan {
  final List<TransitLeg> legs;
  const TripPlan(this.legs);
  bool get isDirect    => legs.length == 1;
  bool get hasTransfer => legs.length == 2;
}

class SupabaseRouteService {
  static final _client = Supabase.instance.client;

  // ── Find nearest stop to a LatLng ─────────────────────────────────────────
  static Future<Map<String, dynamic>?> findNearestStop(
    LatLng point, {
    double radiusKm = 0.5,
  }) async {
    final latDelta = radiusKm / 111.0;
    final lngDelta =
        radiusKm / (111.0 * math.cos(point.latitude * math.pi / 180));

    final results = await _client
        .from('stops')
        .select('stop_id, stop_name, stop_lat, stop_lon')
        .gte('stop_lat', point.latitude - latDelta)
        .lte('stop_lat', point.latitude + latDelta)
        .gte('stop_lon', point.longitude - lngDelta)
        .lte('stop_lon', point.longitude + lngDelta);

    if (results.isEmpty) return null;

    results.sort((a, b) {
      final dA = _haversineKm(point, LatLng(a['stop_lat'], a['stop_lon']));
      final dB = _haversineKm(point, LatLng(b['stop_lat'], b['stop_lon']));
      return dA.compareTo(dB);
    });

    return results.first;
  }

  // ── Find a trip plan via Supabase RPC (server-side, no row-limit issues) ──
  //
  // Calls the `find_trip_plan` PostgreSQL function which handles both
  // direct and 1-transfer routing entirely in the DB.
  static Future<TripPlan?> findTripPlan(
    String originStopId,
    String destStopId,
  ) async {
    debugPrint('[SupabaseRouteService] findTripPlan: "$originStopId" → "$destStopId"');

    final response = await _client.rpc('find_trip_plan', params: {
      'origin_stop_id': originStopId,
      'dest_stop_id':   destStopId,
    });

    if (response == null) {
      debugPrint('[SupabaseRouteService] RPC returned null — no route found');
      return null;
    }

    final data = Map<String, dynamic>.from(response as Map);
    final type = data['type'] as String?;

    debugPrint('[SupabaseRouteService] RPC result type: $type');

    if (type == 'direct') {
      final leg = await _buildLeg(
        tripId:      data['leg1_trip_id'].toString(),
        boardStopId: originStopId,
        alightStopId: destStopId,
      );
      if (leg == null) return null;
      debugPrint('[SupabaseRouteService] Direct route ✓');
      return TripPlan([leg]);
    }

    if (type == 'transfer') {
      final transferStopId = data['transfer_stop_id'].toString();
      debugPrint('[SupabaseRouteService] Transfer via stop: $transferStopId');

      final leg1 = await _buildLeg(
        tripId:      data['leg1_trip_id'].toString(),
        boardStopId: originStopId,
        alightStopId: transferStopId,
      );
      final leg2 = await _buildLeg(
        tripId:      data['leg2_trip_id'].toString(),
        boardStopId: transferStopId,
        alightStopId: destStopId,
      );

      if (leg1 == null || leg2 == null) return null;
      debugPrint('[SupabaseRouteService] Transfer route ✓');
      return TripPlan([leg1, leg2]);
    }

    return null;
  }

  // ── Build a single TransitLeg ──────────────────────────────────────────────
  static Future<TransitLeg?> _buildLeg({
    required String tripId,
    required String boardStopId,
    required String alightStopId,
  }) async {
    final tripRow = await _client
        .from('trips')
        .select('trip_id, route_id, shape_id')
        .eq('trip_id', tripId)
        .maybeSingle();

    if (tripRow == null) return null;

    final routeId = tripRow['route_id'].toString();
    final shapeId = tripRow['shape_id']?.toString();

    final stopRows = await _client
        .from('stops')
        .select('stop_id, stop_name, stop_lat, stop_lon')
        .inFilter('stop_id', [boardStopId, alightStopId]);

    final routeRow = await _client
        .from('routes')
        .select('route_id, route_short_name, route_long_name, route_color, route_type')
        .eq('route_id', routeId)
        .maybeSingle();

    Map<String, dynamic>? boardStop, alightStop;
    for (final s in stopRows) {
      if (s['stop_id'].toString() == boardStopId)  boardStop  = Map.from(s);
      if (s['stop_id'].toString() == alightStopId) alightStop = Map.from(s);
    }

    if (boardStop == null || alightStop == null) {
      debugPrint('[SupabaseRouteService] Could not find stop coords for leg $tripId');
      return null;
    }

    return TransitLeg(
      tripId:         tripId,
      routeId:        routeId,
      shapeId:        shapeId,
      routeShortName: routeRow?['route_short_name'] as String?,
      routeLongName:  routeRow?['route_long_name']  as String?,
      routeColor:     routeRow?['route_color']       as String?,
      routeType:      routeRow?['route_type']        as int?,
      boardStopId:    boardStopId,
      alightStopId:   alightStopId,
      boardStopName:  boardStop['stop_name']  as String? ?? 'Stop',
      alightStopName: alightStop['stop_name'] as String? ?? 'Stop',
      boardLat:  (boardStop['stop_lat']  as num).toDouble(),
      boardLon:  (boardStop['stop_lon']  as num).toDouble(),
      alightLat: (alightStop['stop_lat'] as num).toDouble(),
      alightLon: (alightStop['stop_lon'] as num).toDouble(),
    );
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

  // ── Helpers ───────────────────────────────────────────────────────────────
  static double _haversineKm(LatLng a, LatLng b) {
    const r    = 6371.0;
    final dLat = _rad(b.latitude  - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final x    = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}