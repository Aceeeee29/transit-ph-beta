import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/services/route_metrics_service.dart';

void main() {
  test('saved ETAs are read in minutes, hours included', () {
    expect(RouteMetricsService.parseEtaMinutes('25'), 25);
    expect(RouteMetricsService.parseEtaMinutes('25 min'), 25);
    expect(RouteMetricsService.parseEtaMinutes('1 h 5 min'), 65);
    expect(RouteMetricsService.parseEtaMinutes('2 hrs'), 120);
    expect(RouteMetricsService.parseEtaMinutes('0 min'), isNull);
    expect(RouteMetricsService.parseEtaMinutes(''), isNull);
    expect(RouteMetricsService.parseEtaMinutes(null), isNull);
  });

  route_model.Route route({String? eta, String? distance}) => route_model.Route(
    id: 'r',
    startLocation: 'A',
    endLocation: 'B',
    shortDescription: '',
    eta: eta,
    distance: distance,
    // About 2.2 km north.
    pathPoints: const [LatLng(14.60, 121.0), LatLng(14.62, 121.0)],
    steps: [route_model.Step(mode: 'Jeepney', instruction: '', details: '')],
  );

  test('a route saved with "0 min" shows a time from its line', () {
    expect(RouteMetricsService.routeEtaMinutes(route(eta: '40 min')), 40);
    final estimated = RouteMetricsService.routeEtaMinutes(route(eta: '0 min'));
    expect(estimated, isNotNull);
    expect(estimated, greaterThan(0));
    expect(
      RouteMetricsService.routeEtaLabel(route(eta: '0 min')),
      isNot('0 min'),
    );
  });

  test('a route saved with "0 m" shows its measured length', () {
    expect(
      RouteMetricsService.routeDistanceKm(route(distance: '0 m')),
      closeTo(2.2, 0.1),
    );
  });

  test('whole hours have no trailing space', () {
    expect(RouteMetricsService.formatEta(60), '1 h');
    expect(RouteMetricsService.formatEta(65), '1 h 5 min');
  });
}
