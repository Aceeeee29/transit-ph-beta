import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Walking paths from a walking router, kept on the device so a walk found
/// once (home to the jeep stop) is there next time, even without internet.
/// Ends match to about 28 m, either way round.
class WalkPathRepository {
  WalkPathRepository._();

  static const _dbName = 'transitph_walks.db';
  static const _table = 'walk_paths';
  static const _keepFor = Duration(days: 30);
  static const _maxKept = 500;

  /// Ends are rounded to 1/4000 of a degree, about 28 m.
  static const _cellsPerDegree = 4000;

  static Future<Database>? _db;

  static Future<Database> _database() => _db ??= _open();

  static Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: 1,
      onCreate:
          (db, _) => db.execute('''
            CREATE TABLE $_table (
              walk_key TEXT PRIMARY KEY,
              saved_at INTEGER NOT NULL,
              points TEXT NOT NULL
            )
          '''),
    );
  }

  static String _cell(LatLng point) =>
      '${(point.latitude * _cellsPerDegree).round()},'
      '${(point.longitude * _cellsPerDegree).round()}';

  static String _key(LatLng from, LatLng to) => '${_cell(from)}>${_cell(to)}';

  static int get _oldestKept =>
      DateTime.now().subtract(_keepFor).millisecondsSinceEpoch;

  /// The saved walk from [from] to [to], or one saved the other way round
  /// (reversed); null when there is none.
  static Future<List<LatLng>?> get(LatLng from, LatLng to) async {
    try {
      final db = await _database();
      for (final (key, reversed) in [
        (_key(from, to), false),
        (_key(to, from), true),
      ]) {
        final rows = await db.query(
          _table,
          columns: ['points'],
          where: 'walk_key = ? AND saved_at >= ?',
          whereArgs: [key, _oldestKept],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final points = [
          for (final pair in jsonDecode(rows.first['points'] as String) as List)
            LatLng(
              ((pair as List)[0] as num).toDouble(),
              (pair[1] as num).toDouble(),
            ),
        ];
        if (points.length < 2) return null;
        return reversed ? points.reversed.toList() : points;
      }
    } catch (e) {
      debugPrint('WalkPathRepository: read failed: $e');
    }
    return null;
  }

  static Future<void> put(LatLng from, LatLng to, List<LatLng> points) async {
    try {
      final db = await _database();
      await db.insert(_table, {
        'walk_key': _key(from, to),
        'saved_at': DateTime.now().millisecondsSinceEpoch,
        'points': jsonEncode([
          for (final point in points)
            [
              double.parse(point.latitude.toStringAsFixed(6)),
              double.parse(point.longitude.toStringAsFixed(6)),
            ],
        ]),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.delete(
        _table,
        where:
            'saved_at < ? OR walk_key NOT IN '
            '(SELECT walk_key FROM $_table ORDER BY saved_at DESC '
            'LIMIT $_maxKept)',
        whereArgs: [_oldestKept],
      );
    } catch (e) {
      debugPrint('WalkPathRepository: save failed: $e');
    }
  }
}
