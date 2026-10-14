import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../services/map_style_service.dart';
import '../../theme/app_colors.dart';

/// The base map under every map screen: the clean or classic (colorful)
/// style by day, the night style in dark mode (Settings > Preferences).
/// Everything comes from OpenFreeMap tiles, bundled for CAMANAVA.
class AppBaseMap extends StatelessWidget {
  const AppBaseMap({super.key});

  @override
  Widget build(BuildContext context) {
    final styles = MapStyleService.instance;
    return ListenableBuilder(
      listenable: styles.changes,
      builder: (context, _) {
        final look = styles.look.value;
        final night = styles.isDark.value;
        return _VectorBaseMap(
          key: ValueKey('${look.name}-$night'),
          look: look,
          night: night,
        );
      },
    );
  }
}

Future<Directory> _tileCacheFolder() async =>
    Directory('${(await getApplicationSupportDirectory()).path}/map_tiles');

class _VectorBaseMap extends StatefulWidget {
  final MapLook look;
  final bool night;

  const _VectorBaseMap({super.key, required this.look, required this.night});

  @override
  State<_VectorBaseMap> createState() => _VectorBaseMapState();
}

class _VectorBaseMapState extends State<_VectorBaseMap> {
  late final Future<Style?> _style = MapStyleService.instance.styleFor(
    look: widget.look,
    night: widget.night,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Style?>(
      future: _style,
      builder: (context, snapshot) {
        final style = snapshot.data;
        // The styles are bundled, so this is a blink at most.
        if (style == null) return ColoredBox(color: AppColors.bg);
        return VectorTileLayer(
          theme: style.theme,
          sprites: style.sprites,
          tileProviders: style.providers,
          // Kept with the app's own files, where Android doesn't clear
          // them the way it clears the temporary folder (the plugin's
          // default), so a downloaded tile is downloaded once.
          // (`dynamic`: the analyzer reads the plugin's web stub, where
          // its Directory is a String; on the phone it is dart:io's.)
          cacheFolder: _tileCacheFolder as dynamic,
          fileCacheTtl: const Duration(days: 365),
          fileCacheMaximumSizeInBytes: 150 * 1024 * 1024,
          // Parsed tiles kept in memory (default 20): panning back over
          // the area just seen doesn't parse its tiles again.
          memoryTileDataCacheMaxSize: 60,
        );
      },
    );
  }
}
