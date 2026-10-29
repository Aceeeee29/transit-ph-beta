import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:vector_tile/raw/raw_vector_tile.dart';

import '../data/camanava_places.dart';
import '../models/place.dart';

/// Schools, hospitals, malls, attractions and parks from OpenStreetMap, read
/// from the bundled CAMANAVA tiles' `poi` layer (offline, no lookups), and
/// merged under our own hand-made [camanavaPlaces].
class OsmPlaces {
  OsmPlaces._();

  static Future<List<Place>>? _all;

  /// Our places plus OpenStreetMap's, without OpenStreetMap's copies of
  /// ours. Our places come first. Read once per run.
  static Future<List<Place>> all() => _all ??= _load();

  static Future<List<Place>> _load() async {
    try {
      final data = await rootBundle.load('assets/map/camanava.tiles');
      final osm = await compute(
        placesFromPack,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      return mergePlaces(camanavaPlaces, osm);
    } catch (e) {
      debugPrint('[OsmPlaces] Could not read the map places: $e');
      return camanavaPlaces;
    }
  }

  /// The places in the deepest (z14) tiles of a camanava.tiles pack (see
  /// tool/build_map_pack.dart for its layout).
  @visibleForTesting
  static List<Place> placesFromPack(Uint8List bytes) {
    final headerLength = ByteData.sublistView(bytes).getUint32(0);
    final header =
        jsonDecode(utf8.decode(bytes.sublist(4, 4 + headerLength)))
            as Map<String, dynamic>;
    final dataStart = 4 + headerLength;
    // By id: a tile repeats the places just past its edges.
    final places = <String, Place>{};
    for (final MapEntry(:key, :value)
        in (header['tiles'] as Map<String, dynamic>).entries) {
      final [z, x, y] = key.split('/').map(int.parse).toList();
      if (z != 14) continue;
      final offset = dataStart + ((value as List)[0] as int);
      final tile = VectorTile.fromBuffer(
        bytes.sublist(offset, offset + (value[1] as int)),
      );
      for (final layer in tile.layers) {
        if (layer.name != 'poi') continue;
        for (final place in _layerPlaces(layer, z, x, y)) {
          places.putIfAbsent(place.id, () => place);
        }
      }
    }
    return places.values.toList();
  }

  static Iterable<Place> _layerPlaces(
    VectorTile_Layer layer,
    int z,
    int x,
    int y,
  ) sync* {
    for (final feature in layer.features) {
      if (feature.type != VectorTile_GeomType.POINT) continue;
      final props = <String, Object>{};
      for (var i = 0; i + 1 < feature.tags.length; i += 2) {
        final value = layer.values[feature.tags[i + 1]];
        props[layer.keys[feature.tags[i]]] =
            value.hasStringValue()
                ? value.stringValue
                : value.hasIntValue()
                ? value.intValue.toInt()
                : value.hasUintValue()
                ? value.uintValue.toInt()
                : value.hasSintValue()
                ? value.sintValue.toInt()
                : value.hasDoubleValue()
                ? value.doubleValue
                : value.hasFloatValue()
                ? value.floatValue
                : value.boolValue;
      }
      final name = '${props['name:latin'] ?? props['name'] ?? ''}'.trim();
      final category = categoryFor(
        '${props['class'] ?? ''}',
        '${props['subclass'] ?? ''}',
      );
      if (name.isEmpty || category == null) continue;
      // A point is one MoveTo: [command, x, y], zigzag-encoded.
      final g = feature.geometry;
      if (g.length < 3) continue;
      final px = _unzigzag(g[1]) / layer.extent;
      final py = _unzigzag(g[2]) / layer.extent;
      final n = 1 << z;
      final lng = (x + px) / n * 360 - 180;
      final lat =
          math.atan(_sinh(math.pi * (1 - 2 * (y + py) / n))) * 180 / math.pi;
      yield Place(
        id: 'osm-${feature.id}',
        name: name,
        city: '',
        categories: [category],
        lat: lat,
        lng: lng,
        description: '',
        rank: (props['rank'] as int?) ?? 100,
      );
    }
  }

  static int _unzigzag(int v) => (v >> 1) ^ -(v & 1);

  static double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

  /// Our category for an OpenStreetMap place (OpenMapTiles' class and
  /// subclass), or null for the kinds the map doesn't show. Clinics (400+
  /// in CAMANAVA) and public artworks (statues, murals) are left out so the
  /// Hospitals and Attractions chips stay useful.
  @visibleForTesting
  static PlaceCategory? categoryFor(String cls, String subclass) {
    return switch (cls) {
      'school' || 'college' => PlaceCategory.school,
      'hospital' when subclass != 'clinic' => PlaceCategory.hospital,
      'shop' when subclass == 'mall' || subclass == 'department_store' =>
        PlaceCategory.mall,
      'art_gallery' when subclass == 'artwork' || subclass == 'art' => null,
      'attraction' ||
      'museum' ||
      'zoo' ||
      'castle' ||
      'art_gallery' => PlaceCategory.tourist,
      'park' => PlaceCategory.park,
      _ => null,
    };
  }

  /// OpenStreetMap pins we know are wrong, so we never show them.
  /// Each entry is the pin's name and roughly where it sits.
  static const _wrongPins = [
    // STI's old campus near Monumento. STI moved to Samson Road, next to
    // UE Caloocan and AMA (our own "STI College Caloocan" pin).
    (name: 'STI Caloocan', lat: 14.65152, lng: 120.98290),
  ];

  static bool _isWrongPin(Place place) => _wrongPins.any(
    (wrong) =>
        place.name == wrong.name &&
        (place.lat - wrong.lat).abs() < 0.001 &&
        (place.lng - wrong.lng).abs() < 0.001,
  );

  /// [own] places, then [osm] places that aren't one of ours: an
  /// OpenStreetMap place right next to ours (within 80 m), or nearby with
  /// the same name, is the same place and ours wins. OpenStreetMap's own
  /// duplicates (a building and a point, same name) are dropped too, and
  /// so are the [_wrongPins].
  @visibleForTesting
  static List<Place> mergePlaces(List<Place> own, List<Place> osm) {
    final kept = <Place>[];
    final sorted = [
      for (final place in osm)
        if (!_isWrongPin(place)) place,
    ]..sort((a, b) => a.rank.compareTo(b.rank));
    for (final place in sorted) {
      bool sameAs(Place other, {double near = 80}) {
        final metres = _metresBetween(place, other);
        return metres < near ||
            (metres < 400 && sameName(place.name, other.name));
      }

      if (own.any(sameAs)) continue;
      if (kept.any((k) => sameAs(k, near: 0))) continue;
      kept.add(place);
    }
    return [...own, ...kept];
  }

  static const _genericWords = {
    'the', 'of', 'and', 'ng', 'de', 'city', 'inc', 'corp', 'branch', //
  };

  /// Whether two names are the same place: every word of the shorter one
  /// is in the longer one ("SM Grand Central" vs "SM City Grand Central").
  static bool sameName(String a, String b) {
    Set<String> words(String s) =>
        s
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9ñ ]'), ' ')
            .split(' ')
            .where((w) => w.isNotEmpty && !_genericWords.contains(w))
            .toSet();
    final wa = words(a), wb = words(b);
    if (wa.isEmpty || wb.isEmpty) return false;
    final (short, long) = wa.length <= wb.length ? (wa, wb) : (wb, wa);
    return long.containsAll(short);
  }

  static double _metresBetween(Place a, Place b) {
    const r = 6371000.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLng = (b.lng - a.lng) * math.pi / 180;
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(a.lat * math.pi / 180) *
            math.cos(b.lat * math.pi / 180) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }
}
