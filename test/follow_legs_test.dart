import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/services/follow_legs.dart';
import 'package:transitph_beta/services/route_follow_engine.dart';
import 'package:transitph_beta/services/route_follow_guidance.dart';

void main() {
  // About 1.1 km per 0.01° of latitude: walk 0→1, a transfer on the spot
  // at 1, then a jeepney 1→3.
  final engine = RouteFollowEngine(const [
    LatLng(14.60, 121.0),
    LatLng(14.61, 121.0),
    LatLng(14.62, 121.0),
    LatLng(14.63, 121.0),
  ]);
  const steps = [
    FollowStep(mode: 'Walk', startIndex: 0, endIndex: 1),
    FollowStep(mode: 'Walk', startIndex: 1, endIndex: 1),
    FollowStep(
      mode: 'Jeepney',
      startIndex: 1,
      endIndex: 3,
      endName: 'Balintawak',
    ),
  ];

  FollowLegProgress at(double meters) =>
      FollowLegs.locate(engine: engine, steps: steps, progressMeters: meters)!;

  test('finds the step being travelled and what is left of it', () {
    final walk = at(500);
    expect(walk.index, 0);
    expect(walk.metersLeft, closeTo(engine.alongAt(1) - 500, 0.01));

    // The transfer on the spot is passed over.
    final ride = at(engine.alongAt(1) + 10);
    expect(ride.index, 2);
    expect(ride.legMeters, closeTo(engine.alongAt(3) - engine.alongAt(1), 1));

    final end = at(engine.totalMeters + 50);
    expect(end.index, 2);
    expect(end.metersLeft, 0);
  });

  test('"Get off soon" shows only near the end of a long ride', () {
    expect(at(engine.alongAt(1) + 100).isGetOffSoon(steps), isFalse);
    expect(at(engine.totalMeters - 250).isGetOffSoon(steps), isTrue);
    // Never on foot.
    expect(at(engine.alongAt(1) - 100).isGetOffSoon(steps), isFalse);
  });

  test('rider steps are named by their stops and the route ends', () {
    final route = route_model.Route(
      id: 'r',
      startLocation: 'Monumento',
      endLocation: 'STI Caloocan',
      shortDescription: '',
      steps: [
        route_model.Step(mode: 'Walk', instruction: '', details: ''),
        route_model.Step(mode: 'Jeepney', instruction: '', details: ''),
      ],
    );
    expect(FollowLegs.riderStepEnds(route, 0), (from: 'Monumento', to: null));
    expect(FollowLegs.riderStepEnds(route, 1), (
      from: null,
      to: 'STI Caloocan',
    ));
  });
}
