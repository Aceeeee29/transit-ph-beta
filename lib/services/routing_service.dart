import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config.dart';
import '../models/ors_route_result.dart';
import '../repositories/route_cache_repository.dart';
import 'supabase_route_service.dart';
import 'transport_mode_inference.dart';

/// Thrown when routing cannot produce a result.
class RoutingException implements Exception {
  final String message;
  const RoutingException(this.message);
  @override
  String toString() => message;
}

/// Supabase/GTFS routing with OSRM road snapping.
///
/// Priority:
///   1. GTFS direct route        — one trip, road-snapped via OSRM
///   2. GTFS 1-transfer route    — two trips, road-snapped via OSRM
///   3. Fallback direct route    — estimated walk/ride, road-snapped via OSRM
///
/// OSRM public API is used for road snapping only (free, no key required).
class RoutingService {
  static const _minWalkSegmentKm = 0.08;
  static const _walkSpeedKmh = 5.0;
  static const _stopSearchRadiusKm = 0.5;
  static const _stopSearchRadiusExpandedKm = 1.5;
  static const _candidateStopsLimit = 4;
  static const _allowFerrySuggestions = false;

  // OSRM public demo server — free, no API key needed
  static const _osrmBase = 'https://router.project-osrm.org/route/v1';

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Full GTFS-backed routing for the navigation screen.
  /// Do NOT call this for simple map drawing — use [snapToRoad] instead.
  static Future<OrsRouteResult> getRoute({
    required String originName,
    required LatLng origin,
    required String destinationName,
    required LatLng destination,
    String mode = 'Jeepney',
  }) async {
    final cached = await RouteCacheRepository.get(
      originName,
      destinationName,
      mode,
      RouteCacheRepository.generatedRouteProfile,
    );
    if (cached != null) {
      debugPrint('[RoutingService] Cache hit');
      return cached;
    }

    final result = await _getGtfsRoute(
      origin: origin,
      destination: destination,
      preferredMode: mode,
    );

    RouteCacheRepository.put(
      originName,
      destinationName,
      mode,
      RouteCacheRepository.generatedRouteProfile,
      result,
    );
    return result;
  }

  /// Returns up to 3 GTFS alternatives from Dijkstra with optimization scoring.
  ///
  /// This is a modular hook for route search UIs that want multiple options
  /// (budget / fastest / balanced) without changing the existing getRoute flow.
  static Future<List<DijkstraRouteAlternative>> getRouteAlternatives({
    required LatLng origin,
    required LatLng destination,
    String optimization = 'balanced',
    int maxAlternatives = 3,
    List<CommunityRoute> communityRoutes = const [],
  }) async {
    List<List<Map<String, dynamic>>> candidates;
    try {
      candidates = await Future.wait([
        SupabaseRouteService.findNearestStops(
          origin,
          radiusKm: _stopSearchRadiusKm,
          limit: _candidateStopsLimit,
        ),
        SupabaseRouteService.findNearestStops(
          destination,
          radiusKm: _stopSearchRadiusKm,
          limit: _candidateStopsLimit,
        ),
      ]).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const RoutingException(
        'Stop lookup timed out. Check your internet connection.',
      );
    }

    if (candidates[0].isEmpty || candidates[1].isEmpty) {
      try {
        candidates = await Future.wait([
          candidates[0].isNotEmpty
              ? Future.value(candidates[0])
              : SupabaseRouteService.findNearestStops(
                origin,
                radiusKm: _stopSearchRadiusExpandedKm,
                limit: _candidateStopsLimit,
              ),
          candidates[1].isNotEmpty
              ? Future.value(candidates[1])
              : SupabaseRouteService.findNearestStops(
                destination,
                radiusKm: _stopSearchRadiusExpandedKm,
                limit: _candidateStopsLimit,
              ),
        ]).timeout(const Duration(seconds: 8));
      } on TimeoutException {
        throw const RoutingException(
          'Stop lookup timed out. Check your internet connection.',
        );
      }
    }

    final originCandidates = candidates[0];
    final destCandidates = candidates[1];
    if ((originCandidates.isEmpty || destCandidates.isEmpty) &&
        communityRoutes.isEmpty) {
      return const <DijkstraRouteAlternative>[];
    }

    return SupabaseRouteService.findTripPlanDijkstraAlternatives(
      origin: origin,
      destination: destination,
      originCandidates: originCandidates,
      destCandidates: destCandidates,
      allowFerry: _allowFerrySuggestions,
      maxAlternatives: maxAlternatives,
      optimizationMode: _parseOptimizationMode(optimization),
      communityRoutes: communityRoutes,
    );
  }

  /// Build a full map-ready route from one selected Dijkstra alternative.
  static Future<OrsRouteResult> buildRouteFromDijkstraAlternative({
    required LatLng origin,
    required LatLng destination,
    required DijkstraTripPlanResult alternative,
    String preferredMode = 'Auto',
  }) async {
    final shapePolylines = await Future.wait(
      alternative.plan.legs.map(
        (leg) => _buildTransitLegPolyline(
          leg: leg,
          preferredMode: preferredMode,
        ),
      ),
    );

    return _buildResult(
      origin: origin,
      destination: destination,
      legs: alternative.plan.legs,
      shapePolylines: shapePolylines,
      preferredMode: preferredMode,
      selectedOriginStop: alternative.selectedOriginStop,
      selectedDestStop: alternative.selectedDestStop,
    );
  }

  static Future<OrsRouteResult> buildWalkFallbackRoute({
    required LatLng origin,
    required LatLng destination,
    String note = 'Showing walking fallback route for route variety.',
  }) {
    return _buildFallbackRoute(
      origin: origin,
      destination: destination,
      preferredMode: 'Walk',
      note: note,
    );
  }

  /// Whether a [mode] vehicle normally uses expressways when suggesting its
  /// path: buses and FX/vans do; jeepneys and tricycles normally don't.
  /// Only a default for suggestions — a contributor's drawn route is never
  /// re-routed by it.
  static bool defaultAllowsExpressways(String mode) =>
      mode == 'Bus' || mode == 'FX/Van';

  /// Lightweight road-snap between two points: drawing in the Contribute
  /// screen and walking paths back to a followed route.
  ///
  /// Uses OpenRouteService first, which has a real walking profile and can
  /// avoid expressways, and falls back to OSRM when it is unavailable or
  /// rate-limited. No Supabase, no GTFS, no caching. Returns null if both
  /// are unreachable so the caller can fall back to a straight line.
  static Future<OrsRouteResult?> snapToRoad({
    required LatLng origin,
    required LatLng destination,
    String mode = 'Jeepney',
    bool? allowExpressways,
  }) async {
    final pts =
        await _orsRoute(
          origin,
          destination,
          mode: mode,
          allowExpressways: allowExpressways ?? defaultAllowsExpressways(mode),
        ) ??
        await _osrmSnap(origin, destination, _osrmProfileForMode(mode));
    if (pts == null || pts.length < 2) return null;

    final distKm = _polylineDistanceKm(pts);
    final distM = distKm * 1000;
    final durS = (distKm / _speedForMode(mode)) * 3600;

    return OrsRouteResult(
      distanceMeters: distM,
      durationSeconds: durS,
      polyline: pts,
      steps: [],
      bbox: [],
    );
  }

  /// Road path through [points] in order — e.g. a recorded ride — for
  /// turning it into route geometry. Null when routing fails.
  static Future<List<LatLng>?> snapThrough(
    List<LatLng> points, {
    String mode = 'Jeepney',
  }) {
    if (points.length < 2) return Future.value(null);
    return _osrmRoute(points, _osrmProfileForMode(mode));
  }

  static RouteOptimizationMode _parseOptimizationMode(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'budget':
        return RouteOptimizationMode.budget;
      case 'fastest':
        return RouteOptimizationMode.fastest;
      default:
        return RouteOptimizationMode.balanced;
    }
  }

  // ── GTFS routing with fallback ────────────────────────────────────────────────

  static Future<OrsRouteResult> _getGtfsRoute({
    required LatLng origin,
    required LatLng destination,
    required String preferredMode,
  }) async {
    // ── Step 1: Nearest stop candidates ───────────────────────────────────────
    List<List<Map<String, dynamic>>> candidates;
    try {
      candidates = await Future.wait([
        SupabaseRouteService.findNearestStops(
          origin,
          radiusKm: _stopSearchRadiusKm,
          limit: _candidateStopsLimit,
        ),
        SupabaseRouteService.findNearestStops(
          destination,
          radiusKm: _stopSearchRadiusKm,
          limit: _candidateStopsLimit,
        ),
      ]).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const RoutingException(
        'Stop lookup timed out. Check your internet connection.',
      );
    }

    // Expand radius if either side has no nearby candidates
    if (candidates[0].isEmpty || candidates[1].isEmpty) {
      try {
        candidates = await Future.wait([
          candidates[0].isNotEmpty
              ? Future.value(candidates[0])
              : SupabaseRouteService.findNearestStops(
                origin,
                radiusKm: _stopSearchRadiusExpandedKm,
                limit: _candidateStopsLimit,
              ),
          candidates[1].isNotEmpty
              ? Future.value(candidates[1])
              : SupabaseRouteService.findNearestStops(
                destination,
                radiusKm: _stopSearchRadiusExpandedKm,
                limit: _candidateStopsLimit,
              ),
        ]).timeout(const Duration(seconds: 8));
      } on TimeoutException {
        throw const RoutingException(
          'Stop lookup timed out. Check your internet connection.',
        );
      }
    }

    final originCandidates = candidates[0];
    final destCandidates = candidates[1];
    final originStopData =
        originCandidates.isNotEmpty ? originCandidates.first : null;
    final destStopData =
        destCandidates.isNotEmpty ? destCandidates.first : null;

    // ── Fallback A: no stops at all — walk-only route ─────────────────────────
    if (originStopData == null || destStopData == null) {
      debugPrint('[RoutingService] No stops found — using walk fallback');
      return _buildFallbackRoute(
        origin: origin,
        destination: destination,
        preferredMode: 'Walk',
        note: 'No transit stops found nearby. Showing estimated walking route.',
      );
    }

    final nearestOriginStopId = originStopData['stop_id'].toString();
    final nearestDestStopId = destStopData['stop_id'].toString();

    debugPrint(
      '[RoutingService] Origin nearest: ${originStopData['stop_name']} ($nearestOriginStopId)',
    );
    debugPrint(
      '[RoutingService] Dest nearest:   ${destStopData['stop_name']} ($nearestDestStopId)',
    );

    if (nearestOriginStopId == nearestDestStopId) {
      return _buildFallbackRoute(
        origin: origin,
        destination: destination,
        preferredMode: 'Walk',
        note: 'Origin and destination are very close. Showing walking route.',
      );
    }

    // ── Step 2: GTFS trip plan (Dijkstra first, then heuristic fallback) ─────
    TripPlan? plan;
    Map<String, dynamic>? selectedOriginStop;
    Map<String, dynamic>? selectedDestStop;
    double bestScore = double.infinity;

    try {
      final dijkstraResult = await SupabaseRouteService.findTripPlanDijkstra(
        origin: origin,
        destination: destination,
        originCandidates: originCandidates,
        destCandidates: destCandidates,
        allowFerry: _allowFerrySuggestions,
      ).timeout(const Duration(seconds: 20));

      if (dijkstraResult != null) {
        plan = dijkstraResult.plan;
        selectedOriginStop = dijkstraResult.selectedOriginStop;
        selectedDestStop = dijkstraResult.selectedDestStop;
        bestScore = dijkstraResult.totalCostSeconds / 3600.0;
        debugPrint(
          '[RoutingService] Dijkstra plan selected (${plan.legs.length} leg(s))',
        );
      } else {
        for (final originStop in originCandidates) {
          for (final destStop in destCandidates) {
            final originStopId = originStop['stop_id'].toString();
            final destStopId = destStop['stop_id'].toString();
            if (originStopId == destStopId) continue;

            final candidatePlan = await SupabaseRouteService.findTripPlan(
              originStopId,
              destStopId,
            ).timeout(const Duration(seconds: 15));

            if (candidatePlan == null) continue;
            if (!_allowFerrySuggestions && _planHasFerry(candidatePlan)) {
              continue;
            }

            final originStopPoint = LatLng(
              (originStop['stop_lat'] as num).toDouble(),
              (originStop['stop_lon'] as num).toDouble(),
            );
            final destStopPoint = LatLng(
              (destStop['stop_lat'] as num).toDouble(),
              (destStop['stop_lon'] as num).toDouble(),
            );

            final walkInKm = _haversineKm(origin, originStopPoint);
            final walkOutKm = _haversineKm(destStopPoint, destination);
            final transferPenalty = candidatePlan.legs.length > 1 ? 0.35 : 0.0;
            final score = walkInKm + walkOutKm + transferPenalty;

            if (score < bestScore) {
              bestScore = score;
              plan = candidatePlan;
              selectedOriginStop = originStop;
              selectedDestStop = destStop;
            }
          }
        }
      }
    } on TimeoutException {
      throw const RoutingException(
        'Route lookup timed out. Check your internet connection.',
      );
    } catch (e) {
      debugPrint('[RoutingService] Trip plan error: $e');
    }

    // ── Fallback B: no GTFS connection — estimated direct route ───────────────
    if (plan == null) {
      debugPrint('[RoutingService] No GTFS connection — using direct fallback');
      return _buildFallbackRoute(
        origin: origin,
        destination: destination,
        preferredMode: preferredMode,
        originStop: LatLng(
          (originStopData['stop_lat'] as num).toDouble(),
          (originStopData['stop_lon'] as num).toDouble(),
        ),
        originStopName: originStopData['stop_name'] as String? ?? 'Stop',
        destStop: LatLng(
          (destStopData['stop_lat'] as num).toDouble(),
          (destStopData['stop_lon'] as num).toDouble(),
        ),
        destStopName: destStopData['stop_name'] as String? ?? 'Stop',
        note:
            'No connected transit route found in current data. '
            'Showing estimated direct route.',
      );
    }

    final chosenOriginStop = selectedOriginStop ?? originStopData;
    final chosenDestStop = selectedDestStop ?? destStopData;

    debugPrint(
      '[RoutingService] Selected origin stop: ${chosenOriginStop['stop_name']} (${chosenOriginStop['stop_id']})',
    );
    debugPrint(
      '[RoutingService] Selected dest stop:   ${chosenDestStop['stop_name']} (${chosenDestStop['stop_id']})',
    );

    debugPrint('[RoutingService] Plan: ${plan.legs.length} leg(s)');

    // ── Step 3: Road-snap each leg via OSRM ──────────────────────────────────
    final shapePolylines = await Future.wait(
      plan.legs.map(
        (leg) => _buildTransitLegPolyline(
          leg: leg,
          preferredMode: preferredMode,
        ),
      ),
    );

    return await _buildResult(
      origin: origin,
      destination: destination,
      legs: plan.legs,
      shapePolylines: shapePolylines,
      preferredMode: preferredMode,
      selectedOriginStop: chosenOriginStop,
      selectedDestStop: chosenDestStop,
    );
  }

  // ── Fallback route (no GTFS data) ─────────────────────────────────────────────

  static Future<OrsRouteResult> _buildFallbackRoute({
    required LatLng origin,
    required LatLng destination,
    required String preferredMode,
    LatLng? originStop,
    String? originStopName,
    LatLng? destStop,
    String? destStopName,
    required String note,
  }) async {
    final combinedPolyline = <LatLng>[];
    final steps = <OrsStep>[];

    final bool hasStops = originStop != null && destStop != null;

    // ── Walk-in (origin → nearest stop) ──────────────────────────────────────
    if (hasStops) {
      final walkInKm = _haversineKm(origin, originStop);
      if (walkInKm > _minWalkSegmentKm) {
        final walkPts =
            await _osrmSnap(origin, originStop, 'foot') ?? [origin, originStop];
        final walkDistM = _polylineDistanceKm(walkPts) * 1000;
        final startIdx = combinedPolyline.length;
        combinedPolyline.addAll(walkPts);
        steps.add(
          OrsStep(
            instruction: 'Walk to ${originStopName ?? 'nearest stop'}',
            distanceMeters: walkDistM,
            durationSeconds: (walkDistM / 1000 / _walkSpeedKmh) * 3600,
            suggestedMode: 'Walk',
            estimatedFare: 0.0,
            wayPointStart: startIdx,
            wayPointEnd: combinedPolyline.length - 1,
          ),
        );
      } else {
        combinedPolyline.add(originStop);
      }
    } else {
      combinedPolyline.add(origin);
    }

    // ── Main estimated ride / walk ────────────────────────────────────────────
    final ridePtA = hasStops ? originStop : origin;
    final ridePtB = hasStops ? destStop : destination;
    final rideMode =
        preferredMode == 'Walk'
            ? 'Walk'
            : (preferredMode == 'Auto' ? 'Jeepney' : preferredMode);
    final osrmProf = _osrmProfileForMode(rideMode);

    final ridePts =
        await _osrmSnap(ridePtA, ridePtB, osrmProf) ?? [ridePtA, ridePtB];

    final rideDistM = _polylineDistanceKm(ridePts) * 1000;
    final rideSpeed = _speedForMode(rideMode);
    final rideDurS = (rideDistM / 1000 / rideSpeed) * 3600;
    final rideFare = PhFareCalculator.compute(rideMode, rideDistM);

    final rideStartIdx =
        combinedPolyline.isEmpty ? 0 : combinedPolyline.length - 1;

    final rideToAdd =
        combinedPolyline.isNotEmpty &&
                ridePts.isNotEmpty &&
                _haversineKm(combinedPolyline.last, ridePts.first) < 0.001
            ? ridePts.skip(1).toList()
            : ridePts;
    combinedPolyline.addAll(rideToAdd);

    final rideLabel =
        hasStops
            ? '[Estimated] $rideMode from ${originStopName ?? 'start'} to ${destStopName ?? 'destination'}'
            : '[Estimated] $rideMode to destination';

    steps.add(
      OrsStep(
        instruction: rideLabel,
        distanceMeters: rideDistM,
        durationSeconds: rideDurS,
        suggestedMode: rideMode,
        estimatedFare: rideFare,
        wayPointStart: rideStartIdx,
        wayPointEnd: combinedPolyline.length - 1,
      ),
    );

    // ── Walk-out (dest stop → destination) ────────────────────────────────────
    if (hasStops) {
      final walkOutKm = _haversineKm(destStop, destination);
      if (walkOutKm > _minWalkSegmentKm) {
        final walkPts =
            await _osrmSnap(destStop, destination, 'foot') ??
            [destStop, destination];
        final walkDistM = _polylineDistanceKm(walkPts) * 1000;
        final startIdx = combinedPolyline.length - 1;
        final toAdd =
            _haversineKm(combinedPolyline.last, walkPts.first) < 0.001
                ? walkPts.skip(1).toList()
                : walkPts;
        combinedPolyline.addAll(toAdd);
        steps.add(
          OrsStep(
            instruction: 'Walk from ${destStopName ?? 'stop'} to destination',
            distanceMeters: walkDistM,
            durationSeconds: (walkDistM / 1000 / _walkSpeedKmh) * 3600,
            suggestedMode: 'Walk',
            estimatedFare: 0.0,
            wayPointStart: startIdx,
            wayPointEnd: combinedPolyline.length - 1,
          ),
        );
      }
    }

    // ── Totals + BBox ─────────────────────────────────────────────────────────
    final totalDistM = steps.fold(0.0, (s, e) => s + e.distanceMeters);
    final totalDurS = steps.fold(0.0, (s, e) => s + e.durationSeconds);

    List<double> bbox = [];
    if (combinedPolyline.isNotEmpty) {
      final lats = combinedPolyline.map((p) => p.latitude);
      final lngs = combinedPolyline.map((p) => p.longitude);
      bbox = [
        lngs.reduce(math.min),
        lats.reduce(math.min),
        lngs.reduce(math.max),
        lats.reduce(math.max),
      ];
    }

    debugPrint('[RoutingService] Fallback route built — $note');

    return OrsRouteResult(
      distanceMeters: totalDistM,
      durationSeconds: totalDurS,
      polyline: combinedPolyline,
      steps: steps,
      bbox: bbox,
    );
  }

  // ── OpenRouteService (low-volume snapping) ────────────────────────────────────

  static const _orsBase = 'https://api.openrouteservice.org/v2/directions';

  /// After a rate-limit response, skip ORS for this long (OSRM serves).
  static const _orsCooldown = Duration(seconds: 60);
  static DateTime? _orsCooldownUntil;

  /// Road path between two points via OpenRouteService, or null so the
  /// caller can fall back to OSRM. Walking uses ORS's foot profile; vehicles
  /// use the car profile, avoiding expressways and tollways unless
  /// [allowExpressways].
  static Future<List<LatLng>?> _orsRoute(
    LatLng from,
    LatLng to, {
    required String mode,
    required bool allowExpressways,
  }) async {
    String key;
    try {
      key = Config.openRouteServiceApiKey;
    } catch (_) {
      return null; // .env not loaded (e.g. in tests)
    }
    if (key.isEmpty) return null;
    final cooldown = _orsCooldownUntil;
    if (cooldown != null && DateTime.now().isBefore(cooldown)) return null;

    final isWalk = mode == 'Walk';
    final profile = isWalk ? 'foot-walking' : 'driving-car';
    try {
      final response = await http
          .post(
            Uri.parse('$_orsBase/$profile/geojson'),
            headers: {'Authorization': key, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'coordinates': [
                [from.longitude, from.latitude],
                [to.longitude, to.latitude],
              ],
              if (!isWalk && !allowExpressways)
                'options': {
                  'avoid_features': ['highways', 'tollways'],
                },
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 429) {
        _orsCooldownUntil = DateTime.now().add(_orsCooldown);
        debugPrint('[ORS] Rate limited, using OSRM for a while');
        return null;
      }
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return null;
      final coordinates =
          (features.first as Map<String, dynamic>)['geometry']['coordinates']
              as List;
      final points = [
        for (final c in coordinates)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      return points.length >= 2 ? points : null;
    } catch (e) {
      debugPrint('[ORS] Route failed ($profile): $e');
      return null;
    }
  }

  // ── OSRM road snapping ────────────────────────────────────────────────────────

  static Future<List<LatLng>?> _osrmSnap(
    LatLng from,
    LatLng to,
    String profile,
  ) => _osrmRoute([from, to], profile);

  static const _maxOsrmWaypoints = 25;

  /// Road-snaps a path that must pass through [waypoints] in order.
  static Future<List<LatLng>?> _osrmRoute(
    List<LatLng> waypoints,
    String profile,
  ) async {
    if (waypoints.length < 2) return null;
    final from = waypoints.first;
    final to = waypoints.last;
    final via = _sampleWaypoints(waypoints, _maxOsrmWaypoints);
    try {
      final coords = via.map((p) => '${p.longitude},${p.latitude}').join(';');
      final uri = Uri.parse(
        '$_osrmBase/$profile/$coords?overview=full&geometries=geojson'
        '${via.length > 2 ? '&continue_straight=true' : ''}',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final code = data['code'] as String?;
      if (code != 'Ok') return null;

      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final geometry = routes[0]['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      final points =
          coordinates
              .map(
                (c) =>
                    LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
              )
              .toList();

      // OSRM can occasionally produce pathological small-area loops near
      // roundabouts/interchanges. If detected, skip snap so callers can
      // fall back to GTFS shape or straight segment.
      if (_shouldRejectSnappedPath(
        from: from,
        to: to,
        points: points,
        referenceKm: via.length > 2 ? _polylineDistanceKm(via) : null,
      )) {
        debugPrint('[OSRM] Rejected looped snap geometry, falling back');
        return null;
      }

      return points;
    } catch (e) {
      debugPrint('[OSRM] Snap failed ($profile): $e');
      return null;
    }
  }

  /// Evenly thins [points] to at most [max], always keeping both ends.
  static List<LatLng> _sampleWaypoints(List<LatLng> points, int max) {
    if (points.length <= max) return points;
    final step = (points.length - 1) / (max - 1);
    return [for (var i = 0; i < max; i++) points[(i * step).round()]];
  }

  static bool _shouldRejectSnappedPath({
    required LatLng from,
    required LatLng to,
    required List<LatLng> points,
    double? referenceKm,
  }) {
    if (points.length < 3) return false;

    final directKm = referenceKm ?? _haversineKm(from, to);
    final snappedKm = _polylineDistanceKm(points);
    if (directKm <= 0) return false;

    final ratio = snappedKm / directKm;

    // Very short connectors that balloon into long loops are almost always bad.
    if (directKm < 0.2 && snappedKm > 0.9) return true;

    // General guardrail for severe detours likely caused by roundabout loops.
    if (ratio > 3.2 && snappedKm - directKm > 1.5) return true;

    // Detect repeated revisits within a tight radius (indicative of circling).
    var loopHits = 0;
    for (int i = 0; i < points.length; i++) {
      final step = (points.length / 140).ceil();
      final minJump = math.max(8, step * 4);
      for (int j = i + minJump; j < points.length; j += step) {
        final revisitKm = _haversineKm(points[i], points[j]);
        if (revisitKm < 0.02) {
          loopHits++;
          if (loopHits >= 4 && ratio > 1.8) return true;
        }
      }
    }

    return false;
  }

  static String _osrmProfileForMode(String mode) {
    switch (mode) {
      case 'Walk':
        return 'foot';
      case 'Train':
        return 'driving';
      case 'Ferry':
        return 'driving';
      default:
        return 'driving'; // Jeepney, Bus, FX/Van, Tricycle
    }
  }

  // ── Build OrsRouteResult from GTFS legs ──────────────────────────────────────

  static Future<OrsRouteResult> _buildResult({
    required LatLng origin,
    required LatLng destination,
    required List<TransitLeg> legs,
    required List<List<LatLng>> shapePolylines,
    required String preferredMode,
    required Map<String, dynamic> selectedOriginStop,
    required Map<String, dynamic> selectedDestStop,
  }) async {
    final combinedPolyline = <LatLng>[];
    final steps = <OrsStep>[];
    final firstLeg = legs.first;
    final lastLeg = legs.last;
    final firstLegMode = _inferModeFromRoute(
      routeId: firstLeg.routeId,
      routeType: firstLeg.routeType,
      routeShortName: firstLeg.routeShortName,
      routeLongName: firstLeg.routeLongName,
      preferredMode: preferredMode,
    );
    final lastLegMode = _inferModeFromRoute(
      routeId: lastLeg.routeId,
      routeType: lastLeg.routeType,
      routeShortName: lastLeg.routeShortName,
      routeLongName: lastLeg.routeLongName,
      preferredMode: preferredMode,
    );

    // ── Walk-in ───────────────────────────────────────────────────────────────
    final boardFirst = LatLng(
      (selectedOriginStop['stop_lat'] as num).toDouble(),
      (selectedOriginStop['stop_lon'] as num).toDouble(),
    );
    final walkInKm = _haversineKm(origin, boardFirst);
    if (walkInKm > _minWalkSegmentKm) {
      final walkInPts = await _buildWalkConnectorPolyline(
        origin,
        boardFirst,
        allowRoadSnap: !_isStationBasedLeg(firstLeg, firstLegMode),
      );
      final walkInDistM = _polylineDistanceKm(walkInPts) * 1000;
      combinedPolyline.addAll(walkInPts);
      steps.add(
        OrsStep(
          instruction:
              'Walk to ${selectedOriginStop['stop_name'] ?? firstLeg.boardStopName}',
          distanceMeters: walkInDistM,
          durationSeconds: (walkInDistM / 1000 / _walkSpeedKmh) * 3600,
          suggestedMode: 'Walk',
          estimatedFare: 0.0,
          wayPointStart: 0,
          wayPointEnd: combinedPolyline.length - 1,
        ),
      );
    } else {
      combinedPolyline.add(origin);
    }

    // ── Vehicle legs ──────────────────────────────────────────────────────────
    for (int i = 0; i < legs.length; i++) {
      final leg = legs[i];
      final polyline = shapePolylines[i];
      final mode = _inferModeFromRoute(
        routeId: leg.routeId,
        routeType: leg.routeType,
        routeShortName: leg.routeShortName,
        routeLongName: leg.routeLongName,
        preferredMode: preferredMode,
      );

      final vehicleStartIdx = combinedPolyline.length - 1;

      final toAdd =
          combinedPolyline.isNotEmpty &&
                  polyline.isNotEmpty &&
                  _haversineKm(combinedPolyline.last, polyline.first) < 0.001
              ? polyline.skip(1).toList()
              : polyline;
      combinedPolyline.addAll(toAdd);

      final vehicleEndIdx = combinedPolyline.length - 1;
      final distKm = _polylineDistanceKm(polyline);
      final distM = distKm * 1000;
      final routeLabel = _routeLabelForLeg(leg);

      steps.add(
        OrsStep(
          instruction:
              leg.communityLabel ??
              (routeLabel != null
                  ? 'Ride $mode ($routeLabel) from ${leg.boardStopName} to ${leg.alightStopName}'
                  : 'Ride $mode from ${leg.boardStopName} to ${leg.alightStopName}'),
          distanceMeters: distM,
          durationSeconds: (distKm / _speedForMode(mode)) * 3600,
          suggestedMode: mode,
          estimatedFare:
              leg.communityFare ?? PhFareCalculator.compute(mode, distM),
          isCommunity: leg.isCommunity,
          wayPointStart: vehicleStartIdx,
          wayPointEnd: vehicleEndIdx,
        ),
      );

      // ── Transfer walk ──────────────────────────────────────────────────────
      if (i < legs.length - 1) {
        final nextLeg = legs[i + 1];
        final nextMode = _inferModeFromRoute(
          routeId: nextLeg.routeId,
          routeType: nextLeg.routeType,
          routeShortName: nextLeg.routeShortName,
          routeLongName: nextLeg.routeLongName,
          preferredMode: preferredMode,
        );
        final alightPt = LatLng(leg.alightLat, leg.alightLon);
        final boardPt = LatLng(nextLeg.boardLat, nextLeg.boardLon);
        final transferKm = _haversineKm(alightPt, boardPt);
        final transferRouteLabel = _routeLabelForLeg(nextLeg) ?? 'next line';

        if (transferKm > _minWalkSegmentKm) {
          final transferPts = await _buildWalkConnectorPolyline(
            alightPt,
            boardPt,
            allowRoadSnap:
                !_isStationBasedLeg(leg, mode) &&
                !_isStationBasedLeg(nextLeg, nextMode),
          );
          final transferDistM = _polylineDistanceKm(transferPts) * 1000;
          final tStart = combinedPolyline.length - 1;
          final transferToAdd =
              combinedPolyline.isNotEmpty &&
                      transferPts.isNotEmpty &&
                      _haversineKm(combinedPolyline.last, transferPts.first) <
                          0.001
                  ? transferPts.skip(1).toList()
                  : transferPts;
          combinedPolyline.addAll(transferToAdd);
          steps.add(
            OrsStep(
              instruction:
                  'Transfer: walk from ${leg.alightStopName} to ${nextLeg.boardStopName}, then board $transferRouteLabel',
              distanceMeters: transferDistM,
              durationSeconds: (transferDistM / 1000 / _walkSpeedKmh) * 3600,
              suggestedMode: 'Walk',
              estimatedFare: 0.0,
              wayPointStart: tStart,
              wayPointEnd: combinedPolyline.length - 1,
            ),
          );
        } else {
          final tIdx = combinedPolyline.length - 1;
          steps.add(
            OrsStep(
              instruction:
                  'Transfer at ${leg.alightStopName}: board $transferRouteLabel',
              distanceMeters: 0.0,
              durationSeconds: 45.0,
              suggestedMode: 'Walk',
              estimatedFare: 0.0,
              wayPointStart: tIdx,
              wayPointEnd: tIdx,
            ),
          );
        }
      }
    }

    // ── Walk-out ──────────────────────────────────────────────────────────────
    final alightLast = LatLng(
      (selectedDestStop['stop_lat'] as num).toDouble(),
      (selectedDestStop['stop_lon'] as num).toDouble(),
    );
    final walkOutKm = _haversineKm(alightLast, destination);
    if (walkOutKm > _minWalkSegmentKm) {
      final walkOutPts = await _buildWalkConnectorPolyline(
        alightLast,
        destination,
        allowRoadSnap: !_isStationBasedLeg(lastLeg, lastLegMode),
      );
      final walkOutDistM = _polylineDistanceKm(walkOutPts) * 1000;
      final startIdx = combinedPolyline.length - 1;
      final walkOutToAdd =
          combinedPolyline.isNotEmpty &&
                  walkOutPts.isNotEmpty &&
                  _haversineKm(combinedPolyline.last, walkOutPts.first) < 0.001
              ? walkOutPts.skip(1).toList()
              : walkOutPts;
      combinedPolyline.addAll(walkOutToAdd);
      steps.add(
        OrsStep(
          instruction:
              'Walk from ${selectedDestStop['stop_name'] ?? lastLeg.alightStopName} to destination',
          distanceMeters: walkOutDistM,
          durationSeconds: (walkOutDistM / 1000 / _walkSpeedKmh) * 3600,
          suggestedMode: 'Walk',
          estimatedFare: 0.0,
          wayPointStart: startIdx,
          wayPointEnd: combinedPolyline.length - 1,
        ),
      );
    }

    // ── Totals + BBox ─────────────────────────────────────────────────────────
    final totalDistM = steps.fold(0.0, (s, e) => s + e.distanceMeters);
    final transfers = steps.where((s) => s.suggestedMode != 'Walk').length;
    final totalDurS =
        steps.fold(0.0, (s, e) => s + e.durationSeconds) +
        (transfers > 0 ? transfers * 120.0 : 0.0);

    List<double> bbox = [];
    if (combinedPolyline.isNotEmpty) {
      final lats = combinedPolyline.map((p) => p.latitude);
      final lngs = combinedPolyline.map((p) => p.longitude);
      bbox = [
        lngs.reduce(math.min),
        lats.reduce(math.min),
        lngs.reduce(math.max),
        lats.reduce(math.max),
      ];
    }

    return OrsRouteResult(
      distanceMeters: totalDistM,
      durationSeconds: totalDurS,
      polyline: combinedPolyline,
      steps: steps,
      bbox: bbox,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  static String _inferModeFromRoute({
    required String? routeId,
    required int? routeType,
    required String? routeShortName,
    required String? routeLongName,
    required String preferredMode,
  }) {
    // GTFS route_type is authoritative for rail/ferry and usually bus-like modes.
    if (_isTrainRouteType(routeType)) return 'Train';
    if (routeType == 4) {
      return _allowFerrySuggestions
          ? 'Ferry'
          : (preferredMode == 'Auto' ? 'Jeepney' : preferredMode);
    }

    if (SupabaseRouteService.isEdsaCarouselLeg(
      routeId: routeId,
      routeType: routeType,
      routeShortName: routeShortName,
      routeLongName: routeLongName,
    )) {
      return 'Bus';
    }

    final joinedName =
      '${routeId ?? ''} ${routeShortName ?? ''} ${routeLongName ?? ''}'
        .toLowerCase();

    if (_containsRouteCode(joinedName, 'pub')) {
      return 'Bus';
    }
    if (_containsRouteCode(joinedName, 'puj')) {
      return 'Jeepney';
    }

    // Explicit text signals for bus-like services.
    if (joinedName.contains('bus') ||
        joinedName.contains('carousel') ||
        joinedName.contains('brt')) {
      return 'Bus';
    }
    if (joinedName.contains('uv') ||
        joinedName.contains('uv express') ||
        joinedName.contains('fx') ||
        joinedName.contains('van')) {
      return 'FX/Van';
    }
    if (joinedName.contains('tric') || joinedName.contains('trike')) {
      return 'Tricycle';
    }
    if (joinedName.contains('ferry') || joinedName.contains('pier')) {
      return _allowFerrySuggestions
          ? 'Ferry'
          : (preferredMode == 'Auto' ? 'Jeepney' : preferredMode);
    }
    if (joinedName.contains('mrt') ||
        joinedName.contains('lrt') ||
        joinedName.contains('pnr') ||
        joinedName.contains('rail')) {
      return 'Train';
    }

    // GTFS route_type=3 is commonly shared by bus and jeepney feeds,
    // so we should not hard-force Bus here.
    if (routeType == 700 || routeType == 701 || routeType == 702) {
      return 'Bus';
    }

    // If GTFS metadata is incomplete, respect explicit user mode when valid.
    const validModes = {
      'Walk',
      'Jeepney',
      'Bus',
      'Train',
      'Tricycle',
      'FX/Van',
      'Ferry',
    };
    if (validModes.contains(preferredMode) && preferredMode != 'Walk') {
      return preferredMode;
    }

    // Neutral fallback when no stronger signal exists.
    return 'Jeepney';
  }

  static bool _containsRouteCode(String source, String code) {
    if (source.isEmpty) return false;
    final pattern = RegExp('(^|[^a-z0-9])$code(?=[0-9]|[^a-z0-9]|\$)');
    return pattern.hasMatch(source);
  }

  static bool _isTrainRouteType(int? routeType) {
    if (routeType == null) return false;

    if (routeType == 0 || routeType == 1 || routeType == 2 || routeType == 12) {
      return true;
    }

    if ((routeType >= 100 && routeType <= 117) ||
        (routeType >= 400 && routeType <= 405) ||
        (routeType >= 900 && routeType <= 906)) {
      return true;
    }

    return false;
  }

  static Future<List<LatLng>> _buildTransitLegPolyline({
    required TransitLeg leg,
    required String preferredMode,
  }) async {
    // Community legs already carry the contributor's drawn, verified path.
    final communityPath = leg.communityPath;
    if (communityPath != null && communityPath.length >= 2) {
      return communityPath;
    }

    final board = LatLng(leg.boardLat, leg.boardLon);
    final alight = LatLng(leg.alightLat, leg.alightLon);
    final mode = _inferModeFromRoute(
      routeId: leg.routeId,
      routeType: leg.routeType,
      routeShortName: leg.routeShortName,
      routeLongName: leg.routeLongName,
      preferredMode: preferredMode,
    );
    
    // 1. The GTFS shape is the route's real path, so it decides which roads
    //    the leg follows for every mode — OSRM's fastest-car path between two
    //    stops can leave the jeep's actual route entirely.
    final shapeId = leg.shapeId;
    if (shapeId != null && shapeId.isNotEmpty) {
      List<LatLng> shape = const [];
      try {
        shape = await SupabaseRouteService.getShapePolyline(
          shapeId,
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}
      if (shape.length >= 2) {
        final clipped = _clipShapeToStops(shape, board, alight);
        if (mode == 'Train') return clipped;
        // Road shapes in our feed are station-level (1–3 km between points),
        // so drawn raw they cut corners. Route through them to follow roads.
        final roadFollowed = await _osrmRoute(
          clipped,
          _osrmProfileForMode(mode),
        );
        return roadFollowed ?? clipped;
      }
    }

    // 2. No shape: route through the trip's own stops in order. OSRM's
    //    fastest path between just the two end stops can take different
    //    roads than the vehicle does, and a timeout there leaves a straight
    //    line; the stop-to-stop line is still close to the real route.
    if (leg.viaStops.isNotEmpty) {
      final stopPath = [board, ...leg.viaStops, alight];
      if (mode == 'Train') return stopPath;
      final roadFollowed = await _osrmRoute(
        stopPath,
        _osrmProfileForMode(mode),
      );
      return roadFollowed ?? stopPath;
    }

    if (mode == 'Train') return [board, alight];

    // 3. Nothing known between the two stops: OSRM between them.
    final snapped = await _osrmSnap(board, alight, _osrmProfileForMode(mode));
    if (snapped != null && snapped.length >= 2) {
      // FIX: DO NOT clip OSRM routes. Clipping breaks the geometry 
      // and causes the straight-line bug.
      return snapped; 
    }

    // Ultimate fallback
    return [board, alight];
  }

  static Future<List<LatLng>> _buildWalkConnectorPolyline(
    LatLng from,
    LatLng to, {
    required bool allowRoadSnap,
  }) async {
    if (allowRoadSnap) {
      final snapped = await _osrmSnap(from, to, 'foot');
      if (snapped != null && snapped.length >= 2) {
        return _clipShapeToStops(snapped, from, to);
      }
    }
    return [from, to];
  }

  static bool _isStationBasedLeg(TransitLeg leg, String mode) {
    // Only trains should use direct-line (non-snapped) station connectors.
    // EDSA Carousel is a bus on a road network, so walk connectors to it SHOULD snap to roads.
    if (mode == 'Train') return true;

    return false;
  }

  static List<LatLng> _clipShapeToStops(
    List<LatLng> shape,
    LatLng boardStop,
    LatLng alightStop,
  ) {
    if (shape.length < 2) return [boardStop, alightStop];

    final bIdx = _closestIdx(shape, boardStop);
    final aIdx = _closestIdx(shape, alightStop);
    if (bIdx == aIdx) {
      return [boardStop, alightStop];
    }

    final clipped =
        bIdx < aIdx
            ? shape.sublist(bIdx, aIdx + 1)
            : shape.sublist(aIdx, bIdx + 1).reversed.toList();

    if (clipped.length < 2) {
      return [boardStop, alightStop];
    }

    clipped[0] = boardStop;
    clipped[clipped.length - 1] = alightStop;
    return clipped;
  }

  static int _closestIdx(List<LatLng> polyline, LatLng target) {
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < polyline.length; i++) {
      final d = _haversineKm(polyline[i], target);
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  static double _polylineDistanceKm(List<LatLng> points) {
    double total = 0;
    for (int i = 0; i < points.length - 1; i++) {
      total += _haversineKm(points[i], points[i + 1]);
    }
    return total;
  }

  static double _speedForMode(String mode) {
    switch (mode) {
      case 'Walk':
        return 5.0;
      case 'Jeepney':
        return 20.0;
      case 'Bus':
        return 25.0;
      case 'Train':
        return 40.0;
      case 'Tricycle':
        return 15.0;
      case 'FX/Van':
        return 30.0;
      case 'Ferry':
        return 20.0;
      default:
        return 20.0;
    }
  }

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

  static bool _planHasFerry(TripPlan plan) {
    for (final leg in plan.legs) {
      final type = leg.routeType;
      final short = (leg.routeShortName ?? '').toLowerCase();
      final long = (leg.routeLongName ?? '').toLowerCase();
      if (type == 4) return true;
      if (short.contains('ferry') || short.contains('pier')) return true;
      if (long.contains('ferry') || long.contains('pier')) return true;
    }
    return false;
  }

  static String? _routeLabelForLeg(TransitLeg leg) {
    final short = leg.routeShortName?.trim() ?? '';
    final long = leg.routeLongName?.trim() ?? '';

    if (short.isEmpty && long.isEmpty) return null;
    if (short.isEmpty) return long;
    if (long.isEmpty) return short;

    final same = short.toLowerCase() == long.toLowerCase();
    if (same) return short;
    return '$short - $long';
  }

  static double _rad(double deg) => deg * math.pi / 180;
}