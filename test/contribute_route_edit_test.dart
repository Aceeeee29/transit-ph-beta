import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/services/contribute_route_edit_service.dart';

void main() {
  group('ContributeRouteEditService.rebuildFromStepControlPoints', () {
    final steps = [
      route_model.Step(mode: 'Bus', instruction: 'Bus', details: ''),
      route_model.Step(mode: 'Jeepney', instruction: 'Jeep', details: ''),
    ];
    // Step 0 has detailed geometry (e.g. staying on the expressway);
    // step 1 is a simple line.
    const p = [
      LatLng(14.700, 120.990),
      LatLng(14.695, 120.995),
      LatLng(14.690, 120.996),
      LatLng(14.685, 120.994),
      LatLng(14.680, 120.990),
      LatLng(14.675, 120.988),
      LatLng(14.670, 120.986),
    ];
    final baseline = ContributionRouteBaseline(
      stepControlPoints: [
        [p[0], p[2], p[4]],
        [p[4], p[5], p[6]],
      ],
      pathPoints: p,
      stepBoundaries: const [4, 6],
      stepOrsDistM: const [3200, 1100],
      stepOrsDurS: const [400, 200],
    );

    test('dragging one step keeps the other step exactly as drawn', () async {
      const moved = LatLng(14.674, 120.980);
      final rebuilt =
          await ContributeRouteEditService.rebuildFromStepControlPoints(
            steps: steps,
            stepControlPoints: [
              [p[0], p[2], p[4]],
              [p[4], moved, p[6]],
            ],
            snapToRoadEnabled: false,
            baseline: baseline,
          );

      expect(rebuilt.pathPoints.sublist(0, 5), p.sublist(0, 5));
      expect(rebuilt.stepOrsDistM.first, 3200);
      expect(rebuilt.pathPoints.sublist(4), [p[4], moved, p[6]]);
      expect(rebuilt.stepBoundaries, [4, 6]);
    });

    test('without a baseline every step is rebuilt from its controls', () async {
      final rebuilt =
          await ContributeRouteEditService.rebuildFromStepControlPoints(
            steps: steps,
            stepControlPoints: [
              [p[0], p[2], p[4]],
              [p[4], p[5], p[6]],
            ],
            snapToRoadEnabled: false,
          );

      expect(rebuilt.pathPoints, [p[0], p[2], p[4], p[5], p[6]]);
    });
  });
}
