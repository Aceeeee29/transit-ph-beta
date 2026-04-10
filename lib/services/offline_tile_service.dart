import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OfflineTileService {
  static const _userAgent = 'TransitPH/1.0 (offline-tile-cache)';
  static const _maxTileDownload = 1200;

  static Future<String> getLocalTileTemplatePath() async {
    final root = await _tileRoot();
    return p.join(root.path, '{z}', '{x}', '{y}.png');
  }

  static Future<void> cacheRouteTiles(
    List<LatLng> points, {
    int minZoom = 11,
    int maxZoom = 16,
  }) async {
    final normalized = _normalizedPoints(points);
    if (normalized.length < 2) return;

    final bounds = _boundsForPoints(normalized);
    var activeMaxZoom = maxZoom;

    while (activeMaxZoom > minZoom &&
        _estimateTileCount(bounds, minZoom, activeMaxZoom) > _maxTileDownload) {
      activeMaxZoom -= 1;
    }

    final root = await _tileRoot();
    final client = http.Client();
    try {
      for (var z = minZoom; z <= activeMaxZoom; z++) {
        final (minX, maxX, minY, maxY) = _tileRangeForBounds(bounds, z);
        for (var x = minX; x <= maxX; x++) {
          for (var y = minY; y <= maxY; y++) {
            final tileFile = File(p.join(root.path, '$z', '$x', '$y.png'));
            if (await tileFile.exists()) continue;

            await tileFile.parent.create(recursive: true);
            final uri = Uri.parse('https://tile.openstreetmap.org/$z/$x/$y.png');
            try {
              final response = await client.get(uri, headers: {
                HttpHeaders.userAgentHeader: _userAgent,
              });
              if (response.statusCode == 200) {
                await tileFile.writeAsBytes(response.bodyBytes, flush: true);
              }
            } catch (_) {
              // Best-effort cache: keep going when a tile fails.
            }
          }
        }
      }
    } finally {
      client.close();
    }
  }

  static Future<void> clearAllTiles() async {
    final root = await _tileRoot();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }

  static Future<Directory> _tileRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'offline_tiles'));
  }

  static List<LatLng> _normalizedPoints(List<LatLng> points) {
    return points
        .where((p) => p.latitude.isFinite && p.longitude.isFinite)
        .where((p) => p.latitude >= -85.05112878 && p.latitude <= 85.05112878)
        .toList();
  }

  static ({double minLat, double maxLat, double minLng, double maxLng})
      _boundsForPoints(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final pnt in points.skip(1)) {
      minLat = math.min(minLat, pnt.latitude);
      maxLat = math.max(maxLat, pnt.latitude);
      minLng = math.min(minLng, pnt.longitude);
      maxLng = math.max(maxLng, pnt.longitude);
    }

    // Pad bounds so users can pan a bit around the route when offline.
    const latPad = 0.01;
    const lngPad = 0.01;
    return (
      minLat: (minLat - latPad).clamp(-85.05112878, 85.05112878),
      maxLat: (maxLat + latPad).clamp(-85.05112878, 85.05112878),
      minLng: (minLng - lngPad).clamp(-180.0, 180.0),
      maxLng: (maxLng + lngPad).clamp(-180.0, 180.0),
    );
  }

  static int _estimateTileCount(
    ({double minLat, double maxLat, double minLng, double maxLng}) bounds,
    int minZoom,
    int maxZoom,
  ) {
    var total = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final (minX, maxX, minY, maxY) = _tileRangeForBounds(bounds, z);
      total += (maxX - minX + 1) * (maxY - minY + 1);
    }
    return total;
  }

  static (int, int, int, int) _tileRangeForBounds(
    ({double minLat, double maxLat, double minLng, double maxLng}) bounds,
    int zoom,
  ) {
    final minX = _lonToTileX(bounds.minLng, zoom);
    final maxX = _lonToTileX(bounds.maxLng, zoom);
    final minY = _latToTileY(bounds.maxLat, zoom);
    final maxY = _latToTileY(bounds.minLat, zoom);

    final maxIndex = (1 << zoom) - 1;
    return (
      minX.clamp(0, maxIndex),
      maxX.clamp(0, maxIndex),
      minY.clamp(0, maxIndex),
      maxY.clamp(0, maxIndex),
    );
  }

  static int _lonToTileX(double lon, int zoom) {
    final n = 1 << zoom;
    return ((lon + 180.0) / 360.0 * n).floor();
  }

  static int _latToTileY(double lat, int zoom) {
    final n = 1 << zoom;
    final rad = lat * math.pi / 180.0;
    final value =
        (1.0 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2.0;
    return (value * n).floor();
  }
}