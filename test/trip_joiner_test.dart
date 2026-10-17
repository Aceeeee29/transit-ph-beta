import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/models/ors_route_result.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/services/trip_joiner.dart';

void main() {
  // The way to Monumento (generated), then Monumento → STI (a rider route).
  const toStart = OrsRouteResult(
    distanceMeters: 6000,
    durationSeconds: 1800,
    polyline: [
      LatLng(14.7150, 120.9850),
      LatLng(14.6900, 120.9840),
      LatLng(14.6546, 120.9839),
    ],
    steps: [
      OrsStep(
        instruction: 'Ride Jeepney along the community route VGC → Monumento',
        distanceMeters: 6000,
        durationSeconds: 1800,
        estimatedFare: 15,
        wayPointStart: 0,
        wayPointEnd: 2,
        isCommunity: true,
      ),
    ],
    bbox: [],
  );
  final route = route_model.Route(
    id: 'monu-sti',
    startLocation: 'Monumento',
    endLocation: 'STI Caloocan',
    shortDescription: '',
    steps: [
      route_model.Step(
        mode: 'Jeepney',
        instruction: 'Ride the jeep to 5th Ave',
        details: '',
        actualFare: 13,
      ),
      route_model.Step(mode: 'Walk', instruction: '', details: ''),
    ],
  );
  const routePath = [
    LatLng(14.6546, 120.9839),
    LatLng(14.6400, 120.9860),
    LatLng(14.6250, 120.9880),
    LatLng(14.6200, 120.9900),
  ];

  final trip = TripJoiner.join(
    toStart: toStart,
    route: route,
    routePath: routePath,
    stepRanges: const [(start: 0, end: 2), (start: 2, end: 3)],
  );

  test('the rider route follows the way to its start', () {
    expect(trip.polyline, [...toStart.polyline, ...routePath]);
    expect(trip.steps, hasLength(3));
    // Its steps point into the joined line.
    expect(trip.steps[1].wayPointStart, 3);
    expect(trip.steps[1].wayPointEnd, 5);
    expect(trip.steps[2].wayPointStart, 5);
    expect(trip.steps[2].wayPointEnd, 6);
    expect(trip.steps[1].isCommunity, isTrue);
    expect(trip.steps[1].instruction, contains('Monumento → STI Caloocan'));
    expect(trip.steps[2].suggestedMode, 'Walk');
  });

  test('fares, distance and time add up', () {
    // ₱15 to get there, the contributor's ₱13 jeep, walking is free.
    expect(trip.baseFarePhp, 28);
    expect(trip.distanceMeters, greaterThan(toStart.distanceMeters + 3500));
    expect(trip.durationSeconds, greaterThan(toStart.durationSeconds));
  });

  test('the title names both parts', () {
    expect(
      TripJoiner.title(firstFrom: 'VGC Terminal', route: route),
      'VGC Terminal → Monumento + Monumento → STI Caloocan',
    );
  });
}
