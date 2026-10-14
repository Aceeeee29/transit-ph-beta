import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/services/map_style_service.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('assets/map/style_$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  for (final (name, night) in [('positron', false), ('dark', true)]) {
    test('the $name style is simplified and still renders', () {
      final simplified = MapStyleService.simplifyStyle(
        _fixture(name),
        night: night,
      );
      final layers = (simplified['layers'] as List).cast<Map>();

      expect((simplified['sources'] as Map).keys, ['openmaptiles']);
      expect(layers.where((l) => l['source-layer'] == 'poi'), isEmpty);
      expect(layers.any((l) => l['source'] == 'ne2_shaded'), isFalse);
      // The renderer accepts the edited style.
      expect(ThemeReader().read(simplified).layers, isNotEmpty);
    });
  }

  test('day and night are cached apart and day takes the app colors', () {
    final day = MapStyleService.simplifyStyle(
      _fixture('positron'),
      night: false,
    );
    final night = MapStyleService.simplifyStyle(_fixture('dark'), night: true);
    // The renderer caches drawn tiles by theme id.
    expect(ThemeReader().read(day).id, isNot(ThemeReader().read(night).id));
    final background = (day['layers'] as List).cast<Map>().firstWhere(
      (l) => l['id'] == 'background',
    );
    expect((background['paint'] as Map)['background-color'], '#f4f8ff');
  });

  test('night keeps roads readable on a blue-gray map', () {
    final layers =
        (MapStyleService.simplifyStyle(_fixture('dark'), night: true)['layers']
                as List)
            .cast<Map>();
    Object? paint(String id, String key) =>
        (layers.firstWhere((l) => l['id'] == id)['paint'] as Map)[key];

    expect(paint('background', 'background-color'), '#242f3e');
    expect(paint('highway_minor', 'line-color'), '#38414e');
    expect(paint('highway_motorway_inner', 'line-color'), '#746855');
  });

  test('classic keeps only what our tiles can draw, cached apart', () {
    final classic = MapStyleService.classicStyle(_fixture('liberty'));
    final layers = (classic['layers'] as List).cast<Map>();
    expect(classic['id'], 'transitph-classic');
    expect((classic['sources'] as Map).keys, ['openmaptiles']);
    expect(
      layers.every(
        (l) => l['type'] == 'background' || l['source'] == 'openmaptiles',
      ),
      isTrue,
    );
    // Colorful, with icons: the shop and transit icon layers stay.
    expect(layers.any((l) => l['id'] == 'poi_transit'), isTrue);
  });

  test('auto appearance is dark from 6 PM to 6 AM', () {
    expect(MapStyleService.isNightHour(DateTime(2026, 10, 12, 17, 59)), false);
    expect(MapStyleService.isNightHour(DateTime(2026, 10, 12, 18)), true);
    expect(MapStyleService.isNightHour(DateTime(2026, 10, 12, 5, 59)), true);
    expect(MapStyleService.isNightHour(DateTime(2026, 10, 12, 6)), false);
  });
}
