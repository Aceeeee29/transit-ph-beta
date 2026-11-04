import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/services/ride_path_cleanup.dart';

void main() {
  // 0.0001° is about 11 m. A main road runs north along 121.0.
  List<LatLng> road(double fromLat, double toLat) => [
    for (var lat = fromLat; lat <= toLat + 1e-9; lat += 0.0005)
      LatLng(lat, 121.0),
  ];

  test('cuts a side trip into a side street and back', () {
    final path = [
      ...road(14.700, 14.705),
      // Into the side street to a stop 220 m east, then back.
      const LatLng(14.705, 121.001),
      const LatLng(14.705, 121.002),
      const LatLng(14.705, 121.001),
      const LatLng(14.705, 121.0),
      ...road(14.7055, 14.710),
    ];
    final cleaned = RidePathCleanup.removeSpurs(path);
    expect(cleaned.any((p) => p.longitude > 121.0005), isFalse);
    expect(cleaned.first, path.first);
    expect(cleaned.last, path.last);
  });

  test('cuts a loop around a block', () {
    final path = [
      ...road(14.700, 14.705),
      const LatLng(14.705, 121.0015),
      const LatLng(14.7065, 121.0015),
      const LatLng(14.7065, 121.0),
      const LatLng(14.7051, 121.0),
      ...road(14.7055, 14.710),
    ];
    final cleaned = RidePathCleanup.removeSpurs(path);
    expect(cleaned.any((p) => p.longitude > 121.0005), isFalse);
  });

  test('leaves a straight road alone', () {
    final path = road(14.700, 14.720);
    expect(RidePathCleanup.removeSpurs(path), path);
  });

  test('keeps a long loop that comes back to the same spot', () {
    // Around a block about 550 m by 330 m (1.8 km): too long to be a
    // snapping side trip, so it's the vehicle's real way.
    final path = [
      ...road(14.700, 14.705),
      const LatLng(14.705, 121.003),
      const LatLng(14.710, 121.003),
      const LatLng(14.710, 121.0),
      const LatLng(14.7051, 121.0),
      ...road(14.7055, 14.712),
    ];
    expect(RidePathCleanup.removeSpurs(path), path);
  });
}
