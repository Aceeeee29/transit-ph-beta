import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/services/fare_matrix.dart';
import 'package:transitph_beta/services/route_metrics_service.dart';
import 'package:transitph_beta/services/supabase_route_service.dart';

void main() {
  group('fare matrix', () {
    test('base fares cover the first kilometres', () {
      expect(PhFareCalculator.compute('Jeepney', 3000), 14);
      expect(PhFareCalculator.compute('Bus', 4000), 18);
      expect(PhFareCalculator.compute('Tricycle', 1500), 16);
      expect(PhFareCalculator.compute('FX/Van', 5000), 40);
      expect(PhFareCalculator.compute('Walk', 5000), 0);
    });

    test('per-km rate applies after the base distance', () {
      // 6 km jeepney: ₱14 + 2 km × ₱1.94.
      expect(PhFareCalculator.compute('Jeepney', 6000), closeTo(17.88, 0.001));
      // Buses over 10 km switch to the aircon rate.
      expect(PhFareCalculator.compute('Bus', 12000), closeTo(18 + 7 * 3.18, 0.001));
    });

    test('train fares stay within the LRT/MRT range', () {
      expect(PhFareCalculator.compute('Train', 500), PhFareCalculator.trainMin);
      expect(PhFareCalculator.compute('Train', 40000), PhFareCalculator.trainMax);
    });

    test('mode names match regardless of case', () {
      expect(PhFareCalculator.compute('jeepney', 3000), 14);
      expect(PhFareCalculator.compute('fx/van', 3000), 40);
    });

    test('the route map and contribute screens use the same table', () {
      for (final mode in ['Jeepney', 'Bus', 'Tricycle', 'FX/Van', 'Train']) {
        expect(
          RouteMetricsService.calculateFareForMode(mode, 7.5),
          PhFareCalculator.compute(mode, 7500),
          reason: mode,
        );
      }
    });
  });

  group('stops between board and alight', () {
    final stops = {
      for (var i = 0; i < 6; i++)
        's$i': {'stop_lat': 14.60 + i * 0.01, 'stop_lon': 120.98},
    };
    LatLng at(int i) => LatLng(14.60 + i * 0.01, 120.98);
    const sequence = ['s0', 's1', 's2', 's3', 's4', 's5'];

    test('returns only the stops strictly between the two', () {
      final via = SupabaseRouteService.viaStopPoints(sequence, 's1', 's4', stops);
      expect(via, [at(2), at(3)]);
    });

    test('adjacent stops have nothing in between', () {
      expect(SupabaseRouteService.viaStopPoints(sequence, 's2', 's3', stops), isEmpty);
    });

    test('alighting before boarding yields nothing', () {
      expect(SupabaseRouteService.viaStopPoints(sequence, 's4', 's1', stops), isEmpty);
    });

    test('loop trips use the first alight after boarding', () {
      const loop = ['s0', 's1', 's2', 's1', 's3'];
      final via = SupabaseRouteService.viaStopPoints(loop, 's2', 's3', stops);
      expect(via, [at(1)]);
    });

    test('unknown trips yield nothing', () {
      expect(SupabaseRouteService.viaStopPoints(null, 's0', 's5', stops), isEmpty);
    });
  });
}
