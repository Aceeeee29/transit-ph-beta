import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
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
  static const _minWalkSegmentKm           = 0.08;
  static const _walkSpeedKmh               = 5.0;
  static const _stopSearchRadiusKm         = 0.5;
  static const _stopSearchRadiusExpandedKm = 1.5;

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
    const cacheProfile = 'supabase-gtfs-v2';

    final cached = await RouteCacheRepository.get(
      originName, destinationName, mode, cacheProfile,
    );
    if (cached != null) {
      debugPrint('[RoutingService] Cache hit');
      return cached;
    }

    final result = await _getGtfsRoute(
      origin:        origin,
      destination:   destination,
      preferredMode: mode,
    );

    RouteCacheRepository.put(
        originName, destinationName, mode, cacheProfile, result);
    return result;
  }

  /// Lightweight road-snap between two points for map drawing in the
  /// Contribute screen.
  ///
  /// Calls OSRM directly — no Supabase, no GTFS, no caching.
  /// Returns null if OSRM is unreachable so the caller can fall back to a
  /// straight line.
  static Future<OrsRouteResult?> snapToRoad({
    required LatLng origin,
    required LatLng destination,
    String mode = 'Jeepney',
  }) async {
    final profile = _osrmProfileForMode(mode);
    final pts     = await _osrmSnap(origin, destination, profile);
    if (pts == null || pts.length < 2) return null;

    final distKm = _polylineDistanceKm(pts);
    final distM  = distKm * 1000;
    final durS   = (distKm / _speedForMode(mode)) * 3600;

    return OrsRouteResult(
      distanceMeters:  distM,
      durationSeconds: durS,
      polyline:        pts,
      steps:           [],
      bbox:            [],
    );
  }

  // ── GTFS routing with fallback ────────────────────────────────────────────────

  static Future<OrsRouteResult> _getGtfsRoute({
    required LatLng origin,
    required LatLng destination,
    required String preferredMode,
  }) async {
    // ── Step 1: Nearest stops ─────────────────────────────────────────────────
    List<Map<String, dynamic>?> stops;
    try {
      stops = await Future.wait([
        SupabaseRouteService.findNearestStop(origin,
            radiusKm: _stopSearchRadiusKm),
        SupabaseRouteService.findNearestStop(destination,
            radiusKm: _stopSearchRadiusKm),
      ]).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const RoutingException(
          'Stop lookup timed out. Check your internet connection.');
    }

    // Expand radius if either stop missing
    if (stops[0] == null || stops[1] == null) {
      try {
        stops = await Future.wait([
          stops[0] != null
              ? Future.value(stops[0])
              : SupabaseRouteService.findNearestStop(origin,
                  radiusKm: _stopSearchRadiusExpandedKm),
          stops[1] != null
              ? Future.value(stops[1])
              : SupabaseRouteService.findNearestStop(destination,
                  radiusKm: _stopSearchRadiusExpandedKm),
        ]).timeout(const Duration(seconds: 8));
      } on TimeoutException {
        throw const RoutingException(
            'Stop lookup timed out. Check your internet connection.');
      }
    }

    final originStopData = stops[0];
    final destStopData   = stops[1];

    // ── Fallback A: no stops at all — walk-only route ─────────────────────────
    if (originStopData == null || destStopData == null) {
      debugPrint('[RoutingService] No stops found — using walk fallback');
      return _buildFallbackRoute(
        origin:        origin,
        destination:   destination,
        preferredMode: 'Walk',
        note:          'No transit stops found nearby. Showing estimated walking route.',
      );
    }

    final originStopId = originStopData['stop_id'].toString();
    final destStopId   = destStopData['stop_id'].toString();

    debugPrint('[RoutingService] Origin stop: ${originStopData['stop_name']} ($originStopId)');
    debugPrint('[RoutingService] Dest stop:   ${destStopData['stop_name']} ($destStopId)');

    if (originStopId == destStopId) {
      return _buildFallbackRoute(
        origin:        origin,
        destination:   destination,
        preferredMode: 'Walk',
        note:          'Origin and destination are very close. Showing walking route.',
      );
    }

    // ── Step 2: GTFS trip plan ────────────────────────────────────────────────
    TripPlan? plan;
    try {
      plan = await SupabaseRouteService.findTripPlan(originStopId, destStopId)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const RoutingException(
          'Route lookup timed out. Check your internet connection.');
    } catch (e) {
      debugPrint('[RoutingService] Trip plan error: $e');
    }

    // ── Fallback B: no GTFS connection — estimated direct route ───────────────
    if (plan == null) {
      debugPrint('[RoutingService] No GTFS connection — using direct fallback');
      return _buildFallbackRoute(
        origin:        origin,
        destination:   destination,
        preferredMode: preferredMode,
        originStop:    LatLng(
          (originStopData['stop_lat'] as num).toDouble(),
          (originStopData['stop_lon'] as num).toDouble(),
        ),
        originStopName: originStopData['stop_name'] as String? ?? 'Stop',
        destStop:       LatLng(
          (destStopData['stop_lat'] as num).toDouble(),
          (destStopData['stop_lon'] as num).toDouble(),
        ),
        destStopName:   destStopData['stop_name'] as String? ?? 'Stop',
        note:           'No connected transit route found in current data. '
                        'Showing estimated direct route.',
      );
    }

    debugPrint('[RoutingService] Plan: ${plan.legs.length} leg(s)');

    // ── Step 3: Road-snap each leg via OSRM ──────────────────────────────────
    final shapePolylines = await Future.wait(
      plan.legs.map((leg) async {
        final board  = LatLng(leg.boardLat,  leg.boardLon);
        final alight = LatLng(leg.alightLat, leg.alightLon);
        final osrmMode = _osrmProfileForMode(
            _inferModeFromRoute(leg.routeType ?? 3, leg.routeShortName ?? '', 'Jeepney'));

        // Try OSRM snap first
        final snapped = await _osrmSnap(board, alight, osrmMode);
        if (snapped != null && snapped.length >= 2) return snapped;

        // Fall back to GTFS shape clipped to stops
        if (leg.shapeId != null && leg.shapeId!.isNotEmpty) {
          try {
            final pts = await SupabaseRouteService
                .getShapePolyline(leg.shapeId!)
                .timeout(const Duration(seconds: 8));
            if (pts.length >= 2) {
              return _clipShapeToStops(pts, board, alight);
            }
          } catch (_) {}
        }

        // Last resort: straight line
        return [board, alight];
      }),
    );

    return _buildResult(
      origin:         origin,
      destination:    destination,
      legs:           plan.legs,
      shapePolylines: shapePolylines,
      preferredMode:  preferredMode,
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
    final steps            = <OrsStep>[];

    final bool hasStops = originStop != null && destStop != null;

    // ── Walk-in (origin → nearest stop) ──────────────────────────────────────
    if (hasStops) {
      final walkInKm = _haversineKm(origin, originStop!);
      if (walkInKm > _minWalkSegmentKm) {
        final walkPts = await _osrmSnap(origin, originStop, 'foot') ??
            [origin, originStop];
        final walkDistM = _polylineDistanceKm(walkPts) * 1000;
        final startIdx  = combinedPolyline.length;
        combinedPolyline.addAll(walkPts);
        steps.add(OrsStep(
          instruction:     'Walk to ${originStopName ?? 'nearest stop'}',
          distanceMeters:  walkDistM,
          durationSeconds: (walkDistM / 1000 / _walkSpeedKmh) * 3600,
          suggestedMode:   'Walk',
          estimatedFare:   0.0,
          wayPointStart:   startIdx,
          wayPointEnd:     combinedPolyline.length - 1,
        ));
      } else {
        combinedPolyline.add(originStop!);
      }
    } else {
      combinedPolyline.add(origin);
    }

    // ── Main estimated ride / walk ────────────────────────────────────────────
    final ridePtA   = hasStops ? originStop! : origin;
    final ridePtB   = hasStops ? destStop!   : destination;
    final rideMode  = preferredMode == 'Walk' ? 'Walk' : preferredMode;
    final osrmProf  = _osrmProfileForMode(rideMode);

    final ridePts   = await _osrmSnap(ridePtA, ridePtB, osrmProf) ??
        [ridePtA, ridePtB];

    final rideDistM = _polylineDistanceKm(ridePts) * 1000;
    final rideSpeed = _speedForMode(rideMode);
    final rideDurS  = (rideDistM / 1000 / rideSpeed) * 3600;
    final rideFare  = PhFareCalculator.compute(rideMode, rideDistM);

    final rideStartIdx = combinedPolyline.isEmpty
        ? 0
        : combinedPolyline.length - 1;

    final rideToAdd = combinedPolyline.isNotEmpty &&
            ridePts.isNotEmpty &&
            _haversineKm(combinedPolyline.last, ridePts.first) < 0.001
        ? ridePts.skip(1).toList()
        : ridePts;
    combinedPolyline.addAll(rideToAdd);

    final rideLabel = hasStops
        ? '[Estimated] $rideMode from ${originStopName ?? 'start'} to ${destStopName ?? 'destination'}'
        : '[Estimated] $rideMode to destination';

    steps.add(OrsStep(
      instruction:     rideLabel,
      distanceMeters:  rideDistM,
      durationSeconds: rideDurS,
      suggestedMode:   rideMode,
      estimatedFare:   rideFare,
      wayPointStart:   rideStartIdx,
      wayPointEnd:     combinedPolyline.length - 1,
    ));

    // ── Walk-out (dest stop → destination) ────────────────────────────────────
    if (hasStops) {
      final walkOutKm = _haversineKm(destStop!, destination);
      if (walkOutKm > _minWalkSegmentKm) {
        final walkPts = await _osrmSnap(destStop, destination, 'foot') ??
            [destStop, destination];
        final walkDistM  = _polylineDistanceKm(walkPts) * 1000;
        final startIdx   = combinedPolyline.length - 1;
        final toAdd = _haversineKm(combinedPolyline.last, walkPts.first) < 0.001
            ? walkPts.skip(1).toList()
            : walkPts;
        combinedPolyline.addAll(toAdd);
        steps.add(OrsStep(
          instruction:     'Walk from ${destStopName ?? 'stop'} to destination',
          distanceMeters:  walkDistM,
          durationSeconds: (walkDistM / 1000 / _walkSpeedKmh) * 3600,
          suggestedMode:   'Walk',
          estimatedFare:   0.0,
          wayPointStart:   startIdx,
          wayPointEnd:     combinedPolyline.length - 1,
        ));
      }
    }

    // ── Totals + BBox ─────────────────────────────────────────────────────────
    final totalDistM = steps.fold(0.0, (s, e) => s + e.distanceMeters);
    final totalDurS  = steps.fold(0.0, (s, e) => s + e.durationSeconds);

    List<double> bbox = [];
    if (combinedPolyline.isNotEmpty) {
      final lats = combinedPolyline.map((p) => p.latitude);
      final lngs = combinedPolyline.map((p) => p.longitude);
      bbox = [
        lngs.reduce(math.min), lats.reduce(math.min),
        lngs.reduce(math.max), lats.reduce(math.max),
      ];
    }

    debugPrint('[RoutingService] Fallback route built — $note');

    return OrsRouteResult(
      distanceMeters:  totalDistM,
      durationSeconds: totalDurS,
      polyline:        combinedPolyline,
      steps:           steps,
      bbox:            bbox,
    );
  }

  // ── OSRM road snapping ────────────────────────────────────────────────────────

  static Future<List<LatLng>?> _osrmSnap(
    LatLng from,
    LatLng to,
    String profile,
  ) async {
    try {
      final coords =
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
      final uri = Uri.parse(
          '$_osrmBase/$profile/$coords?overview=full&geometries=geojson');

      final response =
          await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final data  = jsonDecode(response.body) as Map<String, dynamic>;
      final code  = data['code'] as String?;
      if (code != 'Ok') return null;

      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final geometry    = routes[0]['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      return coordinates
          .map((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ))
          .toList();
    } catch (e) {
      debugPrint('[OSRM] Snap failed ($profile): $e');
      return null;
    }
  }

  static String _osrmProfileForMode(String mode) {
    switch (mode) {
      case 'Walk':    return 'foot';
      case 'Train':   return 'driving';
      case 'Ferry':   return 'driving';
      default:        return 'driving'; // Jeepney, Bus, FX/Van, Tricycle
    }
  }

  // ── Build OrsRouteResult from GTFS legs ──────────────────────────────────────

  static OrsRouteResult _buildResult({
    required LatLng origin,
    required LatLng destination,
    required List<TransitLeg> legs,
    required List<List<LatLng>> shapePolylines,
    required String preferredMode,
  }) {
    final combinedPolyline = <LatLng>[];
    final steps            = <OrsStep>[];
    final firstLeg         = legs.first;
    final lastLeg          = legs.last;

    // ── Walk-in ───────────────────────────────────────────────────────────────
    final boardFirst = LatLng(firstLeg.boardLat, firstLeg.boardLon);
    final walkInKm   = _haversineKm(origin, boardFirst);
    if (walkInKm > _minWalkSegmentKm) {
      combinedPolyline.add(origin);
      combinedPolyline.add(boardFirst);
      steps.add(OrsStep(
        instruction:     'Walk to ${firstLeg.boardStopName}',
        distanceMeters:  walkInKm * 1000,
        durationSeconds: (walkInKm / _walkSpeedKmh) * 3600,
        suggestedMode:   'Walk',
        estimatedFare:   0.0,
        wayPointStart:   0,
        wayPointEnd:     1,
      ));
    } else {
      combinedPolyline.add(origin);
    }

    // ── Vehicle legs ──────────────────────────────────────────────────────────
    for (int i = 0; i < legs.length; i++) {
      final leg      = legs[i];
      final polyline = shapePolylines[i];
      final mode     = _inferModeFromRoute(
          leg.routeType ?? 3, leg.routeShortName ?? '', preferredMode);

      final vehicleStartIdx = combinedPolyline.length - 1;

      final toAdd = combinedPolyline.isNotEmpty &&
              polyline.isNotEmpty &&
              _haversineKm(combinedPolyline.last, polyline.first) < 0.001
          ? polyline.skip(1).toList()
          : polyline;
      combinedPolyline.addAll(toAdd);

      final vehicleEndIdx = combinedPolyline.length - 1;
      final distKm        = _polylineDistanceKm(polyline);
      final distM         = distKm * 1000;

      steps.add(OrsStep(
        instruction:     leg.routeShortName?.isNotEmpty == true
            ? 'Ride $mode (${leg.routeShortName}) from ${leg.boardStopName} to ${leg.alightStopName}'
            : 'Ride $mode from ${leg.boardStopName} to ${leg.alightStopName}',
        distanceMeters:  distM,
        durationSeconds: (distKm / _speedForMode(mode)) * 3600,
        suggestedMode:   mode,
        estimatedFare:   PhFareCalculator.compute(mode, distM),
        wayPointStart:   vehicleStartIdx,
        wayPointEnd:     vehicleEndIdx,
      ));

      // ── Transfer walk ──────────────────────────────────────────────────────
      if (i < legs.length - 1) {
        final nextLeg    = legs[i + 1];
        final alightPt   = LatLng(leg.alightLat,   leg.alightLon);
        final boardPt    = LatLng(nextLeg.boardLat, nextLeg.boardLon);
        final transferKm = _haversineKm(alightPt, boardPt);
        if (transferKm > _minWalkSegmentKm) {
          final tStart = combinedPolyline.length - 1;
          combinedPolyline.add(boardPt);
          steps.add(OrsStep(
            instruction:     'Transfer: walk from ${leg.alightStopName} to ${nextLeg.boardStopName}',
            distanceMeters:  transferKm * 1000,
            durationSeconds: (transferKm / _walkSpeedKmh) * 3600,
            suggestedMode:   'Walk',
            estimatedFare:   0.0,
            wayPointStart:   tStart,
            wayPointEnd:     combinedPolyline.length - 1,
          ));
        }
      }
    }

    // ── Walk-out ──────────────────────────────────────────────────────────────
    final alightLast = LatLng(lastLeg.alightLat, lastLeg.alightLon);
    final walkOutKm  = _haversineKm(alightLast, destination);
    if (walkOutKm > _minWalkSegmentKm) {
      final startIdx = combinedPolyline.length - 1;
      combinedPolyline.add(destination);
      steps.add(OrsStep(
        instruction:     'Walk from ${lastLeg.alightStopName} to destination',
        distanceMeters:  walkOutKm * 1000,
        durationSeconds: (walkOutKm / _walkSpeedKmh) * 3600,
        suggestedMode:   'Walk',
        estimatedFare:   0.0,
        wayPointStart:   startIdx,
        wayPointEnd:     combinedPolyline.length - 1,
      ));
    }

    // ── Totals + BBox ─────────────────────────────────────────────────────────
    final totalDistM = steps.fold(0.0, (s, e) => s + e.distanceMeters);
    final transfers  = steps.where((s) => s.suggestedMode != 'Walk').length;
    final totalDurS  = steps.fold(0.0, (s, e) => s + e.durationSeconds)
        + (transfers > 0 ? transfers * 120.0 : 0.0);

    List<double> bbox = [];
    if (combinedPolyline.isNotEmpty) {
      final lats = combinedPolyline.map((p) => p.latitude);
      final lngs = combinedPolyline.map((p) => p.longitude);
      bbox = [
        lngs.reduce(math.min), lats.reduce(math.min),
        lngs.reduce(math.max), lats.reduce(math.max),
      ];
    }

    return OrsRouteResult(
      distanceMeters:  totalDistM,
      durationSeconds: totalDurS,
      polyline:        combinedPolyline,
      steps:           steps,
      bbox:            bbox,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  static String _inferModeFromRoute(
      int routeType, String shortName, String preferredMode) {
    if (routeType == 0 || routeType == 1 || routeType == 2) return 'Train';
    if (routeType == 4) return 'Ferry';
    if (preferredMode != 'Walk') return preferredMode;
    final name = shortName.toLowerCase();
    if (name.contains('bus') || name.contains('carousel') ||
        name.contains('brt') || name.contains('uvex')) return 'Bus';
    if (name.contains('fx') || name.contains('uv') ||
        name.contains('van')) return 'FX/Van';
    return 'Jeepney';
  }

  static List<LatLng> _clipShapeToStops(
      List<LatLng> shape, LatLng boardStop, LatLng alightStop) {
    if (shape.length < 2) return shape;
    int bIdx = _closestIdx(shape, boardStop);
    int aIdx = _closestIdx(shape, alightStop);
    if (bIdx == aIdx) return shape;
    if (bIdx > aIdx) {
      final rev = shape.reversed.toList();
      return rev.sublist(shape.length - 1 - bIdx, shape.length - 1 - aIdx + 1);
    }
    return shape.sublist(bIdx, aIdx + 1);
  }

  static int _closestIdx(List<LatLng> polyline, LatLng target) {
    int best = 0; double bestDist = double.infinity;
    for (int i = 0; i < polyline.length; i++) {
      final d = _haversineKm(polyline[i], target);
      if (d < bestDist) { bestDist = d; best = i; }
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
      case 'Walk':     return 5.0;
      case 'Jeepney':  return 20.0;
      case 'Bus':      return 25.0;
      case 'Train':    return 40.0;
      case 'Tricycle': return 15.0;
      case 'FX/Van':   return 30.0;
      case 'Ferry':    return 20.0;
      default:         return 20.0;
    }
  }

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