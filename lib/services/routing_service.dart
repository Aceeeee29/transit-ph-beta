import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config.dart';
import '../models/ors_route_result.dart';
import '../repositories/route_cache_repository.dart';

/// Service responsible for fetching road-snapped routes from
/// OpenRouteService (ORS) Directions API, with Firestore caching.
///
/// Flow:
///   1. Check Firestore cache via [RouteCacheRepository]
///   2. Cache HIT  → return cached [OrsRouteResult] immediately
///   3. Cache MISS → call ORS API → parse result → write to cache → return
///
/// Usage:
/// ```dart
/// final result = await RoutingService.getRoute(
///   originName: 'Quezon City',
///   origin: LatLng(14.6760, 121.0437),
///   destinationName: 'Makati',
///   destination: LatLng(14.5547, 121.0244),
///   mode: 'Jeepney',
/// );
/// if (result != null) {
///   print(result.distanceLabel);  // "12.4 km"
///   print(result.durationLabel);  // "31 mins"
/// }
/// ```
class RoutingService {
  static const _baseUrl =
      'https://api.openrouteservice.org/v2/directions';

  // Maps app transport modes to ORS API profiles
  static const _modeToProfile = {
    'Walk': 'foot-walking',
    'Jeepney': 'driving-car',
    'Bus': 'driving-car',
    'Train': 'driving-car',
    'Tricycle': 'cycling-regular',
    'FX/Van': 'driving-car',
    'Ferry': 'driving-car',
  };

  /// Returns the ORS profile string for a given transport mode.
  static String profileForMode(String mode) =>
      _modeToProfile[mode] ?? 'driving-car';

  /// Fetches a route from origin to destination, using the Firestore cache
  /// when available.
  ///
  /// [originName] and [destinationName] are human-readable place names used
  /// as the cache key. [origin] and [destination] are the actual coordinates
  /// sent to the ORS API.
  ///
  /// Returns null if both cache and API fail.
  static Future<OrsRouteResult?> getRoute({
    required String originName,
    required LatLng origin,
    required String destinationName,
    required LatLng destination,
    String mode = 'Jeepney',
  }) async {
    final profile = profileForMode(mode);

    // ── 1. Check Firestore cache first ──────────────────────────────────────
    final cached = await RouteCacheRepository.get(
      originName,
      destinationName,
      profile,
    );
    if (cached != null) return cached;

    // ── 2. Cache miss — call ORS API ─────────────────────────────────────────
    final result = await _fetchFromOrs(
      origin: origin,
      destination: destination,
      profile: profile,
    );

    if (result == null) return null;

    // ── 3. Write result to cache asynchronously (non-blocking) ───────────────
    RouteCacheRepository.put(originName, destinationName, profile, result);

    return result;
  }

  /// Makes the actual HTTP call to ORS and parses the GeoJSON response.
  static Future<OrsRouteResult?> _fetchFromOrs({
    required LatLng origin,
    required LatLng destination,
    required String profile,
  }) async {
    final apiKey = Config.openRouteServiceApiKey;
    if (apiKey.isEmpty) {
      debugPrint('[RoutingService] ORS API key is missing.');
      return null;
    }

    final url = Uri.parse(
      '$_baseUrl/$profile?'
      'api_key=$apiKey'
      '&start=${origin.longitude},${origin.latitude}'
      '&end=${destination.longitude},${destination.latitude}',
    );

    try {
      debugPrint('[RoutingService] Fetching ORS route: $profile');
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      debugPrint('[RoutingService] ORS status: ${response.statusCode}');

      if (response.statusCode == 429) {
        debugPrint('[RoutingService] ORS rate limit hit.');
        return null;
      }

      if (response.statusCode != 200) {
        debugPrint('[RoutingService] ORS error: ${response.body}');
        return null;
      }

      return _parseOrsResponse(response.body);
    } catch (e) {
      debugPrint('[RoutingService] Exception: $e');
      return null;
    }
  }

  /// Parses the raw ORS GeoJSON response body into an [OrsRouteResult].
  static OrsRouteResult? _parseOrsResponse(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final feature = (data['features'] as List).first as Map<String, dynamic>;

      // ── Geometry: decode polyline coordinates ─────────────────────────────
      final rawCoords =
          feature['geometry']['coordinates'] as List;
      final polyline = rawCoords
          .map((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ))
          .toList();

      // ── Summary: distance and duration ────────────────────────────────────
      final summary = feature['properties']['summary'] as Map<String, dynamic>;
      final distanceMeters = (summary['distance'] as num).toDouble();
      final durationSeconds = (summary['duration'] as num).toDouble();

      // ── Bounding box ──────────────────────────────────────────────────────
      final rawBbox = data['bbox'] as List?;
      final bbox = rawBbox != null
          ? rawBbox.map((v) => (v as num).toDouble()).toList()
          : <double>[];

      // ── Turn-by-turn steps ────────────────────────────────────────────────
      final segments =
          feature['properties']['segments'] as List? ?? [];
      final List<OrsStep> steps = [];
      for (final segment in segments) {
        final rawSteps = segment['steps'] as List? ?? [];
        for (final s in rawSteps) {
          steps.add(OrsStep(
            instruction: s['instruction'] as String? ?? '',
            distanceMeters: (s['distance'] as num?)?.toDouble() ?? 0,
            durationSeconds: (s['duration'] as num?)?.toDouble() ?? 0,
          ));
        }
      }

      return OrsRouteResult(
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        polyline: polyline,
        steps: steps,
        bbox: bbox,
      );
    } catch (e) {
      debugPrint('[RoutingService] Parse error: $e');
      return null;
    }
  }
}