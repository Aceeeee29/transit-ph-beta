import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/services/walk_option.dart';

void main() {
  group('WalkOption', () {
    // ~200 m apart, like the Malabon trip to Amang Rodriguez Elementary.
    const start = LatLng(14.6650, 120.9560);
    const school = LatLng(14.6665, 120.9570);

    test('offers walking for a short trip', () {
      final minutes = WalkOption.offered(start, school);
      expect(minutes, isNotNull);
      expect(minutes, lessThan(5));
    });

    test('drops a ride that is slower than walking there', () {
      final walk = WalkOption.offered(start, school)!;
      // The 16-minute jeep loop from the bug report.
      expect(WalkOption.rideWorthIt(16, walk), isFalse);
    });

    test('keeps any ride that gets there sooner than walking', () {
      const far = LatLng(14.6850, 120.9560); // ~2.2 km: ~34 min on foot
      expect(WalkOption.offered(start, far), isNull);
      const nearish = LatLng(14.6800, 120.9560); // ~1.7 km: ~26 min
      final walk = WalkOption.offered(start, nearish)!;
      expect(WalkOption.rideWorthIt(12, walk), isTrue);
      expect(WalkOption.rideWorthIt(walk - 2, walk), isTrue);
      expect(WalkOption.rideWorthIt(walk + 1, walk), isFalse);
    });
  });
}
