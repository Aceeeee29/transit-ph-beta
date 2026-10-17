import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/models/route_issue_report.dart';
import 'package:transitph_beta/services/route_report_service.dart';

import 'obando_routes_fixture.dart';

RouteIssueReport report(
  List<LatLng> path, {
  Duration age = const Duration(hours: 1),
  bool kept = false,
}) {
  final created = DateTime.now().subtract(age);
  return RouteIssueReport(
    id: 'r',
    routeId: 'tatawid',
    routeLabel: 'Tatawid Malabon → Sangandaan, Caloocan',
    type: 'Route changed',
    reporterId: 'u',
    path: path,
    createdAt: created,
    expiresAt: kept ? DateTime(2100) : created.add(RouteReportService.lifetime),
    kept: kept,
  );
}

double lengthOf(List<LatLng> path) {
  const d = Distance();
  var total = 0.0;
  for (var i = 0; i < path.length - 1; i++) {
    total += d.as(LengthUnit.Meter, path[i], path[i + 1]);
  }
  return total;
}

void main() {
  const jeep = tatawidToSangandaanJeep;

  test('a route on the whole reported road shares all of it', () {
    final shared = RouteReportService.sharedMeters(jeep, jeep);
    expect(shared, closeTo(lengthOf(jeep), lengthOf(jeep) * 0.02));
  });

  test('another route on part of the same road gets the report', () {
    // Rides about a third of the jeep's road, then turns off.
    final part = jeep.sublist(20, 55);
    final route = [...part, const LatLng(14.6700, 120.9900)];
    expect(lengthOf(part), greaterThan(RouteReportService.minSharedMeters));
    expect(
      RouteReportService.reportsOnRoad(route, [report(jeep)]),
      hasLength(1),
    );
  });

  test('a route that only crosses the reported road does not', () {
    final middle = jeep[50];
    final crossing = [
      LatLng(middle.latitude, middle.longitude - 0.01),
      LatLng(middle.latitude, middle.longitude + 0.01),
    ];
    expect(RouteReportService.reportsOnRoad(crossing, [report(jeep)]), isEmpty);
  });

  test('a route elsewhere does not', () {
    expect(
      RouteReportService.reportsOnRoad(
        panghuloToTatawidTricycle.reversed
            .map((p) => LatLng(p.latitude + 0.05, p.longitude))
            .toList(),
        [report(jeep)],
      ),
      isEmpty,
    );
  });

  test('reports stop showing after a day unless kept', () {
    final old = report(jeep, age: const Duration(hours: 25));
    final keptOld = report(jeep, age: const Duration(days: 3), kept: true);
    expect(RouteReportService.reportsOnRoad(jeep, [old]), isEmpty);
    expect(RouteReportService.reportsOnRoad(jeep, [keptOld]), hasLength(1));
  });
}
