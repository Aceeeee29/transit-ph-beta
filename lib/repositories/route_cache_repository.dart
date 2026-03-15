import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/ors_route_result.dart';

/// Repository responsible solely for reading and writing
/// ORS route results to the Firestore [route_cache] collection.
///
/// FIX (Issue 6): cache key now includes [mode] so that routes between the
/// same origin/destination but different transport modes (e.g. Jeepney vs
/// Train) get separate cache entries and never collide.
class RouteCacheRepository {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _collection = 'route_cache';

  static const _ttl = Duration(days: 7);

  /// Builds a deterministic, Firestore-safe cache key from origin +
  /// destination + transport mode + ORS profile.
  ///
  /// Example: "quezon_city__makati__jeepney__driving-car"
  static String buildCacheKey(
    String originName,
    String destinationName,
    String mode,
    String profile,
  ) {
    String clean(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'[^\w]'), '_');
    return '${clean(originName)}__${clean(destinationName)}__${clean(mode)}__$profile';
  }

  /// Returns a cached [OrsRouteResult] if one exists and is not stale.
  static Future<OrsRouteResult?> get(
    String originName,
    String destinationName,
    String mode,
    String profile,
  ) async {
    final key = buildCacheKey(originName, destinationName, mode, profile);
    try {
      final doc = await _db.collection(_collection).doc(key).get();
      if (!doc.exists || doc.data() == null) return null;
      final data = doc.data()!;

      final cachedAt = (data['cachedAt'] as Timestamp?)?.toDate();
      if (cachedAt == null || DateTime.now().difference(cachedAt) > _ttl) {
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
    String mode,
    String profile,
    OrsRouteResult result,
  ) async {
    final key = buildCacheKey(originName, destinationName, mode, profile);
    try {
      final data = result.toJson();
      data['originName'] = originName;
      data['destinationName'] = destinationName;
      data['mode'] = mode;
      data['profile'] = profile;
      data['cachedAt'] = FieldValue.serverTimestamp();
      await _db.collection(_collection).doc(key).set(data);
      debugPrint('[RouteCacheRepository] Cached route for $key');
    } catch (e) {
      debugPrint('[RouteCacheRepository] Error writing cache: $e');
    }
  }

  /// Deletes a specific cache entry (e.g. to force a refresh).
  static Future<void> invalidate(
    String originName,
    String destinationName,
    String mode,
    String profile,
  ) async {
    final key = buildCacheKey(originName, destinationName, mode, profile);
    try {
      await _db.collection(_collection).doc(key).delete();
      debugPrint('[RouteCacheRepository] Invalidated cache for $key');
    } catch (e) {
      debugPrint('[RouteCacheRepository] Error invalidating cache: $e');
    }
  }
}