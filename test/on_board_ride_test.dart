import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/services/supabase_route_service.dart';

/// A straight line with a point about every 100 m.
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

CommunityRoute rideRoute({
  required String mode,
  required bool designatedStops,
}) => CommunityRoute(
  id: 'ride',
  startLocation: 'VGC Terminal',
  endLocation: 'STI College Caloocan',
  steps: [
    CommunityRouteStep(
      mode: mode,
      instruction: 'Ride it',
      // About 9 km, north to south.
      path: line(
        const LatLng(14.7400, 120.9800),
        const LatLng(14.6600, 120.9800),
      ),
      designatedStops: designatedStops,
    ),
  ],
);

void main() {
  // Halfway along the route, on the road.
  const midRoute = LatLng(14.7000, 120.9801);
  // 300 m past the route's end.
  const nearEnd = LatLng(14.6573, 120.9800);
  const onBus = OnBoardRide(routeId: 'ride', stepIndex: 0, point: midRoute);

  test('standing by the road mid-route, a fixed-stop bus is no use', () async {
    final options = await SupabaseRouteService.planWithCommunityRoutesOnly(
      origin: midRoute,
      destination: nearEnd,
      communityRoutes: [rideRoute(mode: 'Bus', designatedStops: true)],
    );
    // It only picks people up at VGC Terminal, 4.4 km back.
    expect(
      options.where(
        (o) => o.result.plan.legs.any((leg) => leg.communityLabel != null),
      ),
      isEmpty,
    );
  });

  test('already on that bus, you stay on to its last stop', () async {
    final options = await SupabaseRouteService.planWithCommunityRoutesOnly(
      origin: midRoute,
      destination: nearEnd,
      communityRoutes: [rideRoute(mode: 'Bus', designatedStops: true)],
      onBoard: onBus,
    );
    expect(options, isNotEmpty);
    for (final option in options) {
      final first = option.result.plan.legs.first;
      expect(first.communityLabel, startsWith('Stay on the Bus'));
      expect(first.communityLabel, contains('get off at STI College Caloocan'));
      // Already paid when you got on.
      expect(first.communityFare, 0);
    }
  });

  test('already on a jeep, you can get off before its end', () async {
    // 1.5 km before the jeep's last stop, right by its road.
    const beforeEnd = LatLng(14.6735, 120.9802);
    final options = await SupabaseRouteService.planWithCommunityRoutesOnly(
      origin: midRoute,
      destination: beforeEnd,
      communityRoutes: [rideRoute(mode: 'Jeepney', designatedStops: false)],
      onBoard: onBus,
    );
    expect(options, isNotEmpty);
    final leg = options.first.result.plan.legs.single;
    expect(leg.communityLabel, startsWith('Stay on the Jeepney'));
    // It gets off near where you're going, not at the end 1.5 km later.
    const d = Distance();
    expect(
      d.as(LengthUnit.Meter, LatLng(leg.alightLat, leg.alightLon), beforeEnd),
      lessThan(400),
    );
  });
}
