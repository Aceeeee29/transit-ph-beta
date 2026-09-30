import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
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

CommunityRoute jeepRoute(
  String id,
  String start,
  String end,
  LatLng from,
  LatLng to, {
  double? fare,
}) {
  return CommunityRoute(
    id: id,
    startLocation: start,
    endLocation: end,
    steps: [
      CommunityRouteStep(
        mode: 'Jeepney',
        instruction: 'Ride the jeep signed $end',
        path: line(from, to),
        actualFare: fare,
      ),
    ],
  );
}

void main() {
  const monumento = LatLng(14.6546, 120.9839);
  const nearMonumento = LatLng(14.6555, 120.9845); // ~120 m away
  const stiArea = LatLng(14.6200, 120.9900);
  const vgcArea = LatLng(14.7150, 120.9850);
  const distance = Distance();

  // STI → Monumento, and VGC → Monumento (drawn toward Monumento).
  final stiToMonumento = jeepRoute(
    'a',
    'STI Caloocan',
    'Monumento',
    stiArea,
    monumento,
    fare: 13,
  );
  final vgcToMonumento = jeepRoute(
    'b',
    'VGC Canumay',
    'Monumento',
    vgcArea,
    nearMonumento,
  );

  group('community routes in route generation', () {
    test('combines two contributed routes that meet at Monumento', () async {
      final alternatives =
          await SupabaseRouteService.planWithCommunityRoutesOnly(
            origin: const LatLng(14.6204, 120.9903),
            destination: const LatLng(14.7154, 120.9853),
            communityRoutes: [stiToMonumento, vgcToMonumento],
          );

      expect(alternatives, isNotEmpty);
      final legs = alternatives.first.result.plan.legs;
      expect(legs, hasLength(2));

      expect(legs[0].isCommunity, isTrue);
      expect(legs[0].communityLabel, contains('STI Caloocan → Monumento'));
      expect(legs[0].communityLabel, isNot(contains('opposite direction')));

      expect(legs[0].communityLabel, contains('get off at Monumento'));

      // The second route is ridden against its drawn direction.
      expect(legs[1].communityLabel, contains('Monumento → VGC Canumay'));
      expect(legs[1].communityLabel, contains('get off at VGC Canumay'));
      expect(legs[1].communityLabel, contains('opposite direction'));

      // Its geometry must run Monumento → VGC, i.e. already reversed.
      final path = legs[1].communityPath!;
      expect(distance.as(LengthUnit.Meter, path.first, nearMonumento),
          lessThan(400));
      expect(distance.as(LengthUnit.Meter, path.last, vgcArea), lessThan(400));
    });

    test('a full forward ride uses the contributor fare', () async {
      final alternatives =
          await SupabaseRouteService.planWithCommunityRoutesOnly(
            origin: const LatLng(14.6204, 120.9903),
            destination: const LatLng(14.6549, 120.9841),
            communityRoutes: [stiToMonumento],
          );

      expect(alternatives, isNotEmpty);
      final legs = alternatives.first.result.plan.legs;
      expect(legs, hasLength(1));
      expect(legs.single.communityFare, 13);
      expect(legs.single.communityLabel, contains('Ride the jeep signed'));
    });

    test('names a mid-route drop-off after the nearest known place', () async {
      // Runs north→south straight past SM City Grand Central.
      final poloToSouth = jeepRoute(
        'c',
        'Polo',
        'Somewhere South',
        const LatLng(14.7000, 120.9843),
        const LatLng(14.6200, 120.9843),
      );
      final alternatives =
          await SupabaseRouteService.planWithCommunityRoutesOnly(
            origin: const LatLng(14.6996, 120.9845),
            destination: const LatLng(14.654965, 120.984256),
            communityRoutes: [poloToSouth],
          );

      expect(alternatives, isNotEmpty);
      final label = alternatives.first.result.plan.legs.single.communityLabel!;
      expect(label, contains('get off at the stop near'));
      expect(label, matches(RegExp('SM City Grand Central|Bonifacio Monument')));
    });

    test('no route when community routes do not reach the destination',
        () async {
      final alternatives =
          await SupabaseRouteService.planWithCommunityRoutesOnly(
            origin: const LatLng(14.6204, 120.9903),
            destination: const LatLng(14.7154, 120.9853),
            communityRoutes: [stiToMonumento],
          );
      expect(alternatives, isEmpty);
    });
  });

  group('CommunityRoute.fromRoute', () {
    route_model.Route route({
      required route_model.RouteApprovalStatus status,
      List<int> boundaries = const [2, 5],
    }) {
      return route_model.Route(
        id: 'r1',
        startLocation: 'A',
        endLocation: 'B',
        shortDescription: '',
        approvalStatus: status,
        pathPoints: line(stiArea, monumento).take(6).toList(),
        stepBoundaries: boundaries,
        steps: [
          route_model.Step(mode: 'Walk', instruction: 'Walk', details: ''),
          route_model.Step(
            mode: 'Jeepney',
            instruction: 'Ride',
            details: 'x',
            actualFare: 15,
          ),
        ],
      );
    }

    test('splits the drawn path into steps at the step boundaries', () {
      final community = CommunityRoute.fromRoute(
        route(status: route_model.RouteApprovalStatus.approved),
      )!;
      expect(community.steps, hasLength(2));
      expect(community.steps[0].path, hasLength(3)); // indices 0..2
      expect(community.steps[1].path, hasLength(4)); // indices 2..5
      expect(community.steps[1].actualFare, 15);
    });

    test('ignores routes that are not approved', () {
      expect(
        CommunityRoute.fromRoute(
          route(status: route_model.RouteApprovalStatus.pending),
        ),
        isNull,
      );
    });

    test('skips multi-step routes saved without step boundaries', () {
      expect(
        CommunityRoute.fromRoute(
          route(
            status: route_model.RouteApprovalStatus.approved,
            boundaries: const [],
          ),
        ),
        isNull,
      );
    });
  });
}
