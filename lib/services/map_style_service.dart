import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart'
    show ThemeReader;

/// How the base map is drawn.
enum MapLook {
  /// OpenStreetMap's standard pictures (colored roads, many icons).
  classic,

  /// A minimal vector style (OpenFreeMap), redrawn on the phone.
  clean,
}

enum NightMap { off, on, auto }

/// The base-map look and night mode, chosen in Settings and kept on the
/// device. Every map screen draws its base through `AppBaseMap`, which
/// listens to [changes].
class MapStyleService {
  MapStyleService._();
  static final instance = MapStyleService._();

  static const _lookKey = 'map_look';
  static const _nightKey = 'map_night';

  final look = ValueNotifier<MapLook>(MapLook.classic);
  final night = ValueNotifier<NightMap>(NightMap.off);

  /// Whether the map is dark right now ([night], with "auto" resolved).
  final isNight = ValueNotifier<bool>(false);

  Listenable get changes => Listenable.merge([look, isNight]);

  Timer? _clock;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      look.value = MapLook.values.firstWhere(
        (l) => l.name == prefs.getString(_lookKey),
        orElse: () => MapLook.classic,
      );
      night.value = NightMap.values.firstWhere(
        (n) => n.name == prefs.getString(_nightKey),
        orElse: () => NightMap.off,
      );
    } catch (_) {
      // Defaults: classic, day.
    }
    _resolveNight();
    // "Auto" follows the clock.
    _clock ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => _resolveNight(),
    );
  }

  Future<void> setLook(MapLook value) async {
    look.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lookKey, value.name);
    } catch (_) {}
  }

  Future<void> setNight(NightMap value) async {
    night.value = value;
    _resolveNight();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nightKey, value.name);
    } catch (_) {}
  }

  /// "Auto" is dark from 6 PM to 6 AM, close to sunset and sunrise in
  /// Metro Manila all year.
  static bool isNightHour(DateTime time) => time.hour >= 18 || time.hour < 6;

  void _resolveNight() {
    isNight.value = switch (night.value) {
      NightMap.off => false,
      NightMap.on => true,
      NightMap.auto => isNightHour(DateTime.now()),
    };
  }

  // ─── Clean (vector) styles ──────────────────────────────────────────────────

  static const _styleBase = 'https://tiles.openfreemap.org/styles';

  final Map<bool, Future<Style?>> _styles = {};

  /// The clean style for day or night, loaded once. Null when it can't be
  /// loaded (e.g. offline); the map then falls back to classic.
  Future<Style?> cleanStyle({required bool night}) {
    return _styles[night] ??= _loadStyle(night).then((style) {
      // Try again next time instead of remembering a failure.
      if (style == null) _styles.remove(night);
      return style;
    });
  }

  Future<Style?> _loadStyle(bool night) async {
    try {
      final name = night ? 'dark' : 'positron';
      final style =
          jsonDecode(await _get('$_styleBase/$name')) as Map<String, dynamic>;
      final source =
          (style['sources'] as Map<String, dynamic>)['openmaptiles']
              as Map<String, dynamic>;
      final tileJson =
          jsonDecode(await _get(source['url'] as String))
              as Map<String, dynamic>;
      final provider = NetworkVectorTileProvider(
        urlTemplate: (tileJson['tiles'] as List).first as String,
        maximumZoom: (tileJson['maxzoom'] as num?)?.toInt() ?? 14,
        minimumZoom: (tileJson['minzoom'] as num?)?.toInt() ?? 0,
      );
      final cleaned = simplifyStyle(style, night: night);
      return Style(
        theme: ThemeReader().read(cleaned),
        providers: TileProviders({'openmaptiles': provider}),
      );
    } catch (e) {
      debugPrint('[MapStyle] Could not load the clean map: $e');
      return null;
    }
  }

  static Future<String> _get(String url) async {
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw 'HTTP ${response.statusCode} for $url';
    }
    return response.body;
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
