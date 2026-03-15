import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Queries the Overpass API for two purposes:
///
/// 1. **Step mode labeling** — identifies which LTFRB transit route relations
///    pass through the road at a given step midpoint.
///
/// 2. **Nearest stop finder** ([findNearestStop]) — returns the closest
///    bus stop / train station to a coordinate for multi-modal routing.
///
/// ## Latency strategy (Issue 5)
///   Individual step queries time out after 5 s (was 10 s).
///   [getModesForSteps] applies an overall 4 s cap — if Overpass is slow the
///   route is returned immediately via PhRoadDatabase fallback.
class OverpassRouteService {
  static const _overpassUrl = 'https://overpass-api.de/api/interpreter';
  static const _gridSize    = 0.0003; // ≈ 33 m grid for mode cache keys

  static final Map<String, String?> _modeCache = {};
  static final Map<String, LatLng?> _stopCache = {};

  // ── Step mode lookup ────────────────────────────────────────────────────────

  static Future<List<String?>> getModesForSteps({
    required List<LatLng> stepMidpoints,
    int maxConcurrency = 4,
  }) async {
    if (stepMidpoints.isEmpty) return [];
    final results = List<String?>.filled(stepMidpoints.length, null);

    try {
      await Future(() async {
        for (int start = 0; start < stepMidpoints.length; start += maxConcurrency) {
          final end   = (start + maxConcurrency).clamp(0, stepMidpoints.length);
          final batch = stepMidpoints.sublist(start, end);
          await Future.wait(batch.asMap().entries.map((entry) async {
            results[start + entry.key] = await _getModeAt(entry.value);
          }));
        }
      }).timeout(const Duration(seconds: 4));
    } on TimeoutException {
      debugPrint('[Overpass] getModesForSteps overall timeout — using fallback');
    }

    return results;
  }

  static Future<String?> _getModeAt(LatLng coord) async {
    final key = _modeKey(coord);
    if (_modeCache.containsKey(key)) return _modeCache[key];
    final mode  = await _queryMode(coord.latitude, coord.longitude);
    _modeCache[key] = mode;
    return mode;
  }

  static String _modeKey(LatLng c) {
    final lat = (c.latitude  / _gridSize).round() * _gridSize;
    final lng = (c.longitude / _gridSize).round() * _gridSize;
    return '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';
  }

  static Future<String?> _queryMode(double lat, double lng) async {
    final query = '''
[out:json][timeout:5];
way(around:30,$lat,$lng)[highway~"^(trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)\$"];
rel(bw)[route~"^(bus|share_taxi|minibus|tram|train|subway|ferry)\$"];
out tags;
''';
    try {
      final response = await http
          .post(Uri.parse(_overpassUrl),
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: 'data=${Uri.encodeComponent(query)}')
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return null;

      final elements = ((jsonDecode(response.body) as Map)['elements'] as List?) ?? [];
      if (elements.isEmpty) return null;

      String? best;
      for (final el in elements) {
        final mode = _tagsToMode((el['tags'] as Map<String, dynamic>?) ?? {});
        if (mode != null) best = _higherPriority(best, mode);
      }
      debugPrint('[Overpass] $lat,$lng → $best (${elements.length} relations)');
      return best;
    } on TimeoutException {
      debugPrint('[Overpass] Timeout at $lat,$lng');
      return null;
    } catch (e) {
      debugPrint('[Overpass] Error at $lat,$lng: $e');
      return null;
    }
  }

  // ── Nearest stop finder (Issue 4) ───────────────────────────────────────────

  /// Returns the nearest transit stop to [near] that serves [mode],
  /// within [radiusM] metres. Results are cached per session.
  /// Returns null if nothing found or Overpass times out.
  static Future<LatLng?> findNearestStop(
    LatLng near,
    String mode, {
    int radiusM = 400,
  }) async {
    final key = '$mode:${near.latitude.toStringAsFixed(4)},${near.longitude.toStringAsFixed(4)}';
    if (_stopCache.containsKey(key)) return _stopCache[key];
    final result = await _queryNearestStop(near, mode, radiusM);
    _stopCache[key] = result;
    return result;
  }

  static Future<LatLng?> _queryNearestStop(LatLng near, String mode, int radiusM) async {
    final lat = near.latitude;
    final lng = near.longitude;

    final String nodeFilters;
    if (mode == 'Train') {
      nodeFilters = '''
  node(around:$radiusM,$lat,$lng)["railway"~"station|stop|halt"];
  node(around:$radiusM,$lat,$lng)["public_transport"="stop_position"]["train"="yes"];
  node(around:$radiusM,$lat,$lng)["public_transport"="stop_position"]["subway"="yes"];
''';
    } else if (mode == 'Ferry') {
      nodeFilters = '''
  node(around:$radiusM,$lat,$lng)["amenity"="ferry_terminal"];
  node(around:$radiusM,$lat,$lng)["public_transport"="stop_position"]["ferry"="yes"];
''';
    } else {
      nodeFilters = '''
  node(around:$radiusM,$lat,$lng)["highway"="bus_stop"];
  node(around:$radiusM,$lat,$lng)["public_transport"="stop_position"];
  node(around:$radiusM,$lat,$lng)["amenity"="bus_station"];
''';
    }

    final query = '[out:json][timeout:6];\n(\n$nodeFilters);\nout body 10;\n';

    try {
      final response = await http
          .post(Uri.parse(_overpassUrl),
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: 'data=${Uri.encodeComponent(query)}')
          .timeout(const Duration(seconds: 7));

      if (response.statusCode != 200) return null;

      final elements = ((jsonDecode(response.body) as Map)['elements'] as List?) ?? [];
      if (elements.isEmpty) {
        debugPrint('[Overpass] No $mode stops within ${radiusM}m of $lat,$lng');
        return null;
      }

      LatLng?  nearest;
      double nearestDist = double.infinity;
      for (final el in elements) {
        final eLat = (el['lat'] as num?)?.toDouble();
        final eLng = (el['lon'] as num?)?.toDouble();
        if (eLat == null || eLng == null) continue;
        final stop = LatLng(eLat, eLng);
        final dist = _distKm(near, stop);
        if (dist < nearestDist) { nearestDist = dist; nearest = stop; }
      }

      debugPrint('[Overpass] Nearest $mode stop: ${nearestDist.toStringAsFixed(3)} km away');
      return nearest;
    } on TimeoutException {
      debugPrint('[Overpass] findNearestStop timeout ($mode)');
      return null;
    } catch (e) {
      debugPrint('[Overpass] findNearestStop error: $e');
      return null;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static String? _tagsToMode(Map<String, dynamic> tags) {
    final network = (tags['network'] ?? '').toString().toLowerCase();
    final route   = (tags['route']   ?? '').toString().toLowerCase();
    if (route == 'train' || route == 'subway' || route == 'monorail') return 'Train';
    if (route == 'ferry') return 'Ferry';
    if (network.contains('puj')) return 'Jeepney';
    if (network.contains('pub')) return 'Bus';
    if (route == 'share_taxi')   return 'FX/Van';
    if (network.contains('qcitybus') || network.contains('bgc bus') ||
        network.contains('love bus')  || network.contains('p2p'))    return 'Bus';
    if ((route == 'bus' || route == 'minibus') &&
        (network.contains('ltfrb') || network.contains('national capital'))) return 'Bus';
    return null;
  }

  static String? _higherPriority(String? a, String? b) {
    if (a == null) return b;
    if (b == null) return a;
    const order = ['Train', 'Ferry', 'Bus', 'FX/Van', 'Jeepney'];
    return (order.indexOf(b) < order.indexOf(a)) ? b : a;
  }

  static double _distKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude  - a.latitude)  * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  static void clearCache() { _modeCache.clear(); _stopCache.clear(); }
}