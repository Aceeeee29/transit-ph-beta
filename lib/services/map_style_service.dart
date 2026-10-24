import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart'
    show SpriteIndexReader, ThemeReader;

import 'map_tile_pack.dart';
import 'map_tile_server.dart';

/// How the base map is drawn.
enum MapLook {
  /// OpenFreeMap's Liberty: colorful roads and parks, with icons.
  classic,

  /// A minimal vector style (OpenFreeMap), redrawn on the phone.
  clean,
}

/// Light or dark screens and map (Settings > Preferences > Appearance):
/// [auto] goes by the time of day, [system] by the phone's dark theme.
enum Appearance { light, dark, auto, system }

/// The base-map look and the app's appearance, chosen in Settings and kept
/// on the device. Every map screen draws its base through `AppBaseMap`,
/// which listens to [changes]; the app's colors follow [isDark].
class MapStyleService with WidgetsBindingObserver {
  MapStyleService._();
  static final instance = MapStyleService._();

  static const _lookKey = 'map_look';
  static const _appearanceKey = 'app_appearance';

  /// Before Appearance, a "Night Map" setting darkened only the map.
  static const _oldNightKey = 'map_night';

  final look = ValueNotifier<MapLook>(MapLook.clean);
  final appearance = ValueNotifier<Appearance>(Appearance.light);

  /// Whether the app is dark right now ([appearance], with "Auto" and
  /// "System" resolved).
  final isDark = ValueNotifier<bool>(false);

  Listenable get changes => Listenable.merge([look, isDark]);

  bool _observing = false;
  Timer? _clock;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      look.value = MapLook.values.firstWhere(
        (l) => l.name == prefs.getString(_lookKey),
        orElse: () => MapLook.clean,
      );
      final saved = prefs.getString(_appearanceKey);
      appearance.value =
          saved != null
              ? Appearance.values.firstWhere(
                (a) => a.name == saved,
                orElse: () => Appearance.light,
              )
              : switch (prefs.getString(_oldNightKey)) {
                'on' => Appearance.dark,
                'auto' => Appearance.auto,
                _ => Appearance.light,
              };
    } catch (_) {
      // Defaults: clean, light.
    }
    _resolveDark();
    // "System" follows the phone's dark theme as it changes.
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    // "Auto" follows the clock.
    _clock ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => _resolveDark(),
    );
  }

  @override
  void didChangePlatformBrightness() => _resolveDark();

  Future<void> setLook(MapLook value) async {
    look.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lookKey, value.name);
    } catch (_) {}
  }

  Future<void> setAppearance(Appearance value) async {
    appearance.value = value;
    _resolveDark();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_appearanceKey, value.name);
    } catch (_) {}
  }

  /// "Auto" is dark from 6 PM to 6 AM, close to sunset and sunrise in
  /// Metro Manila all year.
  static bool isNightHour(DateTime time) => time.hour >= 18 || time.hour < 6;

  void _resolveDark() {
    isDark.value = switch (appearance.value) {
      Appearance.light => false,
      Appearance.dark => true,
      Appearance.auto => isNightHour(DateTime.now()),
      Appearance.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
  }

  // ─── Vector styles ──────────────────────────────────────────────────────────

  final Map<String, Future<Style?>> _styles = {};

  /// The style for [look] by day, or the night style (dark appearance,
  /// either look). Loaded once; null when it can't be loaded.
  Future<Style?> styleFor({required MapLook look, required bool night}) {
    final key = night ? 'night' : look.name;
    return _styles[key] ??= _loadStyle(key).then((style) {
      // Try again next time instead of remembering a failure.
      if (style == null) _styles.remove(key);
      return style;
    });
  }

  /// Reads OpenFreeMap's styles bundled with the app (no download, so the
  /// map shows right away, offline too); tiles come from [MapTilePack].
  /// Clean is Positron by day and Dark at night, recolored to the app;
  /// Classic is Liberty (colorful, with icons) as it comes.
  Future<Style?> _loadStyle(String key) async {
    try {
      final classic = key == MapLook.classic.name;
      final name = switch (key) {
        'night' => 'dark',
        _ when classic => 'liberty',
        _ => 'positron',
      };
      final style =
          jsonDecode(await rootBundle.loadString('assets/map/style_$name.json'))
              as Map<String, dynamic>;
      final prepared =
          classic
              ? classicStyle(style)
              : simplifyStyle(style, night: key == 'night');
      return Style(
        theme: ThemeReader().read(prepared),
        // Every style draws the same tiles, from one provider.
        providers: TileProviders({
          'openmaptiles': PackedVectorTileProvider.shared,
        }),
        sprites: classic ? await _classicIcons() : null,
      );
    } catch (e) {
      debugPrint('[MapStyle] Could not load the $key map: $e');
      return null;
    }
  }

  // ─── MapLibre styles ────────────────────────────────────────────────────────

  /// The same looks as [styleFor] for the MapLibre map, as style JSON, with
  /// its tiles, fonts and icons from [MapTileServer] and 3D buildings.
  /// [extraLayers] (e.g. the Map tab's pins) go on top, with [extraSources].
  Future<String> maplibreStyle({
    required MapLook look,
    required bool night,
    Map<String, dynamic> extraSources = const {},
    List<Map<String, dynamic>> extraLayers = const [],
  }) async {
    final classic = !night && look == MapLook.classic;
    final name = night ? 'dark' : (classic ? 'liberty' : 'positron');
    final raw =
        jsonDecode(await rootBundle.loadString('assets/map/style_$name.json'))
            as Map<String, dynamic>;
    final prepared =
        classic ? classicStyle(raw) : simplifyStyle(raw, night: night);
    return jsonEncode(
      maplibreStyleFrom(
        prepared,
        baseUrl: await MapTileServer.instance.baseUrl(),
        buildingColor: classic ? null : (night ? '#334156' : '#dde6f1'),
        extraSources: extraSources,
        extraLayers: extraLayers,
      ),
    );
  }

  /// [style] pointed at the phone's tile server at [baseUrl]. Liberty has 3D
  /// buildings already; the clean styles get them in [buildingColor].
  @visibleForTesting
  static Map<String, dynamic> maplibreStyleFrom(
    Map<String, dynamic> style, {
    required String baseUrl,
    String? buildingColor,
    Map<String, dynamic> extraSources = const {},
    List<Map<String, dynamic>> extraLayers = const [],
  }) {
    final layers = [
      for (final layer in style['layers'] as List)
        Map<String, dynamic>.from(layer as Map),
    ];
    if (buildingColor != null &&
        !layers.any((l) => l['type'] == 'fill-extrusion')) {
      final flat = layers.indexWhere((l) => l['source-layer'] == 'building');
      // Flat from above, so it reads like the 2D map until the map tilts.
      layers.insert(flat < 0 ? layers.length : flat + 1, {
        'id': 'building-3d',
        'type': 'fill-extrusion',
        'source': 'openmaptiles',
        'source-layer': 'building',
        'minzoom': 14,
        'paint': {
          'fill-extrusion-color': buildingColor,
          'fill-extrusion-height': ['get', 'render_height'],
          'fill-extrusion-base': ['get', 'render_min_height'],
          'fill-extrusion-opacity': 0.85,
        },
      });
    }
    return {
      ...style,
      'sources': {
        'openmaptiles': {
          'type': 'vector',
          'tiles': ['$baseUrl/tiles/{z}/{x}/{y}.pbf'],
          'minzoom': 0,
          // Deeper zooms draw from z14 tiles, like the flutter_map maps.
          'maxzoom': 14,
          'attribution':
              '© OpenFreeMap © OpenMapTiles © OpenStreetMap contributors',
        },
        ...extraSources,
      },
      'glyphs': '$baseUrl/fonts/{fontstack}/{range}.pbf',
      'sprite': '$baseUrl/sprites/ofm',
      'layers': [...layers, ...extraLayers],
    };
  }

  static Future<SpriteStyle> _classicIcons() async {
    final index =
        jsonDecode(await rootBundle.loadString('assets/map/sprites.json'))
            as Map<String, dynamic>;
    return SpriteStyle(
      atlasProvider:
          () async =>
              (await rootBundle.load(
                'assets/map/sprites.png',
              )).buffer.asUint8List(),
      index: SpriteIndexReader().read(index),
    );
  }

  /// Liberty with only what our tiles carry: the world relief image (its
  /// own raster source) is left out.
  @visibleForTesting
  static Map<String, dynamic> classicStyle(Map<String, dynamic> style) {
    return {
      ...style,
      'id': 'transitph-classic',
      'metadata': {
        ...?(style['metadata'] as Map<String, dynamic>?),
        'version': _styleVersion,
      },
      'sources': {'openmaptiles': (style['sources'] as Map)['openmaptiles']},
      'layers': [
        for (final raw in style['layers'] as List)
          if ((raw as Map)['type'] == 'background' ||
              raw['source'] == 'openmaptiles')
            raw,
      ],
    };
  }

  /// Layers left out for a calm map: shops, businesses and house numbers
  /// (our own place pins cover what matters), plus the world relief image.
  static const _droppedSourceLayers = {'poi', 'housenumber', 'mountain_peak'};

  /// Bump when the palettes change, so phones redraw instead of reusing
  /// cached map images.
  static const _styleVersion = '2';

  /// Removes clutter from an OpenFreeMap style and recolors it to the app.
  @visibleForTesting
  static Map<String, dynamic> simplifyStyle(
    Map<String, dynamic> style, {
    required bool night,
  }) {
    final palette = night ? _nightColors : _dayColors;
    final layers = <Map<String, dynamic>>[];
    for (final raw in style['layers'] as List) {
      final layer = Map<String, dynamic>.from(raw as Map);
      final isBackground = layer['type'] == 'background';
      if (!isBackground && layer['source'] != 'openmaptiles') continue;
      if (_droppedSourceLayers.contains(layer['source-layer'])) continue;
      _applyColors(layer, palette, night: night);
      layers.add(layer);
    }
    return {
      ...style,
      // The renderer caches drawn tiles by theme id; OpenFreeMap's styles
      // have none, so day and night would share (and mix) one cache.
      'id': night ? 'transitph-night' : 'transitph-day',
      'metadata': {
        ...?(style['metadata'] as Map<String, dynamic>?),
        'version': _styleVersion,
      },
      'sources': {'openmaptiles': (style['sources'] as Map)['openmaptiles']},
      'layers': layers,
    };
  }

  /// Day: Positron leaned toward the app (pale blue-white land, sky-tinted
  /// water, white roads with light-blue edges, the app's text colors).
  static const _dayColors = <String, String>{
    'background': '#f4f8ff',
    'landuse_residential': '#eef3fa',
    'building': '#e6edf6',
    'park': '#e4f0e8',
    'landcover_wood': '#e4f0e8',
    'water': '#cbe4f5',
    'waterway': '#cbe4f5',
    'road_area_pier': '#f4f8ff',
    'road_pier': '#f4f8ff',
    'highway_path': '#e8eef6',
    'highway_minor': '#dfe7f1',
    'highway_major_casing': '#d4e4f7',
    'highway_major_inner': '#ffffff',
    'highway_major_subtle': '#dfe7f1',
    'highway_motorway_casing': '#c5d6ec',
    'highway_motorway_inner': '#ffffff',
    'highway_motorway_subtle': '#dfe7f1',
    'highway_motorway_bridge_casing': '#c5d6ec',
    'highway_motorway_bridge_inner': '#ffffff',
    'tunnel_motorway_casing': '#d4e4f7',
    'tunnel_motorway_inner': '#eef3fa',
    'railway_transit': '#cfdbe9',
    'railway_service': '#cfdbe9',
    'railway': '#cfdbe9',
    'boundary_3': '#c5d6ec',
    'boundary_2': '#c5d6ec',
    'boundary_disputed': '#c5d6ec',
    'waterway_line_label': '#6a95bd',
    'water_name_point_label': '#4f7fa8',
    'water_name_line_label': '#4f7fa8',
    'highway-name-path': '#9aabc2',
    'highway-name-minor': '#7a92b2',
    'highway-name-major': '#5b6f8e',
    'label_other': '#5b6f8e',
    'label_village': '#0f1d35',
    'label_town': '#0f1d35',
    'label_state': '#5b6f8e',
    'label_city': '#0f1d35',
    'label_city_capital': '#0f1d35',
  };

  /// Night: OpenFreeMap's dark style is nearly black with roads barely
  /// visible; these blue-grays (after Google Maps' night mode, close to the
  /// app's navy text) keep roads readable.
  static const _nightColors = <String, String>{
    'background': '#242f3e',
    'water': '#17263c',
    'waterway': '#17263c',
    'landuse_residential': '#283343',
    'landcover_wood': '#263c3f',
    'landuse_park': '#263c3f',
    'building': '#2b3646',
    'highway_path': '#2f3948',
    'highway_minor': '#38414e',
    'highway_major_casing': '#212a37',
    'highway_major_inner': '#4a5566',
    'highway_major_subtle': '#38414e',
    'highway_motorway_casing': '#1f2835',
    'highway_motorway_inner': '#746855',
    'highway_motorway_subtle': '#5d5546',
    'railway_transit': '#3d4757',
    'railway_minor': '#3d4757',
    'railway': '#3d4757',
    'railway_transit_dashline': '#242f3e',
    'railway_minor_dashline': '#242f3e',
    'railway_dashline': '#242f3e',
    'aeroway-area': '#2b3646',
    'aeroway-runway': '#38414e',
    'aeroway-taxiway': '#38414e',
    'highway_name_other': '#9ca5b3',
    'highway_name_motorway': '#d59563',
    'water_name': '#515c6d',
  };

  static void _applyColors(
    Map<String, dynamic> layer,
    Map<String, String> palette, {
    required bool night,
  }) {
    final id = layer['id'] as String?;
    final paint = Map<String, dynamic>.from(
      (layer['paint'] as Map?) ?? const {},
    );
    final type = layer['type'];
    final color = palette[id];
    if (color != null) {
      final key = switch (type) {
        'background' => 'background-color',
        'fill' => 'fill-color',
        'line' => 'line-color',
        'symbol' => 'text-color',
        _ => null,
      };
      if (key != null) paint[key] = color;
    } else if (night && type == 'symbol' && (id ?? '').startsWith('place_')) {
      // Town and district names.
      paint['text-color'] = '#a9b3c1';
      paint['text-halo-color'] = '#242f3e';
    }
    layer['paint'] = paint;
  }
}
