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

  static const _durationMultipliers = {
    'Walk':     1.1,
    'Jeepney':  2.5,
    'Bus':      2.0,
    'Train':    1.0,
    'Tricycle': 1.5,
    'FX/Van':   1.8,
    'Ferry':    1.2,
  };

  static const _minWalkSegmentKm = 0.08;
  static const _viaThresholdKm   = 5.0;
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

    final cached = await RouteCacheRepository.get(
      originName, destinationName, mode, profile,
    );
    if (cached != null) return cached;

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

    result ??= await _fetchFromOrs(
      origin: origin, destination: destination,
      profile: profile, mode: mode,
    );

    if (result == null) return null;

    RouteCacheRepository.put(originName, destinationName, mode, profile, result);
    return result;
  }

  // ── Multi-modal routing ─────────────────────────────────────────────────────

  static Future<OrsRouteResult?> _getMultiModalRoute({
    required LatLng origin,
    required LatLng destination,
    required String profile,
    required String mode,
  }) async {
    // Find nearest stops via Supabase (replaces Overpass)
    List<Map<String, dynamic>?> stops;
    try {
      stops = await Future.wait([
        SupabaseRouteService.findNearestStop(origin),
        SupabaseRouteService.findNearestStop(destination),
      ]).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      debugPrint('[RoutingService] Stop finder timed out');
      return null;
    }

    final originStopData = stops[0];
    final destStopData   = stops[1];

    if (originStopData == null || destStopData == null) {
      debugPrint('[RoutingService] No stops found — using direct route');
      return null;
    }

    final originStop = LatLng(
      (originStopData['stop_lat'] as num).toDouble(),
      (originStopData['stop_lon'] as num).toDouble(),
    );
    final destStop = LatLng(
      (destStopData['stop_lat'] as num).toDouble(),
      (destStopData['stop_lon'] as num).toDouble(),
    );

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

    final futures      = <Future<OrsRouteResult?>>[];
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

  // ── Stitch segments ─────────────────────────────────────────────────────────

  static OrsRouteResult _stitchSegments(List<OrsRouteResult> segments) {
    if (segments.length == 1) return segments.first;

    final combinedPolyline = <LatLng>[];
    final combinedSteps    = <OrsStep>[];
    double totalDist = 0, totalDur = 0;
    final bboxes = <List<double>>[];

    for (int s = 0; s < segments.length; s++) {
      final seg = segments[s];
      if (seg.polyline.isEmpty) continue;

      final int offset;
      if (s == 0) {
        combinedPolyline.addAll(seg.polyline);
        offset = 0;
      } else {
        offset = combinedPolyline.length - 1;
        if (seg.polyline.length > 1) {
          combinedPolyline.addAll(seg.polyline.skip(1));
        }
      }

      totalDist += seg.distanceMeters;
      totalDur  += seg.durationSeconds;
      if (seg.bbox.length >= 4) bboxes.add(seg.bbox);

      for (final step in seg.steps) {
        combinedSteps.add(OrsStep(
          instruction:     step.instruction,
          distanceMeters:  step.distanceMeters,
          durationSeconds: step.durationSeconds,
          suggestedMode:   step.suggestedMode,
          estimatedFare:   step.estimatedFare,
          wayPointStart:   step.wayPointStart + offset,
          wayPointEnd:     step.wayPointEnd   + offset,
        ));
      }
    }

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
      distanceMeters:  totalDist,
      durationSeconds: totalDur,
      polyline:        combinedPolyline,
      steps:           combinedSteps,
      bbox:            mergedBbox,
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
      debugPrint('[RoutingService] ORS API key missing.');
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
      if (response.statusCode == 429) { debugPrint('[RoutingService] Rate limited.'); return null; }
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

      final multiplier = _durationMultipliers[mode] ?? 1.5;
      final adjDurSec  = rawDurSec * multiplier;
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

      // Enrich steps with stop names from Supabase (replaces Overpass enrichment)
      final enrichedSteps = await _enrichStepsWithSupabase(
        rawSteps, polyline, mode,
      );

      return OrsRouteResult(
        distanceMeters:  distMeters,
        durationSeconds: adjDurSec,
        polyline:        polyline,
        steps:           enrichedSteps,
        bbox:            bbox,
      );
    } catch (e) {
      debugPrint('[RoutingService] Parse error: $e');
      return null;
    }
  }

  // ── Supabase step enrichment (replaces Overpass getModesForSteps) ───────────

  static Future<List<OrsStep>> _enrichStepsWithSupabase(
    List<OrsStep> rawSteps,
    List<LatLng> polyline,
    String mode,
  ) async {
    // For each significant step, find the nearest stop from Supabase
    // and use its name to enrich the instruction label
    final futures = <Future<Map<String, dynamic>?>>[];
    final indices = <int>[];

    for (int i = 0; i < rawSteps.length; i++) {
      final step = rawSteps[i];
      if (step.distanceMeters < 50 || polyline.isEmpty) continue;

      final start  = step.wayPointStart.clamp(0, polyline.length - 1);
      final end    = step.wayPointEnd.clamp(0, polyline.length - 1);
      final midIdx = ((start + end) / 2).round().clamp(0, polyline.length - 1);

      futures.add(SupabaseRouteService.findNearestStop(
        polyline[midIdx],
        radiusKm: 0.15, // tighter radius for step enrichment
      ));
      indices.add(i);
    }

    // Fetch all in parallel with a 6s cap
    List<Map<String, dynamic>?> nearbyStops;
    try {
      nearbyStops = await Future.wait(futures)
          .timeout(const Duration(seconds: 6));
    } on TimeoutException {
      debugPrint('[RoutingService] Step enrichment timed out — using raw steps');
      return TransitModeInferrer.inferModes(rawSteps,
          dominantMode: mode, overpassModes: List.filled(rawSteps.length, null));
    }

    // Build overpassModes-equivalent list for TransitModeInferrer
    final stopNames = List<String?>.filled(rawSteps.length, null);
    for (int i = 0; i < indices.length; i++) {
      final stop = nearbyStops[i];
      if (stop != null) {
        stopNames[indices[i]] = stop['stop_name'] as String?;
        debugPrint('[RoutingService] Step ${indices[i]} near stop: ${stop['stop_name']}');
      }
    }

    return TransitModeInferrer.inferModes(
      rawSteps,
      dominantMode:  mode,
      overpassModes: null, // same shape as before, now from Supabase
    );
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