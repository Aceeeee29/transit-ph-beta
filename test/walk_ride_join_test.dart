import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/services/walk_ride_join.dart';

/// Straight path with a point roughly every 50 m.
List<LatLng> line(LatLng from, LatLng to) {
  const d = Distance();
  final count = (d.as(LengthUnit.Meter, from, to) / 50).ceil().clamp(2, 500);
  return [
    for (var i = 0; i <= count; i++)
      LatLng(
        from.latitude + (to.latitude - from.latitude) * i / count,
        from.longitude + (to.longitude - from.longitude) * i / count,
      ),
  ];
}

double length(List<LatLng> points) {
  const d = Distance(roundResult: false);
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += d.as(LengthUnit.Meter, points[i - 1], points[i]);
  }
  return total;
}

void main() {
  const distance = Distance(roundResult: false);
  double meters(LatLng a, LatLng b) => distance.as(LengthUnit.Meter, a, b);

  // A tricycle road running ~1.1 km south from its start.
  const rideStart = LatLng(14.7000, 120.9800);
  const rideEnd = LatLng(14.6900, 120.9800);
  final ride = line(rideStart, rideEnd);

  group('WalkRideJoin.board', () {
    test('boards where the street walk first reaches the ride\'s road', () {
      // The street walk can't reach the start directly: it loops west and
      // south, meets the road ~330 m down, then walks up it to the start.
      const meet = LatLng(14.6970, 120.9800);
      final walk = [
        const LatLng(14.7020, 120.9790),
        const LatLng(14.7010, 120.9790),
        const LatLng(14.7010, 120.9750),
        const LatLng(14.6970, 120.9750),
        meet,
        ...line(meet, rideStart).skip(1),
      ];

      final joined = WalkRideJoin.board(walk, ride)!;
      expect(meters(joined.walk.last, meet), lessThan(10));
      expect(meters(joined.ride.first, meet), lessThan(10));
      expect(meters(joined.ride.last, rideEnd), lessThan(1));
      // No more walking up the road the tricycle then drives back down.
      expect(length(walk) - length(joined.walk), greaterThan(300));
      expect(length(joined.ride), closeTo(length(ride) - 330, 15));
    });

    test('catches a walk that crosses the road between its points', () {
      // Crosses the road ~400 m down (no walk point on it), then walks up a
      // parallel street 60 m east to opposite the start.
      final walk = [
        const LatLng(14.6965, 120.9790),
        const LatLng(14.6965, 120.9806),
        const LatLng(14.7000, 120.9806),
        rideStart,
      ];

      final joined = WalkRideJoin.board(walk, ride)!;
      expect(
        meters(joined.ride.first, const LatLng(14.6965, 120.9800)),
        lessThan(10),
      );
    });

    test('leaves a walk that goes straight to the start alone', () {
      final walk = [
        const LatLng(14.7030, 120.9800),
        const LatLng(14.7015, 120.9800),
        rideStart,
      ];
      expect(WalkRideJoin.board(walk, ride), isNull);
    });
  });

  group('WalkRideJoin.alight', () {
    test('gets off where the next walk leaves the ride\'s road', () {
      // From the end, the walk heads back up the road 550 m, then east.
      const leave = LatLng(14.6950, 120.9800);
      final walk = [...line(rideEnd, leave), const LatLng(14.6950, 120.9830)];

      final joined = WalkRideJoin.alight(ride, walk)!;
      expect(meters(joined.ride.last, leave), lessThan(10));
      expect(meters(joined.walk.first, leave), lessThan(10));
      expect(meters(joined.ride.first, rideStart), lessThan(1));
      expect(length(walk) - length(joined.walk), greaterThan(500));
    });

    test('leaves a walk that heads straight away alone', () {
      final walk = [rideEnd, const LatLng(14.6900, 120.9830)];
      expect(WalkRideJoin.alight(ride, walk), isNull);
    });
  });

  test('only modes you can flag down anywhere are joined', () {
    expect(WalkRideJoin.canHail('Jeepney'), isTrue);
    expect(WalkRideJoin.canHail('Tricycle'), isTrue);
    expect(WalkRideJoin.canHail('FX/Van'), isTrue);
    expect(WalkRideJoin.canHail('Bus'), isFalse);
    expect(WalkRideJoin.canHail('Train'), isFalse);
  });

  test('renames a stop moved far from where it was', () {
    const was = LatLng(14.7000, 120.9800);
    expect(
      WalkRideJoin.renamed('Punturin', was, const LatLng(14.6995, 120.98)),
      'Punturin',
    );
    expect(
      WalkRideJoin.renamed(
        'the stop near Bonifacio Monument',
        was,
        const LatLng(14.6970, 120.98),
      ),
      'the spot near Bonifacio Monument',
    );
  });
}
