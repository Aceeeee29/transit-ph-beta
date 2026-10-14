import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// The CAMANAVA vector tiles bundled with the app (built by
/// `tool/build_map_pack.dart`), so the clean map draws there without
/// downloading anything. Copied out of the APK once per app version, then
/// read tile by tile.
class MapTilePack {
  MapTilePack._(this._file, this._tiles, this.tileUrl);

  static const _asset = 'assets/map/camanava.tiles';

  static Future<MapTilePack?>? _loading;

  /// Null when the pack can't be read; the map then downloads every tile.
  static Future<MapTilePack?> load() => _loading ??= _load();

  final File _file;

  /// Where each tile sits in [_file]: "z/x/y" → (offset, length).
  final Map<String, (int, int)> _tiles;

  /// The OpenFreeMap tile address the pack was built from.
  final String tileUrl;

  bool has(TileIdentity tile) =>
      _tiles.containsKey('${tile.z}/${tile.x}/${tile.y}');

  Future<Uint8List?> read(TileIdentity tile) async {
    final entry = _tiles['${tile.z}/${tile.x}/${tile.y}'];
    if (entry == null) return null;
    final file = await _file.open();
    try {
      await file.setPosition(entry.$1);
      return await file.read(entry.$2);
    } finally {
      await file.close();
    }
  }

  static Future<MapTilePack?> _load() async {
    try {
      final data = await rootBundle.load(_asset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final headerLength = data.getUint32(0);
      final header =
          jsonDecode(utf8.decode(bytes.sublist(4, 4 + headerLength)))
              as Map<String, dynamic>;
      final dataStart = 4 + headerLength;

      final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/map_pack',
      );
      final file = File('${dir.path}/camanava_${header['builtAt']}.tiles');
      if (!await file.exists() || await file.length() != bytes.length) {
        await dir.create(recursive: true);
        // An app update brings a newer pack; drop the old copy.
        await for (final old in dir.list()) {
          if (old is File) await old.delete();
        }
        final part = File('${file.path}.part');
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(file.path);
      }

      final tiles = <String, (int, int)>{
        for (final MapEntry(:key, :value)
            in (header['tiles'] as Map<String, dynamic>).entries)
          key: (dataStart + (value as List)[0] as int, value[1] as int),
      };
      return MapTilePack._(file, tiles, header['tileUrl'] as String);
    } catch (e) {
      debugPrint('[MapTilePack] Could not open the bundled map: $e');
      return null;
    }
  }
}

/// Vector tiles for the clean map: from the bundled pack inside CAMANAVA,
/// then tiles saved for downloaded routes ([RouteTileStore]), downloaded
/// everywhere else. The map keeps downloaded tiles on the phone (see
/// `AppBaseMap`), so each one is fetched once.
class PackedVectorTileProvider extends VectorTileProvider {
  PackedVectorTileProvider._();

  /// Every map style draws the same tiles, so one provider serves them all.
  static final shared = PackedVectorTileProvider._();

  /// Lists OpenFreeMap's current tile address, which changes whenever they
  /// publish fresh map data.
  static const tileJsonUrl = 'https://tiles.openfreemap.org/planet';

  static const _tileUrlKey = 'map_tile_url';

  /// One connection reused for every tile.
  static final _client = http.Client();

  String? _tileUrl;
  Future<String?>? _refreshing;
  bool _refreshedThisRun = false;

  @override
  int get maximumZoom => 14;

  @override
  int get minimumZoom => 0;

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    final pack = await MapTilePack.load();
    final packed = await pack?.read(tile);
    if (packed != null) return packed;
    final saved = await RouteTileStore.read(tile);
    if (saved != null) return saved;
    return _fetch(tile, pack);
  }

  /// Saves [tile] for offline use unless the bundled pack already has it.
  Future<void> saveForOffline(TileIdentity tile) async {
    final pack = await MapTilePack.load();
    if (pack?.has(tile) ?? false) return;
    if (await RouteTileStore.has(tile)) return;
    await RouteTileStore.write(tile, await _fetch(tile, pack));
  }

  Future<Uint8List> _fetch(TileIdentity tile, MapTilePack? pack) async {
    var url = await _currentTileUrl(pack);
    var response = await _download(url, tile);
    if (response.statusCode == 404 && !_refreshedThisRun) {
      // Old map data is taken down after a while; look up the new address.
      final fresh = await _refreshTileUrl();
      if (fresh != null && fresh != url) {
        url = fresh;
        response = await _download(url, tile);
      }
    }
    if (response.statusCode == 200) return response.bodyBytes;
    throw ProviderException(
      message: 'HTTP ${response.statusCode} for tile $tile',
      statusCode: response.statusCode,
      retryable:
          response.statusCode >= 500 || response.statusCode == 408
              ? Retryable.retry
              : Retryable.none,
    );
  }

  Future<http.Response> _download(String? url, TileIdentity tile) async {
    if (url == null) {
      throw ProviderException(
        message: 'No map tile address yet',
        retryable: Retryable.retry,
      );
    }
    try {
      return await _client
          .get(
            Uri.parse(
              url
                  .replaceAll('{z}', '${tile.z}')
                  .replaceAll('{x}', '${tile.x}')
                  .replaceAll('{y}', '${tile.y}'),
            ),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception catch (e) {
      throw ProviderException(message: '$e', retryable: Retryable.retry);
    }
  }

  /// The last address seen (kept on the phone), else the pack's. Checked
  /// for a newer one in the background once per run.
  Future<String?> _currentTileUrl(MapTilePack? pack) async {
    if (_tileUrl case final url?) return url;
    try {
      final prefs = await SharedPreferences.getInstance();
      _tileUrl = prefs.getString(_tileUrlKey);
    } catch (_) {}
    _tileUrl ??= pack?.tileUrl;
    unawaited(_refreshTileUrl());
    return _tileUrl ?? await _refreshTileUrl();
  }

  Future<String?> _refreshTileUrl() {
    return _refreshing ??= () async {
      try {
        final response = await _client
            .get(Uri.parse(tileJsonUrl))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) return _tileUrl;
        final tiles =
            (jsonDecode(response.body) as Map<String, dynamic>)['tiles']
                as List;
        final url = tiles.first as String;
        _tileUrl = url;
        _refreshedThisRun = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tileUrlKey, url);
        return url;
      } catch (e) {
        debugPrint('[MapTilePack] Could not look up the tile address: $e');
        return _tileUrl;
      } finally {
        // A failed lookup may be retried later; a successful one stands.
        if (!_refreshedThisRun) _refreshing = null;
      }
    }();
  }
}

/// Vector tiles saved around downloaded routes, so they show offline
/// outside the bundled CAMANAVA area (see `OfflineTileService`).
class RouteTileStore {
  RouteTileStore._();

  static Future<Directory>? _root;

  static Future<Directory> root() =>
      _root ??= getApplicationSupportDirectory().then(
        (dir) => Directory('${dir.path}/route_tiles'),
      );

  static Future<File> _file(TileIdentity tile) async =>
      File('${(await root()).path}/${tile.z}/${tile.x}/${tile.y}.pbf');

  static Future<bool> has(TileIdentity tile) async =>
      (await _file(tile)).exists();

  static Future<Uint8List?> read(TileIdentity tile) async {
    try {
      final file = await _file(tile);
      return await file.exists() ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(TileIdentity tile, Uint8List bytes) async {
    final file = await _file(tile);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  static Future<void> clear() async {
    final dir = await root();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
