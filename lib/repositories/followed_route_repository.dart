import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/ors_route_result.dart';
import '../models/route.dart' as route_model;

/// A route the user started following, kept so it can be reopened offline.
class FollowedRouteEntry {
  final String id;
  final String startLabel;
  final String endLabel;
  final DateTime followedAt;

  /// Exactly one of these is set.
  final route_model.Route? route;
  final OrsRouteResult? generatedRoute;

  const FollowedRouteEntry({
    required this.id,
    required this.startLabel,
    required this.endLabel,
    required this.followedAt,
    this.route,
    this.generatedRoute,
  });
}

/// The routes the user most recently started following, stored on the
/// device whenever a follow starts. Separate from user downloads, so a
/// followed route can still be downloaded with its map tiles later.
class FollowedRouteRepository {
  static const _dbName = 'transitph_offline.db';
  static const _table = 'followed_routes';
  static const maxEntries = 10;

  static Database? _db;

  static Future<Database> _database() async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), _dbName);
    _db = await openDatabase(path, version: 1, onOpen: _ensureSchema);
    await _ensureSchema(_db!);
    return _db!;
  }

  static Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        start_label TEXT NOT NULL,
        end_label TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        followed_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> saveRoute(route_model.Route route) => _save(
    id: route.id,
    kind: 'route',
    startLabel: route.startLocation,
    endLabel: route.endLocation,
    payload: RouteStorageCodec.encode(route),
  );

  static Future<void> saveGenerated(
    String id,
    OrsRouteResult result, {
    required String originName,
    required String destinationName,
  }) => _save(
    id: id,
    kind: 'generated',
    startLabel: originName,
    endLabel: destinationName,
    payload: jsonEncode(result.toJson()),
  );

  static Future<void> _save({
    required String id,
    required String kind,
    required String startLabel,
    required String endLabel,
    required String payload,
  }) async {
    final db = await _database();
    await db.insert(_table, {
      'id': id,
      'kind': kind,
      'start_label': startLabel,
      'end_label': endLabel,
      'payload_json': payload,
      'followed_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Keep only the most recent few.
    await db.rawDelete(
      'DELETE FROM $_table WHERE id NOT IN '
      '(SELECT id FROM $_table ORDER BY followed_at DESC LIMIT ?)',
      [maxEntries],
    );
  }

  static Future<List<FollowedRouteEntry>> getRecent() async {
    final db = await _database();
    final rows = await db.query(_table, orderBy: 'followed_at DESC');
    final entries = <FollowedRouteEntry>[];
    for (final row in rows) {
      try {
        final payload = row['payload_json'] as String;
        final isGenerated = row['kind'] == 'generated';
        entries.add(
          FollowedRouteEntry(
            id: row['id'] as String,
            startLabel: row['start_label'] as String,
            endLabel: row['end_label'] as String,
            followedAt: DateTime.fromMillisecondsSinceEpoch(
              row['followed_at'] as int,
            ),
            route: isGenerated ? null : RouteStorageCodec.decode(payload),
            generatedRoute:
                isGenerated
                    ? OrsRouteResult.fromJson(
                      jsonDecode(payload) as Map<String, dynamic>,
                    )
                    : null,
          ),
        );
      } catch (_) {
        // Skip an entry saved by an incompatible older version.
      }
    }
    return entries;
  }

  static Future<void> delete(String id) async {
    final db = await _database();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearAll() async {
    final db = await _database();
    await db.delete(_table);
  }
}

/// JSON for storing a [route_model.Route] on the device. [Route.toJson]
/// holds a Firestore [Timestamp] (editedAt), which plain jsonEncode can't
/// write, so it is stored as milliseconds and restored on read.
class RouteStorageCodec {
  static const _timestampKey = '__timestampMillis';

  static String encode(route_model.Route route) => jsonEncode(
    route.toJson(),
    toEncodable: (value) {
      if (value is Timestamp) {
        return {_timestampKey: value.millisecondsSinceEpoch};
      }
      throw JsonUnsupportedObjectError(value);
    },
  );

  static route_model.Route decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    json.updateAll((key, value) {
      if (value is Map && value.containsKey(_timestampKey)) {
        return Timestamp.fromMillisecondsSinceEpoch(
          value[_timestampKey] as int,
        );
      }
      return value;
    });
    return route_model.Route.fromJson(json);
  }
}
