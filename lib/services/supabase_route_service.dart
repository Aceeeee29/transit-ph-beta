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

class DijkstraTripPlanResult {
  final TripPlan plan;
  final Map<String, dynamic> selectedOriginStop;
  final Map<String, dynamic> selectedDestStop;
  final double totalCostSeconds;

  const DijkstraTripPlanResult({
    required this.plan,
    required this.selectedOriginStop,
    required this.selectedDestStop,
    required this.totalCostSeconds,
  });
}

class _GraphEdge {
  final String from;
  final String to;
  final double costSeconds;
  final bool isWalk;
  final String? tripId;
  final String? routeId;
  final String? shapeId;
  final String? routeShortName;
  final String? routeLongName;
  final String? routeColor;
  final int? routeType;

  const _GraphEdge({
    required this.from,
    required this.to,
    required this.costSeconds,
    required this.isWalk,
    this.tripId,
    this.routeId,
    this.shapeId,
    this.routeShortName,
    this.routeLongName,
    this.routeColor,
    this.routeType,
  });
}

class _QueueNode {
  final String node;
  final double cost;

  const _QueueNode(this.node, this.cost);
}

class _MinHeap {
  final List<_QueueNode> _data = [];

  bool get isEmpty => _data.isEmpty;

  void add(_QueueNode value) {
    _data.add(value);
    _bubbleUp(_data.length - 1);
  }

  _QueueNode pop() {
    final top = _data.first;
    final last = _data.removeLast();
    if (_data.isNotEmpty) {
      _data[0] = last;
      _bubbleDown(0);
    }
    return top;
  }

  void _bubbleUp(int index) {
    var i = index;
    while (i > 0) {
      final p = (i - 1) ~/ 2;
      if (_data[p].cost <= _data[i].cost) break;
      final tmp = _data[p];
      _data[p] = _data[i];
      _data[i] = tmp;
      i = p;
    }
  }

  void _bubbleDown(int index) {
    var i = index;
    while (true) {
      final left = i * 2 + 1;
      final right = left + 1;
      var smallest = i;

      if (left < _data.length && _data[left].cost < _data[smallest].cost) {
        smallest = left;
      }
      if (right < _data.length && _data[right].cost < _data[smallest].cost) {
        smallest = right;
      }
      if (smallest == i) break;

      final tmp = _data[i];
      _data[i] = _data[smallest];
      _data[smallest] = tmp;
      i = smallest;
    }
  }
}

class SupabaseRouteService {
  static final _client = Supabase.instance.client;

  static const _maxNearestStopsLimit = 12;
  static const _pageSize = 1000;
  static const _originNode = '__origin__';
  static const _destNode = '__dest__';

  static const _dijkstraMinBufferKm = 2.0;
  static const _dijkstraMaxBufferKm = 8.0;
  static const _dijkstraStopLimit = 900;
  static const _walkSpeedKmh = 5.0;
  static const _transferRadiusKm = 0.25;
  static const _transferBasePenaltySec = 90.0;
  static const _maxAccessWalkKm = 1.4;
  static const _boardingPenaltySec = 180.0;
  static const _maxRideStopsSpan = 30;

  static const _inFilterChunk = 250;

  static const _fallbackTransitSpeedKmh = 20.0;

  static Future<DijkstraTripPlanResult?> findTripPlanDijkstra({
    required LatLng origin,
    required LatLng destination,
    required List<Map<String, dynamic>> originCandidates,
    required List<Map<String, dynamic>> destCandidates,
    bool allowFerry = false,
  }) async {
    if (originCandidates.isEmpty || destCandidates.isEmpty) return null;

    final corridorStops = await _fetchCorridorStops(origin, destination);
    if (corridorStops.isEmpty) return null;

    final allStopsById = <String, Map<String, dynamic>>{};
    for (final stop in corridorStops) {
      allStopsById[stop['stop_id'].toString()] = stop;
    }
    for (final stop in originCandidates) {
      allStopsById[stop['stop_id'].toString()] = stop;
    }
    for (final stop in destCandidates) {
      allStopsById[stop['stop_id'].toString()] = stop;
    }

    final stopIds = allStopsById.keys.toList();
    if (stopIds.isEmpty) return null;

    final stopTimes = await _fetchStopTimesForStopIds(stopIds);
    if (stopTimes.isEmpty) return null;

    final tripIds = stopTimes
        .map((r) => r['trip_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();
    if (tripIds.isEmpty) return null;

    final tripRows = await _fetchTripsByIds(tripIds);
    if (tripRows.isEmpty) return null;

    final routeIds = tripRows
        .map((r) => r['route_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();
    final routeRows = await _fetchRoutesByIds(routeIds);

    final tripById = <String, Map<String, dynamic>>{};
    for (final row in tripRows) {
      tripById[row['trip_id'].toString()] = row;
    }

    final routeById = <String, Map<String, dynamic>>{};
    for (final row in routeRows) {
      routeById[row['route_id'].toString()] = row;
    }

    final stopTimesByTrip = <String, List<Map<String, dynamic>>>{};
    for (final row in stopTimes) {
      final tripId = row['trip_id']?.toString();
      final stopId = row['stop_id']?.toString();
      if (tripId == null || stopId == null) continue;
      if (!allStopsById.containsKey(stopId)) continue;
      stopTimesByTrip.putIfAbsent(tripId, () => []).add(row);
    }

    final adjacency = <String, List<_GraphEdge>>{};

    void addEdge(_GraphEdge edge) {
      adjacency.putIfAbsent(edge.from, () => []).add(edge);
    }

    for (final entry in stopTimesByTrip.entries) {
      final tripId = entry.key;
      final seq = entry.value;
      seq.sort((a, b) => _asInt(a['stop_sequence']).compareTo(_asInt(b['stop_sequence'])));
      if (seq.length < 2) continue;

      final trip = tripById[tripId];
      if (trip == null) continue;
      final routeId = trip['route_id']?.toString();
      final route = routeId != null ? routeById[routeId] : null;
      final inferredMode = _inferRouteMode(
        routeType: route?['route_type'] as int?,
        routeShortName: route?['route_short_name'] as String?,
        routeLongName: route?['route_long_name'] as String?,
      );
      if (!allowFerry && inferredMode == 'Ferry') {
        continue;
      }
      final fallbackSpeedKmh = _fallbackSpeedForMode(inferredMode);

      // Build segment travel times between adjacent stops.
      final segmentSeconds = <double>[];
      for (var i = 0; i < seq.length - 1; i++) {
        final a = seq[i];
        final b = seq[i + 1];
        final fromId = a['stop_id']?.toString();
        final toId = b['stop_id']?.toString();
        if (fromId == null || toId == null) {
          segmentSeconds.add(double.infinity);
          continue;
        }

        final fromStop = allStopsById[fromId];
        final toStop = allStopsById[toId];
        if (fromStop == null || toStop == null) {
          segmentSeconds.add(double.infinity);
          continue;
        }

        var segSec = _gtfsTimeDiffSeconds(
          a['departure_time']?.toString(),
          b['arrival_time']?.toString(),
        );

        if (segSec <= 0 || segSec > 7200) {
          final segKm = _haversineKm(
            LatLng((fromStop['stop_lat'] as num).toDouble(), (fromStop['stop_lon'] as num).toDouble()),
            LatLng((toStop['stop_lat'] as num).toDouble(), (toStop['stop_lon'] as num).toDouble()),
          );
          segSec = ((segKm / fallbackSpeedKmh) * 3600).clamp(20, 2400);
        }
        segmentSeconds.add(segSec);
      }

      // Prefix sum for O(1) cumulative segment cost lookup.
      final prefix = List<double>.filled(segmentSeconds.length + 1, 0.0);
      for (var i = 0; i < segmentSeconds.length; i++) {
        prefix[i + 1] = prefix[i] + segmentSeconds[i];
      }

      // Add ride edges from each stop to downstream stops on the same trip.
      // Boarding penalty is applied once per chosen trip edge, discouraging
      // excessive transfers while still allowing them when truly beneficial.
      for (var i = 0; i < seq.length - 1; i++) {
        final fromId = seq[i]['stop_id']?.toString();
        if (fromId == null) continue;

        final maxJ = math.min(seq.length - 1, i + _maxRideStopsSpan);
        for (var j = i + 1; j <= maxJ; j++) {
          final toId = seq[j]['stop_id']?.toString();
          if (toId == null || toId == fromId) continue;

          final runSec = prefix[j] - prefix[i];
          if (!runSec.isFinite || runSec <= 0) continue;

          addEdge(_GraphEdge(
            from: fromId,
            to: toId,
            costSeconds: runSec + _boardingPenaltySec,
            isWalk: false,
            tripId: tripId,
            routeId: routeId,
            shapeId: trip['shape_id']?.toString(),
            routeShortName: route?['route_short_name'] as String?,
            routeLongName: route?['route_long_name'] as String?,
            routeColor: route?['route_color'] as String?,
            routeType: route?['route_type'] as int?,
          ));
        }
      }
    }

    final stopList = allStopsById.values.toList();
    for (var i = 0; i < stopList.length; i++) {
      final a = stopList[i];
      final aId = a['stop_id'].toString();
      final aPt = LatLng((a['stop_lat'] as num).toDouble(), (a['stop_lon'] as num).toDouble());

      for (var j = i + 1; j < stopList.length; j++) {
        final b = stopList[j];
        final bId = b['stop_id'].toString();
        final bPt = LatLng((b['stop_lat'] as num).toDouble(), (b['stop_lon'] as num).toDouble());
        final dKm = _haversineKm(aPt, bPt);
        if (dKm > _transferRadiusKm) continue;

        final walkSec = (dKm / _walkSpeedKmh) * 3600 + _transferBasePenaltySec;
        addEdge(_GraphEdge(from: aId, to: bId, costSeconds: walkSec, isWalk: true));
        addEdge(_GraphEdge(from: bId, to: aId, costSeconds: walkSec, isWalk: true));
      }
    }

    final originCandidateIds = originCandidates
        .map((s) => s['stop_id']?.toString())
        .whereType<String>()
        .toSet();
    final destCandidateIds = destCandidates
        .map((s) => s['stop_id']?.toString())
        .whereType<String>()
        .toSet();

    for (final stop in stopList) {
      final stopId = stop['stop_id'].toString();
      final pt = LatLng((stop['stop_lat'] as num).toDouble(), (stop['stop_lon'] as num).toDouble());

      final walkInKm = _haversineKm(origin, pt);
      if (walkInKm <= _maxAccessWalkKm || originCandidateIds.contains(stopId)) {
        addEdge(_GraphEdge(
          from: _originNode,
          to: stopId,
          costSeconds: (walkInKm / _walkSpeedKmh) * 3600,
          isWalk: true,
        ));
      }

      final walkOutKm = _haversineKm(pt, destination);
      if (walkOutKm <= _maxAccessWalkKm || destCandidateIds.contains(stopId)) {
        addEdge(_GraphEdge(
          from: stopId,
          to: _destNode,
          costSeconds: (walkOutKm / _walkSpeedKmh) * 3600,
          isWalk: true,
        ));
      }
    }

    final dijkstra = _runDijkstra(adjacency, _originNode, _destNode);
    if (dijkstra == null) return null;

    final pathEdges = dijkstra.$1;
    final totalCostSeconds = dijkstra.$2;

    final transitEdges = pathEdges.where((e) => !e.isWalk && e.tripId != null).toList();
    if (transitEdges.isEmpty) return null;

    final legs = <TransitLeg>[];
    var startEdge = transitEdges.first;
    var endEdge = transitEdges.first;

    for (var i = 1; i < transitEdges.length; i++) {
      final e = transitEdges[i];
      if (e.tripId == endEdge.tripId) {
        endEdge = e;
        continue;
      }
      final leg = _legFromEdges(startEdge, endEdge, allStopsById);
      if (leg != null) legs.add(leg);
      startEdge = e;
      endEdge = e;
    }
    final lastLeg = _legFromEdges(startEdge, endEdge, allStopsById);
    if (lastLeg != null) legs.add(lastLeg);

    if (legs.isEmpty) return null;

    final selectedOriginStop = allStopsById[legs.first.boardStopId];
    final selectedDestStop = allStopsById[legs.last.alightStopId];
    if (selectedOriginStop == null || selectedDestStop == null) return null;

    return DijkstraTripPlanResult(
      plan: TripPlan(legs),
      selectedOriginStop: selectedOriginStop,
      selectedDestStop: selectedDestStop,
      totalCostSeconds: totalCostSeconds,
    );
  }

  static TransitLeg? _legFromEdges(
    _GraphEdge start,
    _GraphEdge end,
    Map<String, Map<String, dynamic>> stopById,
  ) {
    final boardStop = stopById[start.from];
    final alightStop = stopById[end.to];
    if (boardStop == null || alightStop == null || start.tripId == null || start.routeId == null) {
      return null;
    }

    return TransitLeg(
      tripId: start.tripId!,
      routeId: start.routeId!,
      shapeId: start.shapeId,
      routeShortName: start.routeShortName,
      routeLongName: start.routeLongName,
      routeColor: start.routeColor,
      routeType: start.routeType,
      boardStopId: start.from,
      alightStopId: end.to,
      boardStopName: boardStop['stop_name'] as String? ?? 'Stop',
      alightStopName: alightStop['stop_name'] as String? ?? 'Stop',
      boardLat: (boardStop['stop_lat'] as num).toDouble(),
      boardLon: (boardStop['stop_lon'] as num).toDouble(),
      alightLat: (alightStop['stop_lat'] as num).toDouble(),
      alightLon: (alightStop['stop_lon'] as num).toDouble(),
    );
  }

  static (List<_GraphEdge>, double)? _runDijkstra(
    Map<String, List<_GraphEdge>> adjacency,
    String start,
    String target,
  ) {
    final dist = <String, double>{start: 0.0};
    final prev = <String, _GraphEdge>{};
    final heap = _MinHeap()..add(const _QueueNode(_originNode, 0.0));

    while (!heap.isEmpty) {
      final current = heap.pop();
      final best = dist[current.node];
      if (best == null || current.cost > best) continue;
      if (current.node == target) break;

      final edges = adjacency[current.node] ?? const <_GraphEdge>[];
      for (final edge in edges) {
        final nextCost = current.cost + edge.costSeconds;
        final known = dist[edge.to];
        if (known == null || nextCost < known) {
          dist[edge.to] = nextCost;
          prev[edge.to] = edge;
          heap.add(_QueueNode(edge.to, nextCost));
        }
      }
    }

    final total = dist[target];
    if (total == null) return null;

    final reversed = <_GraphEdge>[];
    var node = target;
    while (node != start) {
      final edge = prev[node];
      if (edge == null) return null;
      reversed.add(edge);
      node = edge.from;
    }

    return (reversed.reversed.toList(), total);
  }

  static Future<List<Map<String, dynamic>>> _fetchCorridorStops(
    LatLng origin,
    LatLng destination,
  ) async {
    final directKm = _haversineKm(origin, destination);
    final bufferKm = (directKm * 0.35).clamp(_dijkstraMinBufferKm, _dijkstraMaxBufferKm);
    final latBuffer = bufferKm / 111.0;
    final avgLat = (origin.latitude + destination.latitude) / 2;
    final lngBuffer = bufferKm / (111.0 * math.cos(avgLat * math.pi / 180));

    final minLat = math.min(origin.latitude, destination.latitude) - latBuffer;
    final maxLat = math.max(origin.latitude, destination.latitude) + latBuffer;
    final minLng = math.min(origin.longitude, destination.longitude) - lngBuffer;
    final maxLng = math.max(origin.longitude, destination.longitude) + lngBuffer;

    final out = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final rows = await _client
          .from('stops')
          .select('stop_id, stop_name, stop_lat, stop_lon')
          .gte('stop_lat', minLat)
          .lte('stop_lat', maxLat)
          .gte('stop_lon', minLng)
          .lte('stop_lon', maxLng)
          .range(from, from + _pageSize - 1);

      final mapped = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      out.addAll(mapped);
      if (mapped.length < _pageSize) break;
      if (out.length >= _dijkstraStopLimit) break;
      from += _pageSize;
    }

    if (out.length <= _dijkstraStopLimit) return out;

    out.sort((a, b) {
      final aPt = LatLng((a['stop_lat'] as num).toDouble(), (a['stop_lon'] as num).toDouble());
      final bPt = LatLng((b['stop_lat'] as num).toDouble(), (b['stop_lon'] as num).toDouble());
      final da = _haversineKm(origin, aPt) + _haversineKm(aPt, destination);
      final db = _haversineKm(origin, bPt) + _haversineKm(bPt, destination);
      return da.compareTo(db);
    });
    return out.take(_dijkstraStopLimit).toList();
  }

  static Future<List<Map<String, dynamic>>> _fetchStopTimesForStopIds(
    List<String> stopIds,
  ) async {
    final out = <Map<String, dynamic>>[];

    for (var i = 0; i < stopIds.length; i += _inFilterChunk) {
      final chunk = stopIds.sublist(
        i,
        math.min(i + _inFilterChunk, stopIds.length),
      );

      var from = 0;
      while (true) {
        final rows = await _client
            .from('stop_times')
            .select('trip_id, stop_id, stop_sequence, arrival_time, departure_time')
            .inFilter('stop_id', chunk)
            .range(from, from + _pageSize - 1);

        final mapped = rows.map((r) => Map<String, dynamic>.from(r)).toList();
        out.addAll(mapped);
        if (mapped.length < _pageSize) break;
        from += _pageSize;
      }
    }

    return out;
  }

  static Future<List<Map<String, dynamic>>> _fetchTripsByIds(
    List<String> tripIds,
  ) async {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < tripIds.length; i += _inFilterChunk) {
      final chunk = tripIds.sublist(i, math.min(i + _inFilterChunk, tripIds.length));
      final rows = await _client
          .from('trips')
          .select('trip_id, route_id, shape_id')
          .inFilter('trip_id', chunk);
      out.addAll(rows.map((r) => Map<String, dynamic>.from(r)));
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> _fetchRoutesByIds(
    List<String> routeIds,
  ) async {
    if (routeIds.isEmpty) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < routeIds.length; i += _inFilterChunk) {
      final chunk = routeIds.sublist(i, math.min(i + _inFilterChunk, routeIds.length));
      final rows = await _client
          .from('routes')
          .select('route_id, route_short_name, route_long_name, route_color, route_type')
          .inFilter('route_id', chunk);
      out.addAll(rows.map((r) => Map<String, dynamic>.from(r)));
    }
    return out;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _gtfsTimeDiffSeconds(String? from, String? to) {
    final a = _parseGtfsClock(from);
    final b = _parseGtfsClock(to);
    if (a == null || b == null) return -1;
    final diff = b - a;
    if (diff >= 0) return diff.toDouble();
    return -1;
  }

  static int? _parseGtfsClock(String? hhmmss) {
    if (hhmmss == null || hhmmss.isEmpty) return null;
    final p = hhmmss.split(':');
    if (p.length != 3) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final s = int.tryParse(p[2]);
    if (h == null || m == null || s == null) return null;
    if (m < 0 || m > 59 || s < 0 || s > 59) return null;
    return h * 3600 + m * 60 + s;
  }

  static String _inferRouteMode({
    required int? routeType,
    required String? routeShortName,
    required String? routeLongName,
  }) {
    if (routeType == 0 || routeType == 1 || routeType == 2) return 'Train';
    if (routeType == 4) return 'Ferry';

    final name = '${routeShortName ?? ''} ${routeLongName ?? ''}'.toLowerCase();
    if (name.contains('edsa') || name.contains('carousel') || name.contains('bus') || name.contains('brt')) {
      return 'Bus';
    }
    if (name.contains('uv') || name.contains('fx') || name.contains('van')) {
      return 'FX/Van';
    }
    if (name.contains('mrt') || name.contains('lrt') || name.contains('pnr') || name.contains('rail')) {
      return 'Train';
    }
    if (name.contains('ferry') || name.contains('pier')) {
      return 'Ferry';
    }
    if (name.contains('tric') || name.contains('trike')) {
      return 'Tricycle';
    }
    return 'Jeepney';
  }

  static double _fallbackSpeedForMode(String mode) {
    switch (mode) {
      case 'Bus':
        return 26.0;
      case 'Jeepney':
        return 17.0;
      case 'FX/Van':
        return 28.0;
      case 'Train':
        return 40.0;
      case 'Ferry':
        return 18.0;
      case 'Tricycle':
        return 12.0;
      default:
        return _fallbackTransitSpeedKmh;
    }
  }

  // ── Find nearest stops to a LatLng (sorted by distance) ───────────────────
  static Future<List<Map<String, dynamic>>> findNearestStops(
    LatLng point, {
    double radiusKm = 0.5,
    int limit = 4,
  }) async {
    final safeLimit = limit.clamp(1, _maxNearestStopsLimit);
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

    if (results.isEmpty) return [];

    final mapped = results.map((e) => Map<String, dynamic>.from(e)).toList();
    mapped.sort((a, b) {
      final dA = _haversineKm(point, LatLng(a['stop_lat'], a['stop_lon']));
      final dB = _haversineKm(point, LatLng(b['stop_lat'], b['stop_lon']));
      return dA.compareTo(dB);
    });

    if (mapped.length <= safeLimit) return mapped;
    return mapped.take(safeLimit).toList();
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