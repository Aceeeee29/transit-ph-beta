import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/services/supabase_route_service.dart';

import 'obando_routes_fixture.dart';

CommunityRoute rider(
  String id,
  String start,
  String end,
  String mode,
  List<LatLng> path,
) {
  return CommunityRoute(
    id: id,
    startLocation: start,
    endLocation: end,
    steps: [
      CommunityRouteStep(mode: mode, instruction: 'Ride to $end', path: path),
    ],
  );
}

void main() {
  final routes = [
    rider(
      't',
      'Panghulo Obando',
      'Tatawid Malabon',
      'Tricycle',
      panghuloToTatawidTricycle,
    ),
    rider(
      'j',
      'Tatawid Malabon',
      'Sangandaan, Caloocan',
      'Jeepney',
      tatawidToSangandaanJeep,
    ),
    rider(
      's',
      'SM Sangandaan',
      'Monumento Caloocan',
      'Jeepney',
      smSangandaanToMonumentoJeep,
    ),
  ];

  // 253 Galicia, Obando: ~330 m from the tricycle route, ~800 m in a
  // straight line from where the Tatawid jeep starts.
  const galicia = LatLng(14.693691, 120.952111);
  const monumento = LatLng(14.654367, 120.983894);

  for (final mode in [
    RouteOptimizationMode.balanced,
    RouteOptimizationMode.community,
  ]) {
    test('$mode: rides the nearby tricycle instead of walking 1 km', () async {
      final alternatives =
          await SupabaseRouteService.planWithCommunityRoutesOnly(
            origin: galicia,
            destination: monumento,
            communityRoutes: routes,
            optimizationMode: mode,
          );

      expect(alternatives, isNotEmpty);
      final best = alternatives.first;
      final labels = [
        for (final leg in best.result.plan.legs) leg.communityLabel ?? '',
      ];
      expect(labels, hasLength(3));
      expect(labels[0], contains('Panghulo Obando → Tatawid Malabon'));
      expect(labels[1], contains('Tatawid Malabon → Sangandaan'));
      expect(labels[2], contains('SM Sangandaan → Monumento'));
      expect(best.totalWalkKm, lessThan(1.0));
    });
  }

  test(
    'community search walks to a rider route only up to 20 minutes',
    () async {
      // ~3 km from the nearest point of any of the routes.
      const farAway = LatLng(14.7200, 120.9300);
      final alternatives =
          await SupabaseRouteService.planWithCommunityRoutesOnly(
            origin: farAway,
            destination: monumento,
            communityRoutes: routes,
            optimizationMode: RouteOptimizationMode.community,
          );
      expect(alternatives, isEmpty);
    },
  );
}
