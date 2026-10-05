import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/services/route_follow_engine.dart';
import 'package:transitph_beta/services/route_follow_guidance.dart';
import 'package:transitph_beta/services/supabase_route_service.dart';

/// Straight path with a point roughly every 100 m.
List<LatLng> line(LatLng from, LatLng to) {
  const d = Distance();
  final count = (d.as(LengthUnit.Meter, from, to) / 100).ceil().clamp(2, 500);
  return [
    for (var i = 0; i <= count; i++)
      LatLng(
        from.latitude + (to.latitude - from.latitude) * i / count,
        from.longitude + (to.longitude - from.longitude) * i / count,
      ),
  ];
}

void main() {
  const malintaStop = route_model.RouteStop(
    lat: 14.6800,
    lng: 120.9843,
    name: 'Malinta Stop',
  );
  const graceStop = route_model.RouteStop(
    lat: 14.6400,
    lng: 120.9843,
    name: 'Grace Stop',
  );

  test('boarding rule and stops survive saving and loading', () {
    final route = route_model.Route(
      id: 'bus1',
      startLocation: 'Polo',
      endLocation: 'South',
      shortDescription: '',
      steps: [
        route_model.Step(
          mode: 'Bus',
          instruction: 'Ride the bus',
          details: '',
          boarding: route_model.StepBoarding.designated,
          stops: [malintaStop, graceStop.copyWith(pickup: false)],
          controlPoints: const [LatLng(14.70, 120.98), LatLng(14.66, 120.98)],
        ),
        route_model.Step(mode: 'Jeepney', instruction: 'Jeep', details: ''),
      ],
      pathPoints: const [LatLng(14.70, 120.98), LatLng(14.62, 120.98)],
      stepBoundaries: const [1, 1],
    );

    final loaded = route_model.Route.fromJson(route.toJson());
    final bus = loaded.steps.first;
    expect(bus.boarding, route_model.StepBoarding.designated);
    expect(bus.stops.map((s) => s.name), ['Malinta Stop', 'Grace Stop']);
    expect(bus.stops.last.pickup, isFalse);
    expect(bus.stops.last.dropoff, isTrue);
    expect(bus.usesDesignatedStops, isTrue);
    expect(bus.controlPoints, const [
      LatLng(14.70, 120.98),
      LatLng(14.66, 120.98),
    ]);

    // Older steps without the fields stay flexible.
    final jeep = loaded.steps.last;
    expect(jeep.boarding, isNull);
    expect(jeep.stops, isEmpty);
    expect(jeep.controlPoints, isEmpty);
    expect(jeep.usesDesignatedStops, isFalse);
  });

  test('designated with no stops yet still uses only its two ends', () {
    final step = route_model.Step(
      mode: 'Bus',
      instruction: '',
      details: '',
      boarding: route_model.StepBoarding.designated,
    );
    expect(step.usesDesignatedStops, isTrue);
  });

  test('a designated bus with no stops mapped is not left mid-route',
      () async {
    // Like the VGC bus: down the expressway, stops not mapped yet.
    final busRoute = CommunityRoute(
      id: 'bus',
      startLocation: 'VGC Terminal',
      endLocation: 'Yamaha Monumento',
      steps: [
        CommunityRouteStep(
          mode: 'Bus',
          instruction: 'Ride the bus',
          path: line(
            const LatLng(14.7000, 120.9843),
            const LatLng(14.6200, 120.9843),
          ),
          designatedStops: true,
        ),
      ],
    );

    final alternatives = await SupabaseRouteService.planWithCommunityRoutesOnly(
      origin: const LatLng(14.6996, 120.9845),
      // 1.7 km short of the end: a flexible jeep would let you off here.
      destination: const LatLng(14.6350, 120.9850),
      communityRoutes: [busRoute],
    );

    expect(alternatives, isNotEmpty);
    final label = alternatives.first.result.plan.legs.single.communityLabel!;
    expect(label, contains('get off at Yamaha Monumento'));
  });

  test('new-step defaults: buses designated, jeepneys flexible', () {
    expect(
      route_model.Step.defaultBoardingFor('Bus'),
      route_model.StepBoarding.designated,
    );
    expect(
      route_model.Step.defaultBoardingFor('Jeepney'),
      route_model.StepBoarding.flexible,
    );
  });

  test('the router only drops passengers off at designated stops', () async {
    final busRoute = CommunityRoute(
      id: 'bus',
      startLocation: 'Polo',
      endLocation: 'South',
      steps: [
        CommunityRouteStep(
          mode: 'Bus',
          instruction: 'Ride the bus',
          path: line(
            const LatLng(14.7000, 120.9843),
            const LatLng(14.6200, 120.9843),
          ),
          stops: const [malintaStop, graceStop],
        ),
      ],
    );

    final alternatives = await SupabaseRouteService.planWithCommunityRoutesOnly(
      origin: const LatLng(14.6996, 120.9845),
      // Between the two stops, closer to Grace Stop.
      destination: const LatLng(14.6550, 120.9845),
      communityRoutes: [busRoute],
    );

    expect(alternatives, isNotEmpty);
    final label = alternatives.first.result.plan.legs.single.communityLabel!;
    expect(label, contains('get off at Grace Stop'));
  });

  group('guidance with designated stops', () {
    final path = line(
      const LatLng(14.7000, 120.9843),
      const LatLng(14.6200, 120.9843),
    );
    final steps = [
      FollowStep(
        mode: 'Bus',
        startIndex: 0,
        endIndex: path.length - 1,
        designatedStops: true,
        stops: [
          FollowStop(point: malintaStop.point, name: malintaStop.name),
          FollowStop(point: graceStop.point, name: graceStop.name),
        ],
      ),
    ];

    test('approach: walk to the nearest stop, not the nearest point', () {
      final engine = RouteFollowEngine(path);
      // 200 m east of the line, 300 m north of Malinta Stop.
      final snapshot = engine.update(const LatLng(14.6827, 120.9862));
      final g = FollowGuidancePlanner.plan(
        engine: engine,
        snapshot: snapshot,
        steps: steps,
        speedMps: 1,
      );

      expect(g.kind, FollowGuidanceKind.approach);
      expect(g.atDesignatedStop, isTrue);
      expect(g.stopName, 'Malinta Stop');
      expect(g.target, malintaStop.point);
    });

    test('rejoin on foot: the next stop ahead', () {
      final engine = RouteFollowEngine(path);
      final t0 = DateTime(2026, 10, 1, 8);
      engine.update(path.first, at: t0);
      engine.update(const LatLng(14.6900, 120.9843), at: t0);
      late FollowGuidance g;
      for (var s = 1; s <= 12; s++) {
        final at = t0.add(Duration(seconds: s));
        final snapshot = engine.update(
          const LatLng(14.6880, 120.9870),
          at: at,
        );
        g = FollowGuidancePlanner.plan(
          engine: engine,
          snapshot: snapshot,
          steps: steps,
          speedMps: 1.2,
          now: at,
        );
      }

      expect(g.kind, FollowGuidanceKind.rejoin);
      expect(g.stopName, 'Malinta Stop');
    });
  });
}
