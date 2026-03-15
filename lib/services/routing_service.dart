import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config.dart';
import '../models/ors_route_result.dart';
import '../repositories/route_cache_repository.dart';
import 'overpass_route_service.dart';
import 'transport_mode_inference.dart';

/// Fetches road-snapped routes from ORS, enriches step labels via Overpass,
/// applies realistic transit time multipliers, and caches in Firestore.
///
/// ## Accuracy improvements
///   Issue 2 — Multi-modal routing: for non-Walk modes, tries to find nearby
///     stops via Overpass and route Walk→Stop→Transit→Stop→Walk.
///   Issue 3 — Duration multipliers: ORS returns car drive time; each mode
///     gets a multiplier reflecting real PH transit speeds.
///   Issue 4 — Stop snapping: uses [OverpassRouteService.findNearestStop]
///     to anchor route endpoints to actual bus stops.
///   Issue 6 — Cache key includes mode (handled in RouteCacheRepository).
class RoutingService {
  static const _baseUrl = 'https://api.openrouteservice.org/v2/directions';

  static const _modeToProfile = {
    'Walk':     'foot-walking',
    'Jeepney':  'driving-car',
    'Bus':      'driving-hgv',
    'Train':    'driving-car',
    'Tricycle': 'foot-walking',
    'FX/Van':   'driving-car',
    'Ferry':    'driving-car',
  };

  // ── Transit time multipliers (Issue 3) ─────────────────────────────────────
  //
  // ORS gives car/pedestrian travel time without stops or traffic.
  // These multipliers convert ORS time to realistic PH transit time.
  //
  // Jeepney ×2.5 — heavy Metro Manila traffic + frequent loading stops
  // Bus     ×2.0 — fewer stops than jeepney but still congested
  // Train   ×1.0 — MRT/LRT runs on fixed schedule, ORS time is reasonable
  // FX/Van  ×1.8 — expressway ramps offset partly by arterial congestion
  // Tricycle×1.5 — slow but fewer traffic interactions
  // Walk    ×1.1 — ORS slightly underestimates (crossings, footpaths)
  // Ferry   ×1.2 — schedule gaps + boarding time
  static const _durationMultipliers = {
    'Walk':     1.1,
    'Jeepney':  2.5,
    'Bus':      2.0,
    'Train':    1.0,
    'Tricycle': 1.5,
    'FX/Van':   1.8,
    'Ferry':    1.2,
  };

  // Minimum walk distance before adding a walk-in / walk-out segment
  static const _minWalkSegmentKm = 0.08; // 80 m

  static const _viaThresholdKm = 5.0;
  static const _mmMinLat = 14.35, _mmMaxLat = 14.80;
  static const _mmMinLng = 120.90, _mmMaxLng = 121.20;
  static const _edsaLng  = 121.0389;

  static String profileForMode(String mode) =>
      _modeToProfile[mode] ?? 'driving-car';

  // ── Public API ──────────────────────────────────────────────────────────────

  static Future<OrsRouteResult?> getRoute({
    required String originName,
    required LatLng origin,
    required String destinationName,
    required LatLng destination,
    String mode = 'Jeepney',
  }) async {
    final profile = profileForMode(mode);

    // Issue 6 — cache key now includes mode
    final cached = await RouteCacheRepository.get(
      originName, destinationName, mode, profile,
    );
    if (cached != null) return cached;

    // Issue 2 — attempt multi-modal (walk-to-stop + transit + walk-from-stop)
    // for all non-Walk, non-Train modes when trip is long enough
    OrsRouteResult? result;
    final directKm = _haversineKm(origin, destination);

    if (mode != 'Walk' && mode != 'Train' && directKm > 0.5) {
      result = await _getMultiModalRoute(
        origin: origin, destination: destination,
        profile: profile, mode: mode,
      );
      if (result != null) {
        debugPrint('[RoutingService] Multi-modal route succeeded');
      }
    }

    // Fall back to direct ORS routing if multi-modal failed or was skipped
    result ??= await _fetchFromOrs(
      origin: origin, destination: destination,
      profile: profile, mode: mode,
    );

    if (result == null) return null;

    // Issue 6 — cache with mode included
    RouteCacheRepository.put(originName, destinationName, mode, profile, result);
    return result;
  }

  // ── Multi-modal routing (Issues 2 & 4) ─────────────────────────────────────

  /// Tries to build a Walk→Transit→Walk route by snapping origin/destination
  /// to nearby transit stops via Overpass.
  ///
  /// Returns null (causing caller to fall back to direct ORS) when:
  ///   • No stops found within 400 m
  ///   • Overpass times out
  ///   • Any of the three ORS calls fails
  static Future<OrsRouteResult?> _getMultiModalRoute({
    required LatLng origin,
    required LatLng destination,
    required String profile,
    required String mode,
  }) async {
    // Find nearest stops in parallel — cap at 8 s total
    List<LatLng?> stops;
    try {
      stops = await Future.wait([
        OverpassRouteService.findNearestStop(origin, mode),
        OverpassRouteService.findNearestStop(destination, mode),
      ]).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      debugPrint('[RoutingService] Stop finder timed out');
      return null;
    }

    final originStop = stops[0];
    final destStop   = stops[1];

    if (originStop == null || destStop == null) {
      debugPrint('[RoutingService] No stops found — using direct route');
      return null;
    }

    // If the stops are the same (very short transit trip), skip multi-modal
    if (_haversineKm(originStop, destStop) < 0.1) {
      debugPrint('[RoutingService] Stops too close — using direct route');
      return null;
    }

    final walkInKm  = _haversineKm(origin, originStop);
    final walkOutKm = _haversineKm(destination, destStop);

    debugPrint(
      '[RoutingService] Multi-modal: '
      'walk-in ${walkInKm.toStringAsFixed(2)} km, '
      'walk-out ${walkOutKm.toStringAsFixed(2)} km',
    );

    // Build futures for the segments we actually need
    final futures = <Future<OrsRouteResult?>>[];
    final segmentModes = <String>[];

    if (walkInKm > _minWalkSegmentKm) {
      futures.add(_fetchFromOrs(
        origin: origin, destination: originStop,
        profile: 'foot-walking', mode: 'Walk',
      ));
      segmentModes.add('Walk');
    }

    futures.add(_fetchFromOrs(
      origin: originStop, destination: destStop,
      profile: profile, mode: mode,
    ));
    segmentModes.add(mode);

    if (walkOutKm > _minWalkSegmentKm) {
      futures.add(_fetchFromOrs(
        origin: destStop, destination: destination,
        profile: 'foot-walking', mode: 'Walk',
      ));
      segmentModes.add('Walk');
    }

    final results = await Future.wait(futures);
    if (results.any((r) => r == null)) {
      debugPrint('[RoutingService] A multi-modal segment failed');
      return null;
    }

    return _stitchSegments(results.cast<OrsRouteResult>());
  }

  /// Combines multiple [OrsRouteResult] segments into a single result.
  ///
  /// Polyline junction points between segments are deduplicated (the first
  /// point of each non-initial segment is the same as the last point of the
  /// previous one — the transit stop — so we skip it). Waypoint indices in
  /// steps are offset accordingly.
  static OrsRouteResult _stitchSegments(List<OrsRouteResult> segments) {
    if (segments.length == 1) return segments.first;

    final combinedPolyline = <LatLng>[];
    final combinedSteps    = <OrsStep>[];
    double totalDist = 0, totalDur = 0;
    final bboxes = <List<double>>[];

    for (int s = 0; s < segments.length; s++) {
      final seg = segments[s];
      if (seg.polyline.isEmpty) continue;

      // Offset = index of the junction point (last point of previous segment)
      // For the first segment offset is 0; for subsequent segments the
      // junction point is already in the combined polyline at index (length-1).
      final int offset;
      if (s == 0) {
        combinedPolyline.addAll(seg.polyline);
        offset = 0;
      } else {
        offset = combinedPolyline.length - 1; // junction is at this index
        // Skip the first point (duplicate junction)
        if (seg.polyline.length > 1) {
          combinedPolyline.addAll(seg.polyline.skip(1));
        }
      }

      totalDist += seg.distanceMeters;
      totalDur  += seg.durationSeconds;
      if (seg.bbox.length >= 4) bboxes.add(seg.bbox);

      for (final step in seg.steps) {
        combinedSteps.add(OrsStep(
          instruction:    step.instruction,
          distanceMeters: step.distanceMeters,
          durationSeconds:step.durationSeconds,
          suggestedMode:  step.suggestedMode,
          estimatedFare:  step.estimatedFare,
          wayPointStart:  step.wayPointStart + offset,
          wayPointEnd:    step.wayPointEnd   + offset,
        ));
      }
    }

    // Merge bounding boxes
    List<double> mergedBbox = [];
    if (bboxes.isNotEmpty) {
      mergedBbox = [
        bboxes.map((b) => b[0]).reduce(math.min),
        bboxes.map((b) => b[1]).reduce(math.min),
        bboxes.map((b) => b[2]).reduce(math.max),
        bboxes.map((b) => b[3]).reduce(math.max),
      ];
    }

    return OrsRouteResult(
      distanceMeters: totalDist,
      durationSeconds: totalDur,
      polyline: combinedPolyline,
      steps: combinedSteps,
      bbox: mergedBbox,
    );
  }

  // ── ORS fetch ───────────────────────────────────────────────────────────────

  static Future<OrsRouteResult?> _fetchFromOrs({
    required LatLng origin,
    required LatLng destination,
    required String profile,
    String mode = 'Jeepney',
  }) async {
    final apiKey = Config.openRouteServiceApiKey;
    if (apiKey.isEmpty) {
      debugPrint('[RoutingService] API key missing.');
      return null;
    }

    final coordinates = <List<double>>[[origin.longitude, origin.latitude]];
    if (_haversineKm(origin, destination) > _viaThresholdKm) {
      final via = _inferViaWaypoint(origin, destination, mode);
      if (via != null) coordinates.add([via.longitude, via.latitude]);
    }
    coordinates.add([destination.longitude, destination.latitude]);

    final avoidFeatures = (mode == 'Jeepney' || mode == 'Tricycle')
        ? ['tollways', 'highways'] : <String>[];

    final body = jsonEncode({
      'coordinates': coordinates,
      'instructions': true,
      'geometry': true,
      if (avoidFeatures.isNotEmpty) 'options': {'avoid_features': avoidFeatures},
    });

    try {
      debugPrint('[RoutingService] POST $profile ($mode)');
      final response = await http.post(
        Uri.parse('$_baseUrl/$profile/geojson'),
        headers: {'Authorization': apiKey, 'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 15));

      debugPrint('[RoutingService] ORS ${response.statusCode}');
      if (response.statusCode == 429) { debugPrint('[RoutingService] Rate limit.'); return null; }
      if (response.statusCode != 200) { debugPrint('[RoutingService] Error: ${response.body}'); return null; }

      return await _parseOrsResponse(response.body, mode);
    } catch (e) {
      debugPrint('[RoutingService] Exception: $e');
      return null;
    }
  }

  // ── Parsing + enrichment ────────────────────────────────────────────────────

  static Future<OrsRouteResult?> _parseOrsResponse(String body, String mode) async {
    try {
      final data    = jsonDecode(body) as Map<String, dynamic>;
      final feature = (data['features'] as List).first as Map<String, dynamic>;

      final polyline = (feature['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      final summary    = feature['properties']['summary'] as Map<String, dynamic>;
      final distMeters = (summary['distance'] as num).toDouble();
      final rawDurSec  = (summary['duration'] as num).toDouble();

      // Issue 3 — apply transit time multiplier
      final multiplier   = _durationMultipliers[mode] ?? 1.5;
      final adjDurSec    = rawDurSec * multiplier;
      debugPrint('[RoutingService] Duration: raw ${rawDurSec.toInt()}s × $multiplier = ${adjDurSec.toInt()}s ($mode)');

      final rawBbox = data['bbox'] as List?;
      final bbox    = rawBbox?.map((v) => (v as num).toDouble()).toList() ?? <double>[];

      final rawSteps = <OrsStep>[];
      for (final segment in (feature['properties']['segments'] as List? ?? [])) {
        for (final s in (segment['steps'] as List? ?? [])) {
          final wp = s['way_points'] as List?;
          rawSteps.add(OrsStep(
            instruction:     s['instruction']  as String? ?? '',
            distanceMeters:  (s['distance']    as num?)?.toDouble() ?? 0,
            durationSeconds: (s['duration']    as num?)?.toDouble() ?? 0,
            wayPointStart:   wp != null ? (wp[0] as int) : 0,
            wayPointEnd:     wp != null ? (wp[1] as int) : 0,
          ));
        }
      }

      // Overpass enrichment — step midpoint queries with overall 4 s cap
      final nonNullIdx    = <int>[];
      final nonNullCoords = <LatLng>[];
      for (int i = 0; i < rawSteps.length; i++) {
        final step = rawSteps[i];
        if (step.distanceMeters < 50 || polyline.isEmpty) continue;
        final start  = step.wayPointStart.clamp(0, polyline.length - 1);
        final end    = step.wayPointEnd.clamp(0, polyline.length - 1);
        final midIdx = ((start + end) / 2).round().clamp(0, polyline.length - 1);
        nonNullIdx.add(i);
        nonNullCoords.add(polyline[midIdx]);
      }

      final overpassModes = List<String?>.filled(rawSteps.length, null);
      if (nonNullCoords.isNotEmpty) {
        final partial = await OverpassRouteService.getModesForSteps(
          stepMidpoints: nonNullCoords,
        );
        for (int i = 0; i < nonNullIdx.length; i++) {
          overpassModes[nonNullIdx[i]] = partial[i];
        }
      }

      final enrichedSteps = TransitModeInferrer.inferModes(
        rawSteps,
        dominantMode:  mode,
        overpassModes: overpassModes,
      );

      return OrsRouteResult(
        distanceMeters:  distMeters,
        durationSeconds: adjDurSec, // adjusted, not raw ORS time
        polyline:        polyline,
        steps:           enrichedSteps,
        bbox:            bbox,
      );
    } catch (e) {
      debugPrint('[RoutingService] Parse error: $e');
      return null;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static LatLng? _inferViaWaypoint(LatLng origin, LatLng dest, String mode) {
    final midLat = (origin.latitude  + dest.latitude)  / 2;
    final midLng = (origin.longitude + dest.longitude) / 2;
    if (!_isMetroManila(midLat, midLng)) return null;
    if (mode == 'Bus' && (dest.longitude - origin.longitude).abs() > 0.02) {
      return LatLng(midLat, _edsaLng);
    }
    return null;
  }

  static double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _rad(b.latitude  - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  static bool _isMetroManila(double lat, double lng) =>
      lat >= _mmMinLat && lat <= _mmMaxLat &&
      lng >= _mmMinLng && lng <= _mmMaxLng;
}