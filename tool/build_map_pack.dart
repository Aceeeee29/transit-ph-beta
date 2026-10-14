// Builds the map data bundled with the app, so the clean map draws CAMANAVA
// without downloading anything:
//   assets/map/style_{positron,dark,liberty}.json  (OpenFreeMap styles: clean
//   day, clean night, and Classic)
//   assets/map/sprites.json + sprites.png  (Classic's icons, 2x)
//   assets/map/camanava.tiles  (every vector tile over CAMANAVA, zoom 8-14;
//   the maps never zoom out further than that over the region, and wider
//   views load from the internet)
//
// Run from the project root:  dart run tool/build_map_pack.dart
// Add --styles-only to refresh the styles and icons but keep the tiles.
// Re-run now and then to pick up newer OpenStreetMap data.
//
// camanava.tiles layout: a 4-byte big-endian header length, the header as
// UTF-8 JSON ({"builtAt", "tileUrl", "tiles": {"z/x/y":
// [offset, length]}}), then the tiles' bytes; offsets count from the end
// of the header. Read by lib/services/map_tile_pack.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

// Same box as CamanavaPlaces.bounds.
const south = 14.60, west = 120.92, north = 14.76, east = 121.04;
const minZoom = 8, maxZoom = 14;

const styleBase = 'https://tiles.openfreemap.org/styles';

Future<void> main(List<String> args) async {
  final stylesOnly = args.contains('--styles-only');
  final client = http.Client();
  try {
    final outDir = Directory('assets/map')..createSync(recursive: true);

    String? tileJsonUrl;
    for (final name in ['positron', 'dark', 'liberty']) {
      final body = await _get(client, '$styleBase/$name');
      final style = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      tileJsonUrl ??=
          ((style['sources'] as Map)['openmaptiles'] as Map)['url'] as String;
      File('${outDir.path}/style_$name.json').writeAsBytesSync(body);
      stdout.writeln('style_$name.json  ${body.length} bytes');
    }

    final liberty =
        jsonDecode(
              File('${outDir.path}/style_liberty.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final spriteBase = liberty['sprite'] as String;
    for (final ext in ['json', 'png']) {
      final body = await _get(client, '$spriteBase@2x.$ext');
      File('${outDir.path}/sprites.$ext').writeAsBytesSync(body);
      stdout.writeln('sprites.$ext  ${body.length} bytes');
    }
    if (stylesOnly) return;

    final tileJson =
        jsonDecode(utf8.decode(await _get(client, tileJsonUrl!)))
            as Map<String, dynamic>;
    final tileUrl = (tileJson['tiles'] as List).first as String;

    final index = <String, List<int>>{};
    final data = BytesBuilder(copy: false);
    for (var z = minZoom; z <= maxZoom; z++) {
      for (var x = _lonToX(west, z); x <= _lonToX(east, z); x++) {
        for (var y = _latToY(north, z); y <= _latToY(south, z); y++) {
          final url = tileUrl
              .replaceAll('{z}', '$z')
              .replaceAll('{x}', '$x')
              .replaceAll('{y}', '$y');
          final bytes = await _get(client, url);
          index['$z/$x/$y'] = [data.length, bytes.length];
          data.add(bytes);
        }
      }
    }

    final header = utf8.encode(
      jsonEncode({
        'builtAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        'tileUrl': tileUrl,
        'tiles': index,
      }),
    );
    final out =
        BytesBuilder(copy: false)
          ..add((ByteData(4)..setUint32(0, header.length)).buffer.asUint8List())
          ..add(header)
          ..add(data.takeBytes());
    final pack = File('${outDir.path}/camanava.tiles')
      ..writeAsBytesSync(out.takeBytes());
    stdout.writeln(
      'camanava.tiles  ${index.length} tiles, '
      '${(pack.lengthSync() / 1048576).toStringAsFixed(1)} MB, from $tileUrl',
    );
  } finally {
    client.close();
  }
}

Future<Uint8List> _get(http.Client client, String url) async {
  final response = await client
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 30));
  if (response.statusCode != 200) {
    throw 'HTTP ${response.statusCode} for $url';
  }
  return response.bodyBytes;
}

int _lonToX(double lon, int z) => ((lon + 180) / 360 * (1 << z)).floor();

int _latToY(double lat, int z) {
  final r = lat * math.pi / 180;
  return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) /
          2 *
          (1 << z))
      .floor();
}
