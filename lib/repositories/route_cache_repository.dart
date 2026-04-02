import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/ors_route_result.dart';

class RouteCacheRepository {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _collection = 'route_cache';

  static const _ttl = Duration(days: 3);
  static String? _currentUid() => FirebaseAuth.instance.currentUser?.uid;

  static String _sanitizeForKey(String s) {
    return s.trim().toLowerCase().replaceAll(RegExp(r'[^\w]'), '_');
  }

  static String buildCacheKey(
    String uid,
    String originName,
    String destinationName,
    String mode,
    String profile,
  ) {
    return '${_sanitizeForKey(uid)}__${_sanitizeForKey(originName)}__${_sanitizeForKey(destinationName)}__${_sanitizeForKey(mode)}__$profile';
  }

  static Future<OrsRouteResult?> get(
    String originName,
    String destinationName,
    String mode,
    String profile,
  ) async {
    final uid = _currentUid();
    if (uid == null) return null;
    final key = buildCacheKey(uid, originName, destinationName, mode, profile);
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
    final uid = _currentUid();
    if (uid == null) return;
    final key = buildCacheKey(uid, originName, destinationName, mode, profile);
    try {
      final data = result.toJson();
      data['userId'] = uid;
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
    final uid = _currentUid();
    if (uid == null) return;
    final key = buildCacheKey(uid, originName, destinationName, mode, profile);
    try {
      await _db.collection(_collection).doc(key).delete();
      debugPrint('Route cache invalidated: $key');
    } catch (e) {
      debugPrint('Route cache invalidate error: $e');
    }
  }

  static Future<int> clearAll({int pageSize = 200}) async {
    var deleted = 0;
    final uid = _currentUid();
    if (uid == null) return 0;

    try {
      // Current schema: entries include userId field.
      while (true) {
        final snapshot = await _db
            .collection(_collection)
            .where('userId', isEqualTo: uid)
            .limit(pageSize)
            .get();

        if (snapshot.docs.isEmpty) break;

        final batch = _db.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
        deleted += snapshot.docs.length;

        if (snapshot.docs.length < pageSize) break;
      }

      // Legacy schema fallback: user-scoped docs by ID prefix only.
      final uidPrefix = '${_sanitizeForKey(uid)}__';
      while (true) {
        final snapshot = await _db
            .collection(_collection)
            .orderBy(FieldPath.documentId)
            .startAt([uidPrefix])
            .endAt(['$uidPrefix\uf8ff'])
            .limit(pageSize)
            .get();

        if (snapshot.docs.isEmpty) break;

        final batch = _db.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
        deleted += snapshot.docs.length;

        if (snapshot.docs.length < pageSize) break;
      }

      debugPrint('Route cache cleared: $deleted docs deleted');
      return deleted;
    } catch (e) {
      debugPrint('Route cache clear error: $e');
      rethrow;
    }
  }
}