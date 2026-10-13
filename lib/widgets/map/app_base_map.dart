import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../services/map_style_service.dart';

/// The base map under every map screen: classic OpenStreetMap pictures or
/// the clean vector style, by day or night (Settings > Preferences).
class AppBaseMap extends StatelessWidget {
  const AppBaseMap({super.key});

  @override
  Widget build(BuildContext context) {
    final styles = MapStyleService.instance;
    return ListenableBuilder(
      listenable: styles.changes,
      builder: (context, _) {
        final night = styles.isDark.value;
        if (styles.look.value == MapLook.clean) {
          return _CleanBaseMap(key: ValueKey(night), night: night);
        }
        return classicTileLayer(night: night);
      },
    );
  }
}

/// OpenStreetMap's standard tiles; at night their colors are inverted.
TileLayer classicTileLayer({required bool night}) => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.example.app.transitph_beta',
  tileBuilder: night ? darkModeTileBuilder : null,
);

/// Tiles saved for a downloaded route. Drawn under the live map, so they
/// show only where live tiles can't load (offline).
TileLayer offlineTileLayer(String urlTemplate) => TileLayer(
  urlTemplate: urlTemplate,
  tileProvider: FileTileProvider(),
  tileBuilder:
      MapStyleService.instance.isDark.value ? darkModeTileBuilder : null,
);

Future<Directory> _tileCacheFolder() async =>
    Directory('${(await getApplicationSupportDirectory()).path}/map_tiles');

class _CleanBaseMap extends StatefulWidget {
  final bool night;

  const _CleanBaseMap({super.key, required this.night});

  @override
  State<_CleanBaseMap> createState() => _CleanBaseMapState();
}

class _CleanBaseMapState extends State<_CleanBaseMap> {
  late final Future<Style?> _style = MapStyleService.instance.cleanStyle(
    night: widget.night,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Style?>(
      future: _style,
      builder: (context, snapshot) {
        final style = snapshot.data;
        // Classic until the style arrives, or if it can't (offline).
        if (style == null) return classicTileLayer(night: widget.night);
        return VectorTileLayer(
          theme: style.theme,
          tileProviders: style.providers,
          // Kept with the app's own files, where Android doesn't clear
          // them the way it clears the temporary folder (the plugin's
          // default), so a downloaded tile is downloaded once.
          // (`dynamic`: the analyzer reads the plugin's web stub, where
          // its Directory is a String; on the phone it is dart:io's.)
          cacheFolder: _tileCacheFolder as dynamic,
          fileCacheTtl: const Duration(days: 365),
          fileCacheMaximumSizeInBytes: 150 * 1024 * 1024,
        );
      },
    );
  }
}
