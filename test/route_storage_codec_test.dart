import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/repositories/followed_route_repository.dart';

void main() {
  test('an edited route (with a Firestore Timestamp) round-trips', () {
    final editedAt = DateTime(2026, 9, 30, 14, 5);
    final route = route_model.Route(
      id: 'r1',
      startLocation: 'STI Caloocan',
      endLocation: 'MCU Carousel',
      shortDescription: 'Jeep along EDSA',
      steps: [
        route_model.Step(mode: 'Jeepney', instruction: 'Ride', details: ''),
      ],
      pathPoints: const [LatLng(14.66, 120.98), LatLng(14.65, 120.98)],
      stepBoundaries: const [1],
      approvalStatus: route_model.RouteApprovalStatus.approved,
      isEdited: true,
      editedAt: editedAt,
      editCount: 2,
    );

    final decoded = RouteStorageCodec.decode(RouteStorageCodec.encode(route));

    expect(decoded.id, 'r1');
    expect(decoded.editedAt, editedAt);
    expect(decoded.pathPoints, route.pathPoints);
    expect(decoded.steps.single.mode, 'Jeepney');
    expect(decoded.isApproved, isTrue);
    expect(decoded.editCount, 2);
    expect(decoded.createdAt, isNull);
    expect(decoded.updatedAt, isNull);
    expect(decoded.reports, isEmpty);
    // What Download used before: plain jsonEncode can't write the Timestamp.
    expect(
      () => jsonEncode(route.toJson()),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );
  });
}
