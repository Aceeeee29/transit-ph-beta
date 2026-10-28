import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/services/walk_option.dart';

void main() {
  group('WalkOption', () {
    // ~200 m apart, like the Malabon trip to Amang Rodriguez Elementary.
    const start = LatLng(14.6650, 120.9560);
    const school = LatLng(14.6665, 120.9570);

    test('offers walking for a short trip', () {
      final minutes = WalkOption.offered([start, school]);
      expect(minutes, isNotNull);
      expect(minutes, lessThan(5));
    });

    test('drops a ride that is slower than walking there', () {
      final walk = WalkOption.offered([start, school])!;
      // The 16-minute jeep loop from the bug report.
      expect(WalkOption.rideWorthIt(16, walk), isFalse);
    });

    test('keeps any ride that gets there sooner than walking', () {
      const nearish = LatLng(14.6800, 120.9560); // ~1.7 km: ~20 min
      final walk = WalkOption.offered([start, nearish])!;
      expect(WalkOption.rideWorthIt(12, walk), isTrue);
      expect(WalkOption.rideWorthIt(walk - 2, walk), isTrue);
      expect(WalkOption.rideWorthIt(walk + 1, walk), isFalse);
    });

    test('judges by the walking path, not the straight line', () {
      // Galicia St, Malabon → Arkong Bato Park: ~260 m apart, but the
      // walking routers go 1.19 km around.
      const galicia = LatLng(14.69359, 120.95207);
      const park = LatLng(14.69542, 120.95394);
      expect(WalkOption.worthAsking(galicia, park), isTrue);
      const corner = LatLng(14.69900, 120.95100);
      final walk = WalkOption.offered([galicia, corner, park])!;
      expect(walk, greaterThan(10));
      // A 9-minute tricycle beats it, so it stays an option.
      expect(WalkOption.rideWorthIt(9, walk), isTrue);
    });

    test('never asks for a walking path when too far to walk', () {
      const far = LatLng(14.6900, 120.9560); // ~2.8 km straight
      expect(WalkOption.worthAsking(start, far), isFalse);
      expect(WalkOption.offered([start, far]), isNull);
    });
  });
}
