import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/ors_route_result.dart';

/// Repository responsible solely for reading and writing
/// ORS route results to the Firestore [route_cache] collection.
///
/// This is completely separate from [RouteService] which manages
/// community-contributed routes. The cache only stores raw ORS data.
///
/// Firestore document structure:
/// route_cache/{cacheKey}
/// ├── originName:      "Quezon City"
/// ├── destinationName: "Makati"
/// ├── profile:         "driving-car"
/// ├── distanceMeters:  12400.0
/// ├── durationSeconds: 1860.0
/// ├── polyline:        [ { lat: 14.65, lng: 121.03 }, ... ]
/// ├── steps:           [ { instruction: "...", distanceMeters: 200, durationSeconds: 30 }, ... ]
/// ├── bbox:            [ 120.98, 14.55, 121.04, 14.70 ]
/// └── cachedAt:        Timestamp
class RouteCacheRepository {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _collection = 'route_cache';

  /// Cache TTL: routes older than this are considered stale and re-fetched.
  static const _ttl = Duration(days: 7);

  /// Builds a deterministic, Firestore-safe cache key from origin + destination
  /// + transport profile. Normalised to lowercase with spaces replaced.
  ///
  /// Example: "quezon_city__makati__driving-car"
  static String buildCacheKey(
    String originName,
    String destinationName,
    String profile,
  ) {
    String clean(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    return '${clean(originName)}__${clean(destinationName)}__$profile';
  }

  /// Returns a cached [OrsRouteResult] if one exists and is not stale.
  /// Returns null if cache miss or entry is expired.
  static Future<OrsRouteResult?> get(
    String originName,
    String destinationName,
    String profile,
  ) async {
    final key = buildCacheKey(originName, destinationName, profile);

    try {
      final doc = await _db.collection(_collection).doc(key).get();
      if (!doc.exists || doc.data() == null) return null;

      final data = doc.data()!;

      // Check TTL
      final cachedAt = (data['cachedAt'] as Timestamp?)?.toDate();
      if (cachedAt == null ||
          DateTime.now().difference(cachedAt) > _ttl) {
        debugPrint('[RouteCacheRepository] Cache expired for $key');
        return null;
      }

      debugPrint('[RouteCacheRepository] Cache HIT for $key');
      return OrsRouteResult.fromJson(data);
    } catch (e) {
      debugPrint('[RouteCacheRepository] Error reading cache: $e');
      return null;
    }
  }

  /// Writes an [OrsRouteResult] to Firestore cache.
  static Future<void> put(
    String originName,
    String destinationName,
    String profile,
    OrsRouteResult result,
  ) async {
    final key = buildCacheKey(originName, destinationName, profile);

    try {
      final data = result.toJson();
      data['originName'] = originName;
      data['destinationName'] = destinationName;
      data['profile'] = profile;
      data['cachedAt'] = FieldValue.serverTimestamp();

      await _db.collection(_collection).doc(key).set(data);
      debugPrint('[RouteCacheRepository] Cached route for $key');
    } catch (e) {
      // Cache write failure is non-fatal — the caller still has the result
      debugPrint('[RouteCacheRepository] Error writing cache: $e');
    }
  }

  /// Deletes a specific cache entry (e.g. to force a refresh).
  static Future<void> invalidate(
    String originName,
    String destinationName,
    String profile,
  ) async {
    final key = buildCacheKey(originName, destinationName, profile);
    try {
      await _db.collection(_collection).doc(key).delete();
      debugPrint('[RouteCacheRepository] Invalidated cache for $key');
    } catch (e) {
      debugPrint('[RouteCacheRepository] Error invalidating cache: $e');
    }
  }
}