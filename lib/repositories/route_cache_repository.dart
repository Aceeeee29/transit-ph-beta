import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/ors_route_result.dart';

class RouteCacheRepository {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _collection = 'route_cache';

  static const _ttl = Duration(days: 7);
  static String buildCacheKey(
    String originName,
    String destinationName,
    String mode,
    String profile,
  ) {
    String clean(String s) {
      return s.trim().toLowerCase().replaceAll(RegExp(r'[^\w]'), '_');
    }

    return '${clean(originName)}__${clean(destinationName)}__${clean(mode)}__$profile';
  }

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
        debugPrint('Route cache expired: $key');
        return null;
      }

      debugPrint('Route cache hit: $key');
      return OrsRouteResult.fromJson(data);
    } catch (e) {
      debugPrint('Route cache read error: $e');
      return null;
    }
  }

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
      debugPrint('Route cached: $key');
    } catch (e) {
      debugPrint('Route cache write error: $e');
    }
  }

  static Future<void> invalidate(
    String originName,
    String destinationName,
    String mode,
    String profile,
  ) async {
    final key = buildCacheKey(originName, destinationName, mode, profile);
    try {
      await _db.collection(_collection).doc(key).delete();
      debugPrint('Route cache invalidated: $key');
    } catch (e) {
      debugPrint('Route cache invalidate error: $e');
    }
  }
}