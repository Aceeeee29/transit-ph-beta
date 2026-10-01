import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/camanava_places.dart';
import '../models/route.dart' as route_model;
import 'transport_mode_inference.dart';

/// A single vehicle ride between two stops.
class TransitLeg {
  final String tripId;
  final String routeId;
  final String? shapeId;
  final String? routeShortName;
  final String? routeLongName;
  final String? routeColor;
  final int? routeType;
  final String boardStopId;
  final String alightStopId;
  final String boardStopName;
  final String alightStopName;
  final double boardLat;
  final double boardLon;
  final double alightLat;
  final double alightLon;

  /// Set only for legs taken from an approved community route: the
  /// contributor's own drawn path between board and alight, their paid fare
  /// (only when the whole step is ridden), and a ready-made instruction.
  final List<LatLng>? communityPath;
  final double? communityFare;
  final String? communityLabel;

  /// The trip's stops strictly between board and alight, in riding order.
  /// Used to draw legs whose trip has no GTFS shape along the vehicle's
  /// actual route instead of a straight line between the end stops.
  final List<LatLng> viaStops;

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
    this.communityPath,
    this.communityFare,
    this.communityLabel,
    this.viaStops = const [],
  });

  bool get isCommunity => communityLabel != null;
}

/// An admin-approved user route, reduced to what the router needs.
class CommunityRoute {
  final String id;
  final String startLocation;
  final String endLocation;
  final List<CommunityRouteStep> steps;

  const CommunityRoute({
    required this.id,
    required this.startLocation,
    required this.endLocation,
    required this.steps,
  });

  /// Splits the drawn path into per-step geometry using [stepBoundaries]
  /// (the path index where each step ends). Returns null when the route
  /// can't be split reliably, e.g. older routes saved without boundaries.
  static CommunityRoute? fromRoute(route_model.Route route) {
    if (!route.isApproved) return null;
    final path = route.pathPoints;
    if (path.length < 2 || route.steps.isEmpty) return null;

    final steps = <CommunityRouteStep>[];
    for (var i = 0; i < route.steps.length; i++) {
      final List<LatLng> stepPath;
      if (route.stepBoundaries.isEmpty) {
        if (route.steps.length != 1) return null;
        stepPath = path;
      } else {
        final start = i == 0 ? 0 : route.stepBoundaries[i - 1];
        final end =
            i < route.stepBoundaries.length
                ? route.stepBoundaries[i]
                : path.length - 1;
        if (start < 0 || end >= path.length || end <= start) continue;
        stepPath = path.sublist(start, end + 1);
      }
      final step = route.steps[i];
      steps.add(
        CommunityRouteStep(
          mode: step.mode,
          instruction: step.instruction,
          path: stepPath,
          actualFare: step.actualFare,
        ),
      );
    }
    if (steps.isEmpty) return null;

    return CommunityRoute(
      id: route.id,
      startLocation: route.startLocation,
      endLocation: route.endLocation,
      steps: steps,
    );
  }
}

class CommunityRouteStep {
  final String mode;
  final String instruction;
  final List<LatLng> path;
  final double? actualFare;

  const CommunityRouteStep({
    required this.mode,
    required this.instruction,
    required this.path,
    this.actualFare,
  });
}

/// 1 leg = direct, 2 legs = one transfer.
class TripPlan {
  final List<TransitLeg> legs;
  const TripPlan(this.legs);
  bool get isDirect => legs.length == 1;
  bool get hasTransfer => legs.length == 2;
}

class DijkstraTripPlanResult {
  final TripPlan plan;
  final Map<String, dynamic> selectedOriginStop;
  final Map<String, dynamic> selectedDestStop;
  final double totalCostSeconds;
  final double totalWalkKm;

  const DijkstraTripPlanResult({
    required this.plan,
    required this.selectedOriginStop,
    required this.selectedDestStop,
    required this.totalCostSeconds,
    required this.totalWalkKm,
  });
}

enum RouteOptimizationMode { budget, fastest, balanced }

class DijkstraRouteAlternative {
  final DijkstraTripPlanResult result;
  final double estimatedFarePhp;
  final double estimatedTimeMinutes;
  final double totalWalkKm;
  final double budgetScore;
  final double fastestScore;
  final double balancedScore;
  final double selectedScore;

  const DijkstraRouteAlternative({
    required this.result,
    required this.estimatedFarePhp,
    required this.estimatedTimeMinutes,
    required this.totalWalkKm,
    required this.budgetScore,
    required this.fastestScore,
    required this.balancedScore,
    required this.selectedScore,
  });
}

class _GraphEdge {
  final String from;
  final String to;
  final double costSeconds;
  final double distanceMeters;
  final bool isWalk;
  final String? tripId;
  final String? routeId;
  final String? shapeId;
  final String? routeShortName;
  final String? routeLongName;
  final String? routeColor;
  final int? routeType;

  /// Search-only preference multiplier; [costSeconds] stays the real time.
  final double weightFactor;

  const _GraphEdge({
    required this.from,
    required this.to,
    required this.costSeconds,
    required this.distanceMeters,
    required this.isWalk,
    this.tripId,
    this.routeId,
    this.shapeId,
    this.routeShortName,
    this.routeLongName,
    this.routeColor,
    this.routeType,
    this.weightFactor = 1.0,
  });
}

/// One riding step of a community route, in one direction.
class _CommunityTrip {
  /// Always in the contributor's drawn direction; [reversed] flips riding.
  final List<LatLng> path;
  final bool reversed;
  final String mode;

  /// "Start → End" in riding direction.
  final String routeLabel;

  /// The contributor's own instruction (e.g. the jeep's signboard).
  final String note;
  final double? actualFare;

  const _CommunityTrip({
    required this.path,
    required this.reversed,
    required this.mode,
    required this.routeLabel,
    required this.note,
    this.actualFare,
  });
}

class _QueueNode {
  final String node;
  final double cost;

  const _QueueNode(this.node, this.cost);
}

class _DijkstraGraphContext {
  final Map<String, List<_GraphEdge>> adjacency;
  final Map<String, Map<String, dynamic>> allStopsById;
  final Map<String, _CommunityTrip> communityTrips;

  /// Each GTFS trip's corridor stop IDs in stop_sequence order.
  final Map<String, List<String>> tripStopSequences;

  const _DijkstraGraphContext({
    required this.adjacency,
    required this.allStopsById,
    this.communityTrips = const {},
    this.tripStopSequences = const {},
  });
}

class _DijkstraContextCacheEntry {
  final String key;
  final _DijkstraGraphContext context;
  final DateTime cachedAt;

  const _DijkstraContextCacheEntry({
    required this.key,
    required this.context,
    required this.cachedAt,
  });
}

class _DijkstraPathResult {
  final List<_GraphEdge> edges;
  final double weightedCostSeconds;
  final double baseCostSeconds;

  const _DijkstraPathResult({
    required this.edges,
    required this.weightedCostSeconds,
    required this.baseCostSeconds,
  });
}

/// Bundles everything the repeated-Dijkstra search needs so it can run on a
/// background isolate via [compute] instead of blocking the UI thread.
class _DijkstraComputeArgs {
  final _DijkstraGraphContext context;
  final RouteOptimizationMode optimizationMode;
  final int maxAlternatives;
  final double edgePenaltyFactor;

  const _DijkstraComputeArgs({
    required this.context,
    required this.optimizationMode,
    required this.maxAlternatives,
    required this.edgePenaltyFactor,
  });
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
  static const _transferRadiusKm = 0.6;
  static const _transferBasePenaltySec = 90.0;
  static const _maxAccessWalkKm = 2.4;
  static const _boardingPenaltySec = 180.0;
  static const _maxRideStopsSpan = 30;

  static const _inFilterChunk = 250;

  static const _fallbackTransitSpeedKmh = 20.0;

  static const _dijkstraContextTtl = Duration(seconds: 45);
  static _DijkstraContextCacheEntry? _dijkstraContextCache;

  static Future<DijkstraTripPlanResult?> findTripPlanDijkstra({
    required LatLng origin,
    required LatLng destination,
    required List<Map<String, dynamic>> originCandidates,
    required List<Map<String, dynamic>> destCandidates,
    bool allowFerry = false,
  }) async {
    final alternatives = await findTripPlanDijkstraAlternatives(
      origin: origin,
      destination: destination,
      originCandidates: originCandidates,
      destCandidates: destCandidates,
      allowFerry: allowFerry,
      maxAlternatives: 1,
      optimizationMode: RouteOptimizationMode.balanced,
    );
    if (alternatives.isEmpty) return null;
    return alternatives.first.result;
  }

  static Future<List<DijkstraRouteAlternative>>
  findTripPlanDijkstraAlternatives({
    required LatLng origin,
    required LatLng destination,
    required List<Map<String, dynamic>> originCandidates,
    required List<Map<String, dynamic>> destCandidates,
    bool allowFerry = false,
    int maxAlternatives = 3,
    RouteOptimizationMode optimizationMode = RouteOptimizationMode.balanced,
    double edgePenaltyFactor = 0.45,
    List<CommunityRoute> communityRoutes = const [],
  }) async {
    if ((originCandidates.isEmpty || destCandidates.isEmpty) &&
        communityRoutes.isEmpty) {
      return const <DijkstraRouteAlternative>[];
    }

    final contextKey = _buildDijkstraContextKey(
      origin: origin,
      destination: destination,
      originCandidates: originCandidates,
      destCandidates: destCandidates,
      allowFerry: allowFerry,
      communityRoutes: communityRoutes,
    );

    var context = _getCachedDijkstraContext(contextKey);
    context ??= await _buildDijkstraGraphContext(
      origin: origin,
      destination: destination,
      originCandidates: originCandidates,
      destCandidates: destCandidates,
      allowFerry: allowFerry,
      communityRoutes: communityRoutes,
    );
    if (context != null) {
      _cacheDijkstraContext(contextKey, context);
    }
    if (context == null) return const <DijkstraRouteAlternative>[];

    // The repeated-Dijkstra search below can run 30+ full graph searches
    // back-to-back with no await in between, which previously blocked the
    // UI thread for the whole batch (visible as dropped frames / a frozen
    // screen during "Generate Route"). Running it via compute() moves that
    // CPU-bound work to a background isolate so the UI stays responsive.
    final results = await compute(
      _runDijkstraAlternatives,
      _DijkstraComputeArgs(
        context: context,
        optimizationMode: optimizationMode,
        maxAlternatives: maxAlternatives,
        edgePenaltyFactor: edgePenaltyFactor,
      ),
    );

    if (results.isEmpty) return const <DijkstraRouteAlternative>[];
    return _scoreAndSortAlternatives(results, optimizationMode);
  }

  /// Plans over community routes alone, with no Supabase access.
  @visibleForTesting
  static Future<List<DijkstraRouteAlternative>> planWithCommunityRoutesOnly({
    required LatLng origin,
    required LatLng destination,
    required List<CommunityRoute> communityRoutes,
    RouteOptimizationMode optimizationMode = RouteOptimizationMode.balanced,
  }) async {
    final context = await _buildDijkstraGraphContext(
      origin: origin,
      destination: destination,
      originCandidates: const [],
      destCandidates: const [],
      allowFerry: false,
      communityRoutes: communityRoutes,
      includeGtfs: false,
    );
    if (context == null) return const [];
    final results = _runDijkstraAlternatives(
      _DijkstraComputeArgs(
        context: context,
        optimizationMode: optimizationMode,
        maxAlternatives: 3,
        edgePenaltyFactor: 0.45,
      ),
    );
    if (results.isEmpty) return const [];
    return _scoreAndSortAlternatives(results, optimizationMode);
  }

  /// Pure, isolate-safe: repeatedly runs Dijkstra with growing edge
  /// penalties to approximate k-shortest diverse paths. No network or
  /// instance state — safe to run off the main isolate via [compute].
  static List<DijkstraTripPlanResult> _runDijkstraAlternatives(
    _DijkstraComputeArgs args,
  ) {
    final context = args.context;
    final optimizationMode = args.optimizationMode;
    final edgePenaltyFactor = args.edgePenaltyFactor;

    final results = <DijkstraTripPlanResult>[];
    final uniquePathSignatures = <String>{};
    final edgePenalties = <String, double>{};

    final targetCount = args.maxAlternatives.clamp(1, 6);
    final maxIterations = targetCount * 5;

    for (var i = 0; i < maxIterations && results.length < targetCount; i++) {
      final path = _runDijkstra(
        context.adjacency,
        _originNode,
        _destNode,
        optimizationMode: optimizationMode,
        edgePenalties: edgePenalties,
      );
      if (path == null) break;

      final signature = _pathTransitSignature(path.edges);

      if (signature.isNotEmpty && uniquePathSignatures.add(signature)) {
        final materialized = _materializeDijkstraResult(
          pathEdges: path.edges,
          totalCostSeconds: path.baseCostSeconds,
          allStopsById: context.allStopsById,
          communityTrips: context.communityTrips,
          tripStopSequences: context.tripStopSequences,
        );
        if (materialized != null) {
          results.add(materialized);
        }
      }

      for (final edge in path.edges) {
        final key = _edgeSignature(edge);
        final addPenalty =
            _edgeWeight(edge, optimizationMode) * edgePenaltyFactor;
        edgePenalties[key] = (edgePenalties[key] ?? 0) + addPenalty;
      }
    }

    return results;
  }

  /// K-shortest approximation using repeated Dijkstra runs with edge penalties.
  ///
  /// This keeps the code modular while producing diverse alternatives without
  /// a full Yen/Eppstein implementation.
  static Future<List<DijkstraRouteAlternative>> findTripPlanKShortestApprox({
    required LatLng origin,
    required LatLng destination,
    required List<Map<String, dynamic>> originCandidates,
    required List<Map<String, dynamic>> destCandidates,
    int k = 3,
    RouteOptimizationMode optimizationMode = RouteOptimizationMode.balanced,
    bool allowFerry = false,
  }) {
    return findTripPlanDijkstraAlternatives(
      origin: origin,
      destination: destination,
      originCandidates: originCandidates,
      destCandidates: destCandidates,
      allowFerry: allowFerry,
      maxAlternatives: k,
      optimizationMode: optimizationMode,
    );
  }

  static TransitLeg? _legFromEdges(
    _GraphEdge start,
    _GraphEdge end,
    Map<String, Map<String, dynamic>> stopById,
    Map<String, _CommunityTrip> communityTrips,
    Map<String, List<String>> tripStopSequences,
  ) {
    final boardStop = stopById[start.from];
    final alightStop = stopById[end.to];
    if (boardStop == null ||
        alightStop == null ||
        start.tripId == null ||
        start.routeId == null) {
      return null;
    }

    final community = communityTrips[start.tripId];
    if (community != null) {
      return _communityLegFromEdges(
        start,
        end,
        boardStop,
        alightStop,
        community,
      );
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
      viaStops: viaStopPoints(
        tripStopSequences[start.tripId!],
        start.from,
        end.to,
        stopById,
      ),
    );
  }

  /// Coordinates of the stops [sequence] visits strictly between
  /// [boardStopId] and the first [alightStopId] after it.
  @visibleForTesting
  static List<LatLng> viaStopPoints(
    List<String>? sequence,
    String boardStopId,
    String alightStopId,
    Map<String, Map<String, dynamic>> stopById,
  ) {
    if (sequence == null) return const [];
    final boardIdx = sequence.indexOf(boardStopId);
    if (boardIdx < 0) return const [];
    final alightIdx = sequence.indexOf(alightStopId, boardIdx + 1);
    if (alightIdx < 0) return const [];

    return [
      for (final id in sequence.sublist(boardIdx + 1, alightIdx))
        if (stopById[id] case final stop?)
          LatLng(
            (stop['stop_lat'] as num).toDouble(),
            (stop['stop_lon'] as num).toDouble(),
          ),
    ];
  }

  static _DijkstraPathResult? _runDijkstra(
    Map<String, List<_GraphEdge>> adjacency,
    String start,
    String target, {
    required RouteOptimizationMode optimizationMode,
    Map<String, double>? edgePenalties,
  }) {
    final dist = <String, double>{start: 0.0};
    final prev = <String, _GraphEdge>{};
    final heap = _MinHeap()..add(_QueueNode(start, 0.0));

    while (!heap.isEmpty) {
      final current = heap.pop();
      final best = dist[current.node];
      if (best == null || current.cost > best) continue;
      if (current.node == target) break;

      final edges = adjacency[current.node] ?? const <_GraphEdge>[];
      for (final edge in edges) {
        final edgeWeight = _edgeWeight(edge, optimizationMode);
        final penalty =
            edgePenalties == null
                ? 0.0
                : (edgePenalties[_edgeSignature(edge)] ?? 0.0);
        final nextCost = current.cost + edgeWeight + penalty;
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

    final edges = reversed.reversed.toList();
    final base = edges.fold<double>(0.0, (sum, e) => sum + e.costSeconds);
    return _DijkstraPathResult(
      edges: edges,
      weightedCostSeconds: total,
      baseCostSeconds: base,
    );
  }

  static double _edgeWeight(_GraphEdge edge, RouteOptimizationMode mode) {
    return _baseEdgeWeight(edge, mode) * edge.weightFactor;
  }

  static double _baseEdgeWeight(_GraphEdge edge, RouteOptimizationMode mode) {
    switch (mode) {
      case RouteOptimizationMode.balanced:
        return edge.costSeconds;
      case RouteOptimizationMode.fastest:
        return edge.isWalk ? edge.costSeconds * 3.0 : edge.costSeconds * 0.5;
      case RouteOptimizationMode.budget:
        final inferredMode =
            edge.isWalk
                ? 'Walk'
                : _inferRouteMode(
                  routeId: edge.routeId,
                  routeType: edge.routeType,
                  routeShortName: edge.routeShortName,
                  routeLongName: edge.routeLongName,
                );
        return PhFareCalculator.compute(inferredMode, edge.distanceMeters);
    }
  }

  static Future<_DijkstraGraphContext?> _buildDijkstraGraphContext({
    required LatLng origin,
    required LatLng destination,
    required List<Map<String, dynamic>> originCandidates,
    required List<Map<String, dynamic>> destCandidates,
    required bool allowFerry,
    List<CommunityRoute> communityRoutes = const [],
    bool includeGtfs = true,
  }) async {
    final corridorStops =
        includeGtfs
            ? await _fetchCorridorStops(origin, destination)
            : const <Map<String, dynamic>>[];

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

    final adjacency = <String, List<_GraphEdge>>{};
    final tripStopSequences = <String, List<String>>{};

    void addEdge(_GraphEdge edge) {
      adjacency.putIfAbsent(edge.from, () => []).add(edge);
    }

    if (includeGtfs && allStopsById.isNotEmpty) {
      await _addGtfsRideEdges(
        allStopsById: allStopsById,
        allowFerry: allowFerry,
        addEdge: addEdge,
        tripStopSequences: tripStopSequences,
      );
    }

    final communityTrips = <String, _CommunityTrip>{};
    _addCommunityLegs(
      routes: communityRoutes,
      bounds: _corridorBounds(origin, destination),
      allowFerry: allowFerry,
      allStopsById: allStopsById,
      communityTrips: communityTrips,
      addEdge: addEdge,
    );

    if (adjacency.isEmpty) return null;

    final stopList = allStopsById.values.toList();
    for (var i = 0; i < stopList.length; i++) {
      final a = stopList[i];
      final aId = a['stop_id'].toString();
      final aPt = LatLng(
        (a['stop_lat'] as num).toDouble(),
        (a['stop_lon'] as num).toDouble(),
      );

      for (var j = i + 1; j < stopList.length; j++) {
        final b = stopList[j];
        final bId = b['stop_id'].toString();
        final bPt = LatLng(
          (b['stop_lat'] as num).toDouble(),
          (b['stop_lon'] as num).toDouble(),
        );
        final dKm = _haversineKm(aPt, bPt);
        if (dKm > _transferRadiusKm) continue;

        final walkSec = (dKm / _walkSpeedKmh) * 3600 + _transferBasePenaltySec;
        addEdge(
          _GraphEdge(
            from: aId,
            to: bId,
            costSeconds: walkSec,
            distanceMeters: dKm * 1000.0,
            isWalk: true,
          ),
        );
        addEdge(
          _GraphEdge(
            from: bId,
            to: aId,
            costSeconds: walkSec,
            distanceMeters: dKm * 1000.0,
            isWalk: true,
          ),
        );
      }
    }

    final originCandidateIds =
        originCandidates
            .map((s) => s['stop_id']?.toString())
            .whereType<String>()
            .toSet();
    final destCandidateIds =
        destCandidates
            .map((s) => s['stop_id']?.toString())
            .whereType<String>()
            .toSet();

    for (final stop in stopList) {
      final stopId = stop['stop_id'].toString();
      final pt = LatLng(
        (stop['stop_lat'] as num).toDouble(),
        (stop['stop_lon'] as num).toDouble(),
      );

      final walkInKm = _haversineKm(origin, pt);
      if (walkInKm <= _maxAccessWalkKm || originCandidateIds.contains(stopId)) {
        addEdge(
          _GraphEdge(
            from: _originNode,
            to: stopId,
            costSeconds: (walkInKm / _walkSpeedKmh) * 3600,
            distanceMeters: walkInKm * 1000.0,
            isWalk: true,
          ),
        );
      }

      final walkOutKm = _haversineKm(pt, destination);
      if (walkOutKm <= _maxAccessWalkKm || destCandidateIds.contains(stopId)) {
        addEdge(
          _GraphEdge(
            from: stopId,
            to: _destNode,
            costSeconds: (walkOutKm / _walkSpeedKmh) * 3600,
            distanceMeters: walkOutKm * 1000.0,
            isWalk: true,
          ),
        );
      }
    }

    return _DijkstraGraphContext(
      adjacency: adjacency,
      allStopsById: allStopsById,
      communityTrips: communityTrips,
      tripStopSequences: tripStopSequences,
    );
  }

  /// Adds a ride edge for every stop pair a GTFS trip serves in the corridor,
  /// and records each trip's ordered stops in [tripStopSequences].
  static Future<void> _addGtfsRideEdges({
    required Map<String, Map<String, dynamic>> allStopsById,
    required bool allowFerry,
    required void Function(_GraphEdge edge) addEdge,
    required Map<String, List<String>> tripStopSequences,
  }) async {
    final stopIds = allStopsById.keys.toList();
    if (stopIds.isEmpty) return;

    final stopTimes = await _fetchStopTimesForStopIds(stopIds);
    if (stopTimes.isEmpty) return;

    final tripIds =
        stopTimes
            .map((r) => r['trip_id']?.toString())
            .whereType<String>()
            .toSet()
            .toList();
    if (tripIds.isEmpty) return;

    final tripRows = await _fetchTripsByIds(tripIds);
    if (tripRows.isEmpty) return;

    final routeIds =
        tripRows
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

    for (final entry in stopTimesByTrip.entries) {
      final tripId = entry.key;
      final seq = entry.value;
      seq.sort(
        (a, b) =>
            _asInt(a['stop_sequence']).compareTo(_asInt(b['stop_sequence'])),
      );
      if (seq.length < 2) continue;

      final trip = tripById[tripId];
      if (trip == null) continue;
      final routeId = trip['route_id']?.toString();
      final route = routeId != null ? routeById[routeId] : null;
      final routeType = _parseRouteType(route?['route_type']);
      final inferredMode = _inferRouteMode(
        routeId: routeId,
        routeType: routeType,
        routeShortName: route?['route_short_name'] as String?,
        routeLongName: route?['route_long_name'] as String?,
      );
      if (!allowFerry && inferredMode == 'Ferry') continue;
      tripStopSequences[tripId] = [
        for (final row in seq) row['stop_id'].toString(),
      ];
      final fallbackSpeedKmh = _fallbackSpeedForMode(inferredMode);

      final segmentSeconds = <double>[];
      final segmentMeters = <double>[];
      for (var i = 0; i < seq.length - 1; i++) {
        final a = seq[i];
        final b = seq[i + 1];
        final fromId = a['stop_id']?.toString();
        final toId = b['stop_id']?.toString();
        if (fromId == null || toId == null) {
          segmentSeconds.add(double.infinity);
          segmentMeters.add(0.0);
          continue;
        }

        final fromStop = allStopsById[fromId];
        final toStop = allStopsById[toId];
        if (fromStop == null || toStop == null) {
          segmentSeconds.add(double.infinity);
          segmentMeters.add(0.0);
          continue;
        }

        final segKm = _haversineKm(
          LatLng(
            (fromStop['stop_lat'] as num).toDouble(),
            (fromStop['stop_lon'] as num).toDouble(),
          ),
          LatLng(
            (toStop['stop_lat'] as num).toDouble(),
            (toStop['stop_lon'] as num).toDouble(),
          ),
        );

        var segSec = _gtfsTimeDiffSeconds(
          a['departure_time']?.toString(),
          b['arrival_time']?.toString(),
        );

        if (segSec <= 0 || segSec > 7200) {
          segSec = ((segKm / fallbackSpeedKmh) * 3600).clamp(20, 2400);
        }
        segmentSeconds.add(segSec);
        segmentMeters.add(segKm * 1000.0);
      }

      final prefix = List<double>.filled(segmentSeconds.length + 1, 0.0);
      for (var i = 0; i < segmentSeconds.length; i++) {
        prefix[i + 1] = prefix[i] + segmentSeconds[i];
      }
      final prefixMeters = List<double>.filled(segmentMeters.length + 1, 0.0);
      for (var i = 0; i < segmentMeters.length; i++) {
        prefixMeters[i + 1] = prefixMeters[i] + segmentMeters[i];
      }

      for (var i = 0; i < seq.length - 1; i++) {
        final fromId = seq[i]['stop_id']?.toString();
        if (fromId == null) continue;

        final maxJ = math.min(seq.length - 1, i + _maxRideStopsSpan);
        for (var j = i + 1; j <= maxJ; j++) {
          final toId = seq[j]['stop_id']?.toString();
          if (toId == null || toId == fromId) continue;

          final runSec = prefix[j] - prefix[i];
          final runMeters = prefixMeters[j] - prefixMeters[i];
          if (!runSec.isFinite || runSec <= 0) continue;
          if (!runMeters.isFinite || runMeters <= 0) continue;

          addEdge(
            _GraphEdge(
              from: fromId,
              to: toId,
              costSeconds: runSec + _boardingPenaltySec,
              distanceMeters: runMeters,
              isWalk: false,
              tripId: tripId,
              routeId: routeId,
              shapeId: _normalizeShapeId(trip['shape_id']),
              routeShortName: route?['route_short_name'] as String?,
              routeLongName: route?['route_long_name'] as String?,
              routeColor: route?['route_color'] as String?,
              routeType: routeType,
            ),
          );
        }
      }
    }

  }

  // ── Community routes ──────────────────────────────────────────────────────

  /// Riding a contributed route backwards is a guess (one-way streets,
  /// different pickup points), so it's allowed but discouraged and labelled.
  static const allowReversedCommunityLegs = true;
  static const _communityNodeSpacingKm = 0.3;
  static const _communityWeightFactor = 0.8;
  static const _reversedCommunityWeightFactor = 1.3;

  /// Turns each riding step of an approved route into boardable nodes every
  /// ~300 m along the contributor's path (stations only at the ends for
  /// trains) plus ride edges between them. Walking links to GTFS stops, other
  /// community routes, origin and destination are added later by the shared
  /// transfer/access pass, which is what lets separate routes combine.
  static void _addCommunityLegs({
    required List<CommunityRoute> routes,
    required ({double minLat, double maxLat, double minLng, double maxLng})
    bounds,
    required bool allowFerry,
    required Map<String, Map<String, dynamic>> allStopsById,
    required Map<String, _CommunityTrip> communityTrips,
    required void Function(_GraphEdge edge) addEdge,
  }) {
    if (routes.isEmpty) return;

    // Snapshot of GTFS stops, taken before community nodes are added.
    final transitStops = [
      for (final s in allStopsById.values)
        (
          name: s['stop_name']?.toString() ?? '',
          point: LatLng(
            (s['stop_lat'] as num).toDouble(),
            (s['stop_lon'] as num).toDouble(),
          ),
        ),
    ];

    for (final route in routes) {
      final forwardLabel = '${route.startLocation} → ${route.endLocation}';
      final reverseLabel = '${route.endLocation} → ${route.startLocation}';
      final lastStepIndex = route.steps.length - 1;

      for (var i = 0; i < route.steps.length; i++) {
        final step = route.steps[i];
        if (step.mode == 'Walk') continue;
        if (!allowFerry && step.mode == 'Ferry') continue;
        final path = step.path;
        if (path.length < 2 || !_pathTouchesBounds(path, bounds)) continue;

        final nodePathIndices =
            step.mode == 'Train'
                ? [0, path.length - 1]
                : _sampleIndicesAlongPath(path, _communityNodeSpacingKm);
        final alongKm = _cumulativeKm(path);

        final nodeIds = <String>[];
        for (var k = 0; k < nodePathIndices.length; k++) {
          final pathIndex = nodePathIndices[k];
          final point = path[pathIndex];
          final id = 'community|${route.id}|$i|$k';
          String? name;
          if (i == 0 && k == 0) {
            name = route.startLocation;
          } else if (i == lastStepIndex && k == nodePathIndices.length - 1) {
            name = route.endLocation;
          } else {
            final landmark = _nearestLandmark(point, transitStops);
            if (landmark != null) name = 'the stop near $landmark';
          }
          allStopsById[id] = {
            'stop_id': id,
            'stop_name': name ?? 'the ${step.mode} route ($forwardLabel)',
            'stop_lat': point.latitude,
            'stop_lon': point.longitude,
            'path_index': pathIndex,
            'named': name != null,
          };
          nodeIds.add(id);
        }

        final tripId = 'community|${route.id}|$i';
        final reverseTripId = '$tripId|rev';
        communityTrips[tripId] = _CommunityTrip(
          path: path,
          reversed: false,
          mode: step.mode,
          routeLabel: forwardLabel,
          note: step.instruction.trim(),
          actualFare: step.actualFare,
        );
        if (allowReversedCommunityLegs) {
          communityTrips[reverseTripId] = _CommunityTrip(
            path: path,
            reversed: true,
            mode: step.mode,
            routeLabel: reverseLabel,
            note: step.instruction.trim(),
            actualFare: step.actualFare,
          );
        }

        // Mode is carried only via routeType + routeShortName: mode inference
        // scans route text for tokens like "uv", "van" or "mrt", so free text
        // (place names, Firestore IDs) must never go into these fields.
        final routeType = switch (step.mode) {
          'Train' => 2,
          'Ferry' => 4,
          _ => 3,
        };
        final speedKmh = _fallbackSpeedForMode(step.mode);

        for (var a = 0; a < nodeIds.length - 1; a++) {
          for (var b = a + 1; b < nodeIds.length; b++) {
            final km =
                alongKm[nodePathIndices[b]] - alongKm[nodePathIndices[a]];
            if (km <= 0) continue;
            final seconds = (km / speedKmh) * 3600 + _boardingPenaltySec;

            _GraphEdge ride(String from, String to, String trip, double f) =>
                _GraphEdge(
                  from: from,
                  to: to,
                  costSeconds: seconds,
                  distanceMeters: km * 1000.0,
                  isWalk: false,
                  tripId: trip,
                  routeId: 'COMMUNITY',
                  routeShortName: step.mode,
                  routeType: routeType,
                  weightFactor: f,
                );

            addEdge(ride(nodeIds[a], nodeIds[b], tripId, _communityWeightFactor));
            if (allowReversedCommunityLegs) {
              addEdge(
                ride(
                  nodeIds[b],
                  nodeIds[a],
                  reverseTripId,
                  _reversedCommunityWeightFactor,
                ),
              );
            }
          }
        }
      }
    }
  }

  static const _landmarkRadiusKm = 0.35;
  static const _transitStopNameRadiusKm = 0.2;

  /// A recognisable name for a point along a community route: the closest
  /// CAMANAVA place within ~350 m, else the closest transit stop within
  /// ~200 m. Null when nothing is close enough to be meaningful.
  static String? _nearestLandmark(
    LatLng point,
    List<({String name, LatLng point})> transitStops,
  ) {
    String? best = nearestCamanavaPlaceName(
      point,
      maxMeters: _landmarkRadiusKm * 1000,
    );
    if (best != null) return best;

    var bestKm = _transitStopNameRadiusKm;
    for (final stop in transitStops) {
      if (stop.name.isEmpty) continue;
      final km = _haversineKm(point, stop.point);
      if (km <= bestKm) {
        best = stop.name;
        bestKm = km;
      }
    }
    return best;
  }

  static String _communityInstruction(
    _CommunityTrip trip,
    Map<String, dynamic> alightStop,
  ) {
    var text = 'Ride ${trip.mode} along the community route ${trip.routeLabel}';
    if (alightStop['named'] == true) {
      text += ', get off at ${alightStop['stop_name']}';
    }
    if (trip.reversed) {
      return '$text (opposite direction of what was contributed — '
          'not verified yet)';
    }
    return trip.note.isEmpty ? text : '$text — "${trip.note}"';
  }

  static TransitLeg _communityLegFromEdges(
    _GraphEdge start,
    _GraphEdge end,
    Map<String, dynamic> boardStop,
    Map<String, dynamic> alightStop,
    _CommunityTrip trip,
  ) {
    final boardIndex = boardStop['path_index'] as int;
    final alightIndex = alightStop['path_index'] as int;
    final lo = math.min(boardIndex, alightIndex);
    final hi = math.max(boardIndex, alightIndex);
    final segment = trip.path.sublist(lo, hi + 1);
    final wholeStep = lo == 0 && hi == trip.path.length - 1;

    return TransitLeg(
      tripId: start.tripId!,
      routeId: start.routeId!,
      routeShortName: start.routeShortName,
      routeType: start.routeType,
      boardStopId: start.from,
      alightStopId: end.to,
      boardStopName: boardStop['stop_name'] as String? ?? 'Stop',
      alightStopName: alightStop['stop_name'] as String? ?? 'Stop',
      boardLat: (boardStop['stop_lat'] as num).toDouble(),
      boardLon: (boardStop['stop_lon'] as num).toDouble(),
      alightLat: (alightStop['stop_lat'] as num).toDouble(),
      alightLon: (alightStop['stop_lon'] as num).toDouble(),
      communityPath: trip.reversed ? segment.reversed.toList() : segment,
      // The contributor's fare covers the whole step; partial rides fall
      // back to the LTFRB formula downstream.
      communityFare: wholeStep ? trip.actualFare : null,
      communityLabel: _communityInstruction(trip, alightStop),
    );
  }

  static bool _pathTouchesBounds(
    List<LatLng> path,
    ({double minLat, double maxLat, double minLng, double maxLng}) b,
  ) {
    return path.any(
      (p) =>
          p.latitude >= b.minLat &&
          p.latitude <= b.maxLat &&
          p.longitude >= b.minLng &&
          p.longitude <= b.maxLng,
    );
  }

  /// Path indices roughly every [spacingKm], always including both ends.
  static List<int> _sampleIndicesAlongPath(List<LatLng> path, double spacingKm) {
    final out = <int>[0];
    var sinceLast = 0.0;
    for (var i = 1; i < path.length; i++) {
      sinceLast += _haversineKm(path[i - 1], path[i]);
      if (sinceLast >= spacingKm) {
        out.add(i);
        sinceLast = 0.0;
      }
    }
    if (out.last != path.length - 1) out.add(path.length - 1);
    return out;
  }

  static List<double> _cumulativeKm(List<LatLng> path) {
    final out = List<double>.filled(path.length, 0.0);
    for (var i = 1; i < path.length; i++) {
      out[i] = out[i - 1] + _haversineKm(path[i - 1], path[i]);
    }
    return out;
  }

  static DijkstraTripPlanResult? _materializeDijkstraResult({
    required List<_GraphEdge> pathEdges,
    required double totalCostSeconds,
    required Map<String, Map<String, dynamic>> allStopsById,
    required Map<String, _CommunityTrip> communityTrips,
    required Map<String, List<String>> tripStopSequences,
  }) {
    final transitEdges =
        pathEdges.where((e) => !e.isWalk && e.tripId != null).toList();
    if (transitEdges.isEmpty) return null;

    final totalWalkMeters = pathEdges
        .where((e) => e.isWalk)
        .fold<double>(0.0, (sum, e) => sum + e.distanceMeters);

    final legs = <TransitLeg>[];
    var startEdge = transitEdges.first;
    var endEdge = transitEdges.first;

    for (var i = 1; i < transitEdges.length; i++) {
      final e = transitEdges[i];
      if (e.tripId == endEdge.tripId) {
        endEdge = e;
        continue;
      }
      final leg = _legFromEdges(
        startEdge,
        endEdge,
        allStopsById,
        communityTrips,
        tripStopSequences,
      );
      if (leg != null) legs.add(leg);
      startEdge = e;
      endEdge = e;
    }
    final lastLeg = _legFromEdges(
      startEdge,
      endEdge,
      allStopsById,
      communityTrips,
      tripStopSequences,
    );
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
      totalWalkKm: totalWalkMeters / 1000.0,
    );
  }

  static String _edgeSignature(_GraphEdge edge) {
    return '${edge.from}|${edge.to}|${edge.tripId ?? '-'}|${edge.routeId ?? '-'}|${edge.isWalk ? 'w' : 'r'}';
  }

  static String _pathTransitSignature(List<_GraphEdge> edges) {
    final transit = edges.where((e) => !e.isWalk).toList();
    if (transit.isEmpty) return '';
    return transit.map(_edgeSignature).join('>');
  }

  static List<DijkstraRouteAlternative> _scoreAndSortAlternatives(
    List<DijkstraTripPlanResult> results,
    RouteOptimizationMode mode,
  ) {
    final fares = results.map(_estimateFarePhp).toList();
    final times = results.map((r) => r.totalCostSeconds / 60.0).toList();

    final minFare = fares.reduce(math.min);
    final maxFare = fares.reduce(math.max);
    final minTime = times.reduce(math.min);
    final maxTime = times.reduce(math.max);

    final out = <DijkstraRouteAlternative>[];
    for (var i = 0; i < results.length; i++) {
      final budgetScore = _normalizeLowerIsBetter(fares[i], minFare, maxFare);
      final fastestScore = _normalizeLowerIsBetter(times[i], minTime, maxTime);
      const fareWeight = 0.6;
      const timeWeight = 0.4;
      final balancedScore =
          (budgetScore * fareWeight) + (fastestScore * timeWeight);

      final selectedScore = switch (mode) {
        RouteOptimizationMode.budget => budgetScore,
        RouteOptimizationMode.fastest => fastestScore,
        RouteOptimizationMode.balanced => balancedScore,
      };

      out.add(
        DijkstraRouteAlternative(
          result: results[i],
          estimatedFarePhp: fares[i],
          estimatedTimeMinutes: times[i],
          totalWalkKm: results[i].totalWalkKm,
          budgetScore: budgetScore,
          fastestScore: fastestScore,
          balancedScore: balancedScore,
          selectedScore: selectedScore,
        ),
      );
    }

    out.sort((a, b) {
      final bySelected = a.selectedScore.compareTo(b.selectedScore);
      if (bySelected != 0) return bySelected;
      return a.estimatedTimeMinutes.compareTo(b.estimatedTimeMinutes);
    });
    return out;
  }

  static double _normalizeLowerIsBetter(double value, double min, double max) {
    final range = max - min;
    if (range.abs() < 0.0001) return 0.0;
    return (value - min) / range;
  }

  /// Road distance is roughly 1.3× the straight line between stops in
  /// Metro Manila; used when a leg has no drawn path to measure.
  static const _roadDetourFactor = 1.3;

  static double _estimateFarePhp(DijkstraTripPlanResult result) {
    var total = 0.0;
    for (final leg in result.plan.legs) {
      if (leg.communityFare != null) {
        total += leg.communityFare!;
        continue;
      }
      final mode = _inferRouteMode(
        routeId: leg.routeId,
        routeType: leg.routeType,
        routeShortName: leg.routeShortName,
        routeLongName: leg.routeLongName,
      );
      final path = leg.communityPath;
      final km =
          path != null && path.length >= 2
              ? _polylineKm(path)
              : _haversineKm(
                    LatLng(leg.boardLat, leg.boardLon),
                    LatLng(leg.alightLat, leg.alightLon),
                  ) *
                  _roadDetourFactor;
      total += PhFareCalculator.compute(mode, km * 1000.0);
    }
    return total;
  }

  static double _polylineKm(List<LatLng> path) {
    var km = 0.0;
    for (var i = 0; i + 1 < path.length; i++) {
      km += _haversineKm(path[i], path[i + 1]);
    }
    return km;
  }

  /// Origin–destination box padded by a distance-scaled buffer.
  static ({double minLat, double maxLat, double minLng, double maxLng})
  _corridorBounds(LatLng origin, LatLng destination) {
    final directKm = _haversineKm(origin, destination);
    final bufferKm = (directKm * 0.35).clamp(
      _dijkstraMinBufferKm,
      _dijkstraMaxBufferKm,
    );
    final latBuffer = bufferKm / 111.0;
    final avgLat = (origin.latitude + destination.latitude) / 2;
    final lngBuffer = bufferKm / (111.0 * math.cos(avgLat * math.pi / 180));

    return (
      minLat: math.min(origin.latitude, destination.latitude) - latBuffer,
      maxLat: math.max(origin.latitude, destination.latitude) + latBuffer,
      minLng: math.min(origin.longitude, destination.longitude) - lngBuffer,
      maxLng: math.max(origin.longitude, destination.longitude) + lngBuffer,
    );
  }

  static Future<List<Map<String, dynamic>>> _fetchCorridorStops(
    LatLng origin,
    LatLng destination,
  ) async {
    final (:minLat, :maxLat, :minLng, :maxLng) = _corridorBounds(
      origin,
      destination,
    );

    final out = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final rows = await _client
          .schema('gtfs')
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
      final aPt = LatLng(
        (a['stop_lat'] as num).toDouble(),
        (a['stop_lon'] as num).toDouble(),
      );
      final bPt = LatLng(
        (b['stop_lat'] as num).toDouble(),
        (b['stop_lon'] as num).toDouble(),
      );
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
            .schema('gtfs')
            .from('stop_times')
            .select(
              'trip_id, stop_id, stop_sequence, arrival_time, departure_time',
            )
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
      final chunk = tripIds.sublist(
        i,
        math.min(i + _inFilterChunk, tripIds.length),
      );
      final rows = await _client
          .schema('gtfs')
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
      final chunk = routeIds.sublist(
        i,
        math.min(i + _inFilterChunk, routeIds.length),
      );
      final rows = await _client
          .schema('gtfs')
          .from('routes')
          .select(
            'route_id, route_short_name, route_long_name, route_color, route_type',
          )
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

  static double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
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
    required String? routeId,
    required int? routeType,
    required String? routeShortName,
    required String? routeLongName,
  }) {
    if (_isTrainRouteType(routeType)) return 'Train';
    if (routeType == 4) return 'Ferry';

    if (isEdsaCarouselLeg(
      routeId: routeId,
      routeType: routeType,
      routeShortName: routeShortName,
      routeLongName: routeLongName,
    )) {
      return 'Bus';
    }

    final name =
        '${routeId ?? ''} ${routeShortName ?? ''} ${routeLongName ?? ''}'
            .toLowerCase();
    if (_containsRouteCode(name, 'pub')) {
      return 'Bus';
    }
    if (_containsRouteCode(name, 'puj')) {
      return 'Jeepney';
    }

    if (name.contains('carousel') ||
        name.contains('bus') ||
        name.contains('brt')) {
      return 'Bus';
    }
    if (name.contains('uv') || name.contains('fx') || name.contains('van')) {
      return 'FX/Van';
    }
    if (name.contains('mrt') ||
        name.contains('lrt') ||
        name.contains('pnr') ||
        name.contains('rail')) {
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

  static bool _containsRouteCode(String source, String code) {
    if (source.isEmpty) return false;
    final pattern = RegExp('(^|[^a-z0-9])$code(?=[0-9]|[^a-z0-9]|\$)');
    return pattern.hasMatch(source);
  }

  static bool isEdsaCarouselLeg({
    required String? routeId,
    required int? routeType,
    String? routeShortName,
    String? routeLongName,
    String? boardStopId,
    String? alightStopId,
  }) {
    if (_isTrainRouteType(routeType)) return false;

    final normalizedRouteId = _normalizeRouteToken(routeId);
    final normalizedShort = _normalizeRouteToken(routeShortName);
    final normalizedLong = _normalizeRouteToken(routeLongName);
    final normalizedBoard = _normalizeRouteToken(boardStopId);
    final normalizedAlight = _normalizeRouteToken(alightStopId);

    if (normalizedRouteId == 'carousel_edsa' ||
        normalizedRouteId == 'edsa_carousel' ||
        normalizedRouteId == 'edsa_busway_carousel') {
      return true;
    }

    if (normalizedRouteId.startsWith('carousel_') &&
        normalizedRouteId.contains('edsa')) {
      return true;
    }

    // Carousel stops in our GTFS consistently use CAR_* IDs.
    if (routeType == 3 &&
        (normalizedBoard.startsWith('car_') ||
            normalizedAlight.startsWith('car_'))) {
      return true;
    }

    final merged = '$normalizedRouteId $normalizedShort $normalizedLong';
    final hasEdsa = _hasNormalizedToken(merged, 'edsa');
    final hasCarousel = _hasNormalizedToken(merged, 'carousel');
    final hasBusway =
        _hasNormalizedToken(merged, 'busway') ||
        _hasNormalizedToken(merged, 'brt');
    return hasEdsa && (hasCarousel || hasBusway);
  }

  static bool _hasNormalizedToken(String source, String token) {
    if (source.isEmpty) return false;
    final tokens =
        source.split(RegExp(r'[\s_]+')).where((t) => t.isNotEmpty).toSet();
    return tokens.contains(token);
  }

  static String _normalizeRouteToken(String? value) {
    if (value == null || value.isEmpty) return '';
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return normalized.replaceAll(RegExp(r'^_|_$'), '');
  }

  static bool _isTrainRouteType(int? routeType) {
    if (routeType == null) return false;

    // Core GTFS rail types + monorail.
    if (routeType == 0 || routeType == 1 || routeType == 2 || routeType == 12) {
      return true;
    }

    // GTFS extended rail/urban-rail categories frequently used by some feeds.
    if ((routeType >= 100 && routeType <= 117) ||
        (routeType >= 400 && routeType <= 405) ||
        (routeType >= 900 && routeType <= 906)) {
      return true;
    }

    return false;
  }

  static int? _parseRouteType(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static String? _normalizeShapeId(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final rounded = value.roundToDouble();
      if ((value - rounded).abs() < 0.000001) {
        return value.round().toString();
      }
      return value.toString();
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    final match = RegExp(r'^(\d+)\.0+$').firstMatch(raw);
    if (match != null) return match.group(1);

    return raw;
  }

  static String _buildDijkstraContextKey({
    required LatLng origin,
    required LatLng destination,
    required List<Map<String, dynamic>> originCandidates,
    required List<Map<String, dynamic>> destCandidates,
    required bool allowFerry,
    required List<CommunityRoute> communityRoutes,
  }) {
    final communityKey = communityRoutes
        .map(
          (r) =>
              '${r.id}:${r.steps.fold<int>(0, (n, s) => n + s.path.length)}',
        )
        .join(',');
    final originKey =
        '${origin.latitude.toStringAsFixed(5)},${origin.longitude.toStringAsFixed(5)}';
    final destKey =
        '${destination.latitude.toStringAsFixed(5)},${destination.longitude.toStringAsFixed(5)}';

    final originIds =
        originCandidates
            .map((s) => s['stop_id']?.toString())
            .whereType<String>()
            .toList()
          ..sort();
    final destIds =
        destCandidates
            .map((s) => s['stop_id']?.toString())
            .whereType<String>()
            .toList()
          ..sort();

    return '${allowFerry ? '1' : '0'}|$originKey|$destKey|o:${originIds.join(',')}|d:${destIds.join(',')}|c:$communityKey';
  }

  static _DijkstraGraphContext? _getCachedDijkstraContext(String key) {
    final cached = _dijkstraContextCache;
    if (cached == null) return null;
    if (cached.key != key) return null;
    if (DateTime.now().difference(cached.cachedAt) > _dijkstraContextTtl) {
      _dijkstraContextCache = null;
      return null;
    }
    return cached.context;
  }

  static void _cacheDijkstraContext(String key, _DijkstraGraphContext context) {
    _dijkstraContextCache = _DijkstraContextCacheEntry(
      key: key,
      context: context,
      cachedAt: DateTime.now(),
    );
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
        .schema('gtfs')
        .from('stops')
        .select('stop_id, stop_name, stop_lat, stop_lon')
        .gte('stop_lat', point.latitude - latDelta)
        .lte('stop_lat', point.latitude + latDelta)
        .gte('stop_lon', point.longitude - lngDelta)
        .lte('stop_lon', point.longitude + lngDelta);

    if (results.isEmpty) return [];

    final mapped = results.map((e) => Map<String, dynamic>.from(e)).toList();
    mapped.sort((a, b) {
      final dA = _haversineKm(
        point,
        LatLng(_asDouble(a['stop_lat']), _asDouble(a['stop_lon'])),
      );
      final dB = _haversineKm(
        point,
        LatLng(_asDouble(b['stop_lat']), _asDouble(b['stop_lon'])),
      );
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
    debugPrint(
      '[SupabaseRouteService] findTripPlan: "$originStopId" → "$destStopId"',
    );

    final response = await _client.rpc(
      'find_trip_plan',
      params: {'origin_stop_id': originStopId, 'dest_stop_id': destStopId},
    );

    if (response == null) {
      debugPrint('[SupabaseRouteService] RPC returned null — no route found');
      return null;
    }

    final data = Map<String, dynamic>.from(response as Map);
    final type = data['type'] as String?;

    debugPrint('[SupabaseRouteService] RPC result type: $type');

    if (type == 'direct') {
      final leg = await _buildLeg(
        tripId: data['leg1_trip_id'].toString(),
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
        tripId: data['leg1_trip_id'].toString(),
        boardStopId: originStopId,
        alightStopId: transferStopId,
      );
      final leg2 = await _buildLeg(
        tripId: data['leg2_trip_id'].toString(),
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
    final tripRow =
        await _client
            .schema('gtfs')
            .from('trips')
            .select('trip_id, route_id, shape_id')
            .eq('trip_id', tripId)
            .maybeSingle();

    if (tripRow == null) return null;

    final routeId = tripRow['route_id'].toString();
    final shapeId = _normalizeShapeId(tripRow['shape_id']);

    final stopRows = await _client
        .schema('gtfs')
        .from('stops')
        .select('stop_id, stop_name, stop_lat, stop_lon')
        .inFilter('stop_id', [boardStopId, alightStopId]);

    final routeRow =
        await _client
            .schema('gtfs')
            .from('routes')
            .select(
              'route_id, route_short_name, route_long_name, route_color, route_type',
            )
            .eq('route_id', routeId)
            .maybeSingle();

    Map<String, dynamic>? boardStop, alightStop;
    for (final s in stopRows) {
      if (s['stop_id'].toString() == boardStopId) boardStop = Map.from(s);
      if (s['stop_id'].toString() == alightStopId) alightStop = Map.from(s);
    }

    if (boardStop == null || alightStop == null) {
      debugPrint(
        '[SupabaseRouteService] Could not find stop coords for leg $tripId',
      );
      return null;
    }

    return TransitLeg(
      tripId: tripId,
      routeId: routeId,
      shapeId: shapeId,
      routeShortName: routeRow?['route_short_name'] as String?,
      routeLongName: routeRow?['route_long_name'] as String?,
      routeColor: routeRow?['route_color'] as String?,
      routeType: _parseRouteType(routeRow?['route_type']),
      boardStopId: boardStopId,
      alightStopId: alightStopId,
      boardStopName: boardStop['stop_name'] as String? ?? 'Stop',
      alightStopName: alightStop['stop_name'] as String? ?? 'Stop',
      boardLat: (boardStop['stop_lat'] as num).toDouble(),
      boardLon: (boardStop['stop_lon'] as num).toDouble(),
      alightLat: (alightStop['stop_lat'] as num).toDouble(),
      alightLon: (alightStop['stop_lon'] as num).toDouble(),
    );
  }

  // ── Get shape polyline for a trip ─────────────────────────────────────────
  static Future<List<LatLng>> getShapePolyline(String shapeId) async {
    final normalized = _normalizeShapeId(shapeId);
    if (normalized == null || normalized.isEmpty) return [];
    final points = await _client
        .schema('gtfs')
        .from('shapes')
        .select('shape_pt_lat, shape_pt_lon, shape_pt_sequence')
        .eq('shape_id', normalized)
        .order('shape_pt_sequence');

    return points
        .map(
          (p) => LatLng(
            (p['shape_pt_lat'] as num).toDouble(),
            (p['shape_pt_lon'] as num).toDouble(),
          ),
        )
        .toList();
  }

  // ── Get all stops along a trip ────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getStopsForTrip(
    String tripId,
  ) async {
    final stopTimes = await _client
        .schema('gtfs')
        .from('stop_times')
        .select('stop_id, stop_sequence, arrival_time, departure_time')
        .eq('trip_id', tripId)
        .order('stop_sequence');

    final stopIds = stopTimes.map((s) => s['stop_id'].toString()).toList();

    final stops = await _client
        .schema('gtfs')
        .from('stops')
        .select('stop_id, stop_name, stop_lat, stop_lon')
        .inFilter('stop_id', stopIds);

    final stopMap = {for (var s in stops) s['stop_id'].toString(): s};

    return stopTimes.map((st) {
      final stop = stopMap[st['stop_id'].toString()] ?? {};
      return {
        ...st,
        'stop_name': stop['stop_name'],
        'stop_lat': stop['stop_lat'],
        'stop_lon': stop['stop_lon'],
      };
    }).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  static double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final x =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
