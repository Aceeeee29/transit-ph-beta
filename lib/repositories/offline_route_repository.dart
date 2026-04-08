import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/route.dart' as route_model;

class OfflineRouteRepository {
  static const _dbName = 'transitph_offline.db';
  static const _dbVersion = 1;
  static const _table = 'downloaded_routes';

  static Database? _db;

  static Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        route_json TEXT NOT NULL,
        downloaded_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<Database> _database() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _ensureSchema(db);
      },
      onOpen: (db) async => _ensureSchema(db),
    );

    return _db!;
  }

  static Future<void> saveRoute(route_model.Route route) async {
    final db = await _database();
    await _ensureSchema(db);
    await db.insert(
      _table,
      {
        'id': route.id,
        'route_json': jsonEncode(route.toJson()),
        'downloaded_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<bool> isRouteDownloaded(String routeId) async {
    final db = await _database();
    await _ensureSchema(db);
    final rows = await db.query(
      _table,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [routeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<List<route_model.Route>> getDownloadedRoutes() async {
    final db = await _database();
    await _ensureSchema(db);
    final rows = await db.query(_table, orderBy: 'downloaded_at DESC');

    return rows.map((row) {
      final raw = row['route_json'] as String;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return route_model.Route.fromJson(json);
    }).toList();
  }

  static Future<void> deleteRoute(String routeId) async {
    final db = await _database();
    await _ensureSchema(db);
    await db.delete(_table, where: 'id = ?', whereArgs: [routeId]);
  }

  static Future<void> clearAllDownloadedRoutes() async {
    final db = await _database();
    await _ensureSchema(db);
    await db.delete(_table);
  }
}
