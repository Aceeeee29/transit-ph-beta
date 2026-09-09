import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/data/camanava_places.dart';
import 'package:transitph_beta/models/place.dart';
import 'package:transitph_beta/utils/map_distance.dart';

void main() {
  group('CAMANAVA places dataset', () {
    test('all places fall inside the CAMANAVA bounding box', () {
      for (final place in camanavaPlaces) {
        final point = LatLng(place.lat, place.lng);
        expect(
          CamanavaBounds.bounds.contains(point),
          isTrue,
          reason: '${place.name} (${place.lat}, ${place.lng}) is outside '
              'CAMANAVA bounds (120.92-121.04 E, 14.60-14.76 N)',
        );
      }
    });

    test('every filter category has at least one place', () {
      for (final category in PlaceCategory.values) {
        final matches =
            camanavaPlaces.where((p) => p.categories.contains(category));
        expect(matches, isNotEmpty,
            reason: 'category ${category.name} has no places');
      }
    });

    test('place ids are unique', () {
      final ids = camanavaPlaces.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('only CAMANAVA cities are present (South Caloocan, Malabon, Navotas, Valenzuela)', () {
      final cities = camanavaPlaces.map((p) => p.city.toLowerCase()).toSet();
      expect(
        cities.difference({'caloocan', 'malabon', 'navotas', 'valenzuela'}),
        isEmpty,
      );
    });

    test('galaan spots exist for the "Where to Go" module', () {
      expect(camanavaPlaces.where((p) => p.isGalaan).length,
          greaterThanOrEqualTo(4));
    });
  });

  group('map distance util', () {
    test('Haversine distance between two known CAMANAVA points', () {
      // Roughly between Bonifacio Monument (Caloocan) and SM City Valenzuela.
      final km = kmBetween(const LatLng(14.6533, 120.9829), const LatLng(14.6670, 120.9700));
      expect(km, closeTo(2.1, 0.5));
    });

    test('zero distance for identical points', () {
      expect(kmBetween(const LatLng(14.64, 120.94), const LatLng(14.64, 120.94)),
          closeTo(0.0, 0.001));
    });

    test('formatDistanceKm produces readable labels', () {
      expect(formatDistanceKm(0.4), '400 m');
      expect(formatDistanceKm(1.234), '1.2 km');
      expect(formatDistanceKm(3.5), '3.5 km');
    });
  });
}