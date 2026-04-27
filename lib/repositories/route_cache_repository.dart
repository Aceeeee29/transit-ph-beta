import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/route.dart' as route_model;
import '../models/ors_route_result.dart';

class RouteCacheRepository {
  static const _dbName = 'transitph_offline.db';
  static const _dbVersion = 1;
  static const _table = 'route_cache';
  static const generatedRouteProfile = 'supabase-gtfs-v12';

  static const _ttl = Duration(days: 3);
  static const _generatedRoutePrefix = 'generated_cache__';
  static Database? _db;

  static bool isGeneratedRouteId(String routeId) {
    return routeId.startsWith(_generatedRoutePrefix);
  }

  static String _currentUid() => FirebaseAuth.instance.currentUser?.uid ?? 'guest';

  static Future<Database> _database() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            cache_key TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            origin_name TEXT NOT NULL,
            destination_name TEXT NOT NULL,
            mode TEXT NOT NULL,
            profile TEXT NOT NULL,
            cached_at INTEGER NOT NULL,
            route_json TEXT NOT NULL
          )
        ''');
      },
      onOpen: (db) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_table (
            cache_key TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            origin_name TEXT NOT NULL,
            destination_name TEXT NOT NULL,
            mode TEXT NOT NULL,
            profile TEXT NOT NULL,
            cached_at INTEGER NOT NULL,
            route_json TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_route_cache_user ON $_table(user_id)',
        );
      },
    );

    return _db!;
  }

  static Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        cache_key TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        origin_name TEXT NOT NULL,
        destination_name TEXT NOT NULL,
        mode TEXT NOT NULL,
        profile TEXT NOT NULL,
        cached_at INTEGER NOT NULL,
        route_json TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_route_cache_user ON $_table(user_id)',
    );
  }

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
    final key = buildCacheKey(uid, originName, destinationName, mode, profile);
    try {
      final db = await _database();
      await _ensureSchema(db);
      final rows = await db.query(
        _table,
        columns: ['cached_at', 'route_json'],
        where: 'cache_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final row = rows.first;
      final cachedAtMillis = (row['cached_at'] as num?)?.toInt();
      if (cachedAtMillis == null ||
          DateTime.now().difference(
                DateTime.fromMillisecondsSinceEpoch(cachedAtMillis),
              ) >
              _ttl) {
        debugPrint('Route cache expired: $key');
        await db.delete(_table, where: 'cache_key = ?', whereArgs: [key]);
        return null;
      }

      debugPrint('Route cache hit: $key');
      final routeJson = row['route_json'] as String;
      final decoded = jsonDecode(routeJson) as Map<String, dynamic>;
      return OrsRouteResult.fromJson(decoded);
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
    final key = buildCacheKey(uid, originName, destinationName, mode, profile);
    try {
      final db = await _database();
      await _ensureSchema(db);
      await db.insert(
        _table,
        {
          'cache_key': key,
          'user_id': uid,
          'origin_name': originName,
          'destination_name': destinationName,
          'mode': mode,
          'profile': profile,
          'cached_at': DateTime.now().millisecondsSinceEpoch,
          'route_json': jsonEncode(result.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
    final key = buildCacheKey(uid, originName, destinationName, mode, profile);
    try {
      final db = await _database();
      await _ensureSchema(db);
      await db.delete(_table, where: 'cache_key = ?', whereArgs: [key]);
      debugPrint('Route cache invalidated: $key');
    } catch (e) {
      debugPrint('Route cache invalidate error: $e');
    }
  }

  static Future<int> clearAll({int pageSize = 200}) async {
    final uid = _currentUid();

    try {
      final db = await _database();
      await _ensureSchema(db);
      final deleted = await db.delete(
        _table,
        where: 'user_id = ?',
        whereArgs: [uid],
      );

      debugPrint('Route cache cleared: $deleted docs deleted');
      return deleted;
    } catch (e) {
      debugPrint('Route cache clear error: $e');
      rethrow;
    }
  }

  static Future<List<route_model.Route>> getCachedGeneratedRoutes() async {
    final now = DateTime.now();

    try {
      final db = await _database();
      await _ensureSchema(db);
      final rows = await db.query(_table, orderBy: 'cached_at DESC');

      final routes = <route_model.Route>[];
      for (final row in rows) {
        final cachedAtMillis = (row['cached_at'] as num?)?.toInt() ?? 0;
        final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMillis);
        if (now.difference(cachedAt) > _ttl) continue;

        final routeJson = row['route_json'] as String;
        final decoded = jsonDecode(routeJson) as Map<String, dynamic>;
        final ors = OrsRouteResult.fromJson(decoded);

        final cacheKey = row['cache_key'] as String;
        final origin = row['origin_name'] as String;
        final destination = row['destination_name'] as String;
        final mode = row['mode'] as String;
        routes.add(
          _toRouteModel(
            cacheKey: cacheKey,
            originName: origin,
            destinationName: destination,
            mode: mode,
            result: ors,
          ),
        );
      }
      return routes;
    } catch (e) {
      debugPrint('Route cache read-as-routes error: $e');
      return <route_model.Route>[];
    }
  }

  static Future<int> clearAllLocalCache() async {
    try {
      final db = await _database();
      await _ensureSchema(db);
      return await db.delete(_table);
    } catch (e) {
      debugPrint('Route cache clear-all-local error: $e');
      rethrow;
    }
  }

  static Future<void> deleteCachedGeneratedRoute(String routeId) async {
    if (!routeId.startsWith(_generatedRoutePrefix)) return;
    final cacheKey = routeId.substring(_generatedRoutePrefix.length);
    try {
      final db = await _database();
      await _ensureSchema(db);
      await db.delete(_table, where: 'cache_key = ?', whereArgs: [cacheKey]);
    } catch (e) {
      debugPrint('Route cache delete-generated error: $e');
    }
  }

  static Future<CachedGeneratedRoutePayload?> getCachedGeneratedRoutePayload(
    String routeId,
  ) async {
    if (!isGeneratedRouteId(routeId)) return null;

    final cacheKey = routeId.substring(_generatedRoutePrefix.length);
    try {
      final db = await _database();
      await _ensureSchema(db);
      final rows = await db.query(
        _table,
        where: 'cache_key = ?',
        whereArgs: [cacheKey],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final row = rows.first;
      final routeJson = row['route_json'] as String;
      final decoded = jsonDecode(routeJson) as Map<String, dynamic>;
      final result = OrsRouteResult.fromJson(decoded);

      return CachedGeneratedRoutePayload(
        originName: row['origin_name'] as String,
        destinationName: row['destination_name'] as String,
        result: result,
      );
    } catch (e) {
      debugPrint('Route cache payload read error: $e');
      return null;
    }
  }

  static route_model.Route _toRouteModel({
    required String cacheKey,
    required String originName,
    required String destinationName,
    required String mode,
    required OrsRouteResult result,
  }) {
    final points = result.polyline;
    final start = points.isNotEmpty ? points.first : null;
    final end = points.isNotEmpty ? points.last : null;

    final steps = result.steps
        .map(
          (s) => route_model.Step(
            mode: s.suggestedMode,
            instruction: s.instruction,
            details: '${(s.distanceMeters / 1000).toStringAsFixed(2)} km',
            actualFare: s.estimatedFare > 0 ? s.estimatedFare : null,
            is24_7: true,
          ),
        )
        .toList();

    final totalFare = result.steps.fold<double>(
      0,
      (sum, s) => sum + s.estimatedFare,
    );
    final etaMins = (result.durationSeconds / 60).round();

    return route_model.Route(
      id: '$_generatedRoutePrefix$cacheKey',
      startLocation: originName,
      endLocation: destinationName,
      shortDescription: 'Generated $mode route (cached offline)',
      steps: steps,
      startLat: start?.latitude,
      startLng: start?.longitude,
      endLat: end?.latitude,
      endLng: end?.longitude,
      pathPoints: points,
      eta: '$etaMins min',
      price: totalFare > 0 ? 'PHP ${totalFare.toStringAsFixed(0)}' : null,
      distance: result.distanceLabel,
      distanceMeters: result.distanceMeters,
      audienceTags: const ['Generated', 'Offline'],
      approvalStatus: route_model.RouteApprovalStatus.approved,
      views: 0,
      upvotes: 0,
      downvotes: 0,
    );
  }
}

class CachedGeneratedRoutePayload {
  final String originName;
  final String destinationName;
  final OrsRouteResult result;

  const CachedGeneratedRoutePayload({
    required this.originName,
    required this.destinationName,
    required this.result,
  });
}