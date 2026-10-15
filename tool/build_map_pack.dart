// Builds the map data bundled with the app, so the clean map draws CAMANAVA
// without downloading anything:
//   assets/map/style_{positron,dark,liberty}.json  (OpenFreeMap styles: clean
//   day, clean night, and Classic)
//   assets/map/sprites.json + sprites.png  (Classic's icons, 2x)
//   assets/map/fonts/<font>/<range>.pbf  (label fonts for the MapLibre map:
//   Latin, Latin Extended and punctuation; other characters download)
//   assets/map/camanava.tiles  (every vector tile over CAMANAVA, zoom 8-14;
//   the maps never zoom out further than that over the region, and wider
//   views load from the internet)
//
// Run from the project root:  dart run tool/build_map_pack.dart
// Add --styles-only to refresh the styles, icons and fonts but keep the
// tiles, or --fonts-only for just the fonts.
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

// The fonts the styles name, and the glyph ranges covering Filipino and
// English place names. Saved with "_" for spaces (see MapLibreTileServer).
const fontStacks = ['Noto Sans Regular', 'Noto Sans Bold', 'Noto Sans Italic'];
const glyphRanges = ['0-255', '256-511', '8192-8447'];

Future<void> main(List<String> args) async {
  final stylesOnly = args.contains('--styles-only');
  final client = http.Client();
  try {
    final outDir = Directory('assets/map')..createSync(recursive: true);
    if (args.contains('--fonts-only')) {
      await _fetchFonts(client, outDir);
      return;
    }

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
        jsonDecode(File('${outDir.path}/style_liberty.json').readAsStringSync())
            as Map<String, dynamic>;
    final spriteBase = liberty['sprite'] as String;
    for (final ext in ['json', 'png']) {
      final body = await _get(client, '$spriteBase@2x.$ext');
      File('${outDir.path}/sprites.$ext').writeAsBytesSync(body);
      stdout.writeln('sprites.$ext  ${body.length} bytes');
    }
    await _fetchFonts(client, outDir);
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

Future<void> _fetchFonts(http.Client client, Directory outDir) async {
  final liberty =
      jsonDecode(File('${outDir.path}/style_liberty.json').readAsStringSync())
          as Map<String, dynamic>;
  final glyphs = liberty['glyphs'] as String;
  for (final font in fontStacks) {
    final dir = Directory('${outDir.path}/fonts/${font.replaceAll(' ', '_')}')
      ..createSync(recursive: true);
    var total = 0;
    for (final range in glyphRanges) {
      final body = await _get(
        client,
        glyphs
            .replaceAll('{fontstack}', Uri.encodeComponent(font))
            .replaceAll('{range}', range),
      );
      File('${dir.path}/$range.pbf').writeAsBytesSync(body);
      total += body.length;
    }
    stdout.writeln('fonts/${font.replaceAll(' ', '_')}  $total bytes');
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
