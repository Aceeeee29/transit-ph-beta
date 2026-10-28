import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/models/ors_route_result.dart';
import 'package:transitph_beta/services/routing_service.dart';

void main() {
  // Network requests fail in tests (status 400), and there is no device
  // storage: no walking router or saved walk can answer.
  TestWidgetsFlutterBinding.ensureInitialized();

  const galicia = LatLng(14.69359, 120.95207);
  const park = LatLng(14.69542, 120.95394);

  test('no walking path is no walk, never a straight line', () async {
    expect(await RoutingService.walkPath(galicia, park), isNull);
    await expectLater(
      RoutingService.buildWalkFallbackRoute(origin: galicia, destination: park),
      throwsA(isA<RoutingException>()),
    );
  });

  test('a walk with no path found keeps its mark when saved', () {
    const step = OrsStep(
      instruction: 'Walk to Monumento (exact path unavailable)',
      distanceMeters: 390,
      durationSeconds: 281,
      suggestedMode: 'Walk',
      wayPointEnd: 1,
      isEstimatedPath: true,
    );
    expect(OrsStep.fromJson(step.toJson()).isEstimatedPath, isTrue);
    const real = OrsStep(
      instruction: 'Walk to Monumento',
      distanceMeters: 300,
      durationSeconds: 216,
    );
    expect(real.toJson().containsKey('isEstimatedPath'), isFalse);
    expect(OrsStep.fromJson(real.toJson()).isEstimatedPath, isFalse);
  });
}
