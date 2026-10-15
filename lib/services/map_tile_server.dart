import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart'
    show ProviderException, Retryable, TileIdentity;

import 'map_tile_pack.dart';

/// Serves the MapLibre map on the phone itself (127.0.0.1), since MapLibre
/// draws natively and can't call Dart for its data:
/// * `/tiles/z/x/y.pbf`: [PackedVectorTileProvider.shared] (bundled pack,
///   then tiles saved for downloaded routes, then OpenFreeMap)
/// * `/fonts/{font}/{range}.pbf`: bundled Latin ranges, other ranges
///   downloaded once and kept
/// * `/sprites/ofm@2x.json` and `.png`: Classic's bundled icons
///
/// So MapLibre draws from the same data as the flutter_map maps, offline too.
class MapTileServer {
  MapTileServer._();
  static final instance = MapTileServer._();

  static const _glyphsUrl =
      'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf';

  Future<String>? _starting;

  /// The server's address, e.g. http://127.0.0.1:41234. Started on first
  /// use and kept for the rest of the run.
  Future<String> baseUrl() => _starting ??= _start();

  Future<String> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(
      (request) => unawaited(_handle(request)),
      onError: (Object e) => debugPrint('[MapTileServer] $e'),
    );
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final parts = request.uri.pathSegments;
      final (bytes, type) = switch (parts) {
        ['tiles', final z, final x, final y] => (
          await _tile(z, x, y),
          'application/x-protobuf',
        ),
        ['fonts', final font, final range] => (
          await _glyphs(font, range),
          'application/x-protobuf',
        ),
        ['sprites', final name] => (
          await _sprite(name),
          name.endsWith('.png') ? 'image/png' : 'application/json',
        ),
        _ => (null, ''),
      };
      if (bytes == null) {
        response.statusCode = HttpStatus.notFound;
      } else {
        response.headers
          ..set(HttpHeaders.contentTypeHeader, type)
          // The data behind an address doesn't change within a run.
          ..set(HttpHeaders.cacheControlHeader, 'max-age=86400');
        response.add(bytes);
      }
    } on ProviderException catch (e) {
      // Offline or a server error: MapLibre tries again later on a 5xx,
      // and gives up on the tile on a 4xx.
      response.statusCode =
          e.retryable == Retryable.retry
              ? HttpStatus.serviceUnavailable
              : HttpStatus.notFound;
    } catch (e) {
      debugPrint('[MapTileServer] ${request.uri.path}: $e');
      response.statusCode = HttpStatus.serviceUnavailable;
    }
    await response.close();
  }

  Future<Uint8List?> _tile(String z, String x, String y) async {
    final tile = TileIdentity(
      int.parse(z),
      int.parse(x),
      int.parse(y.replaceAll('.pbf', '')),
    );
    return PackedVectorTileProvider.shared.provide(tile);
  }

  /// MapLibre asks for "Noto Sans Regular" (sometimes with fallbacks after a
  /// comma); the bundled files use "_" for spaces.
  Future<Uint8List?> _glyphs(String fontStack, String range) async {
    final font = fontStack.split(',').first.trim();
    final file = '${font.replaceAll(' ', '_')}/$range';
    try {
      final data = await rootBundle.load('assets/map/fonts/$file');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      // Not bundled: a rarer script. Download it once.
    }
    final saved = File(
      '${(await getApplicationSupportDirectory()).path}/map_fonts/$file',
    );
    if (await saved.exists()) return saved.readAsBytes();
    final response = await http
        .get(
          Uri.parse(
            _glyphsUrl
                .replaceAll('{fontstack}', Uri.encodeComponent(font))
                .replaceAll('{range}', range.replaceAll('.pbf', '')),
          ),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw ProviderException(
        message: 'HTTP ${response.statusCode} for font $file',
        retryable: Retryable.retry,
      );
    }
    await saved.parent.create(recursive: true);
    await saved.writeAsBytes(response.bodyBytes, flush: true);
    return response.bodyBytes;
  }

  /// MapLibre asks for ofm@2x.json and .png on this kind of screen; the
  /// bundled icons are the 2x set, served for any size asked.
  Future<Uint8List?> _sprite(String name) async {
    final ext = name.endsWith('.png') ? 'png' : 'json';
    final data = await rootBundle.load('assets/map/sprites.$ext');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
