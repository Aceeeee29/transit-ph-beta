import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/data/camanava_places.dart';
import 'package:transitph_beta/models/place.dart';
import 'package:transitph_beta/services/osm_places.dart';

Place _place(String id, String name, double lat, double lng) => Place(
  id: id,
  name: name,
  city: '',
  categories: const [PlaceCategory.mall],
  lat: lat,
  lng: lng,
  description: '',
);

void main() {
  test('reads named places of our categories from the bundled tiles', () {
    final places = OsmPlaces.placesFromPack(
      File('assets/map/camanava.tiles').readAsBytesSync(),
    );
    expect(places, isNotEmpty);
    for (final place in places) {
      expect(place.isFromMap, isTrue);
      expect(place.name, isNotEmpty);
      // Inside the pack's box, give or take a tile.
      expect(place.lat, inInclusiveRange(14.55, 14.80));
      expect(place.lng, inInclusiveRange(120.88, 121.08));
    }
    final merged = OsmPlaces.mergePlaces(camanavaPlaces, places);
    final counts = <PlaceCategory, int>{};
    for (final p in merged.where((p) => p.isFromMap)) {
      counts[p.categories.first] = (counts[p.categories.first] ?? 0) + 1;
    }
    // ignore: avoid_print
    print(
      'OSM places: ${places.length}, after merging: '
      '${merged.length - camanavaPlaces.length} $counts',
    );
  });

  test('our place wins over an OpenStreetMap place next to it', () {
    final own = [_place('sm', 'SM City Grand Central', 14.6570, 120.9840)];
    final osm = [
      // 30 m away, different name: the same spot.
      _place('osm-1', 'Grand Central Mall', 14.6572, 120.9841),
      // 250 m away, same name: the same mall.
      _place('osm-2', 'SM Grand Central', 14.6592, 120.9840),
      // 250 m away, another name: a different place.
      _place('osm-3', 'Victory Central Mall', 14.6592, 120.9845),
    ];
    final merged = OsmPlaces.mergePlaces(own, osm);
    expect(merged.map((p) => p.id), ['sm', 'osm-3']);
  });

  test('names match when one is contained in the other', () {
    expect(
      OsmPlaces.sameName('SM Grand Central', 'SM City Grand Central'),
      isTrue,
    );
    expect(OsmPlaces.sameName('Bonifacio Monument', 'Monumento'), isFalse);
    expect(
      OsmPlaces.sameName(
        'Our Lady of Grace Hospital',
        'Our Lady of Grace Hospital (OLGH)',
      ),
      isTrue,
    );
  });

  test('maps OpenMapTiles classes to our categories', () {
    expect(OsmPlaces.categoryFor('school', 'school'), PlaceCategory.school);
    expect(
      OsmPlaces.categoryFor('college', 'university'),
      PlaceCategory.school,
    );
    expect(OsmPlaces.categoryFor('shop', 'mall'), PlaceCategory.mall);
    expect(OsmPlaces.categoryFor('shop', 'convenience'), isNull);
    expect(OsmPlaces.categoryFor('hospital', 'clinic'), isNull);
    expect(OsmPlaces.categoryFor('art_gallery', 'artwork'), isNull);
    expect(OsmPlaces.categoryFor('museum', 'museum'), PlaceCategory.tourist);
    expect(OsmPlaces.categoryFor('fast_food', ''), isNull);
  });
}
