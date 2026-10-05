import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/services/contribute_route_edit_service.dart';

void main() {
  geometryTests();

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

/// Straight north-going path, one vertex every [stepMeters].
List<LatLng> _northLine(int vertices, {double stepMeters = 100}) => [
  for (var i = 0; i < vertices; i++)
    LatLng(14.60 + i * stepMeters / 111320.0, 120.98),
];

Future<List<LatLng>> _straight(LatLng from, LatLng to) async => [from, to];

void geometryTests() {
  group('StepGeometry (via-point editing)', () {
    final path = _northLine(31); // 3 km
    final controls = [path[0], path[10], path[20], path[30]];

    test('splits a step at its control points and rebuilds it exactly', () {
      final g = StepGeometry.fromPath(path, controls);
      expect(g.controls, controls);
      expect(g.pieces, hasLength(3));
      expect(g.pieces[1].first, path[10]);
      expect(g.pieces[1].last, path[20]);
      expect(g.path, path);
    });

    test('moving a via point re-routes only the two pieces touching it',
        () async {
      final g = StepGeometry.fromPath(path, controls);
      const moved = LatLng(14.61, 120.99);
      final edited = await g.moveControl(1, moved, _straight);

      expect(edited.controls[1], moved);
      expect(edited.pieces[0], [path[0], moved]);
      expect(edited.pieces[1], [moved, path[20]]);
      expect(edited.pieces[2], g.pieces[2]); // untouched, exact geometry
    });

    test('inserting a via point splits just that piece', () async {
      final g = StepGeometry.fromPath(path, controls);
      const added = LatLng(14.615, 120.985);
      final edited = await g.insertControl(2, added, _straight);

      expect(edited.controls, hasLength(5));
      expect(edited.controls[3], added);
      expect(edited.pieces.sublist(0, 2), g.pieces.sublist(0, 2));
      expect(edited.pieces[2], [path[20], added]);
      expect(edited.pieces[3], [added, path[30]]);
    });

    test('removing a via point joins its two pieces', () async {
      final g = StepGeometry.fromPath(path, controls);
      final edited = await g.removeControl(1, _straight);

      expect(edited.controls, [path[0], path[20], path[30]]);
      expect(edited.pieces.first, [path[0], path[20]]);
      expect(edited.pieces.last, g.pieces.last);
    });

    test('the step start and end cannot be removed', () async {
      final g = StepGeometry.fromPath(path, controls);
      expect(identical(await g.removeControl(0, _straight), g), isTrue);
      expect(identical(await g.removeControl(3, _straight), g), isTrue);
    });

    test('a point dragged off the road lands where the road line ends',
        () async {
      final g = StepGeometry.fromPath(path, controls);
      const offRoad = LatLng(14.61, 120.99);
      const onRoad = LatLng(14.61, 120.985);
      // A vehicle router: the line stops at the road, not in the block.
      Future<List<LatLng>> toRoad(LatLng from, LatLng to) async =>
          [from, to == offRoad ? onRoad : to];

      final moved = await g.moveControl(1, offRoad, toRoad);
      expect(moved.controls[1], onRoad);
      expect(moved.pieces[1].first, onRoad); // the next piece starts there

      final inserted = await g.insertControl(2, offRoad, toRoad);
      expect(inserted.controls[3], onRoad);
      expect(inserted.pieces[3].first, onRoad);
    });

    test('older steps without points get one about every kilometre', () {
      final g = StepGeometry.fromPath(path, const []);
      expect(g.controls.first, path.first);
      expect(g.controls.last, path.last);
      expect(g.controls, hasLength(4)); // 0, ~1 km, ~2 km, 3 km
      expect(g.path, path);
    });
  });
}
