import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/models/ors_route_result.dart';
import 'package:transitph_beta/services/fare_matrix.dart';

void main() {
  test('only jeepneys and buses give the discount', () {
    for (final mode in ['Jeepney', 'Bus', 'EDSA Carousel', 'jeep']) {
      expect(PhFareCalculator.givesDiscount(mode), isTrue, reason: mode);
    }
    for (final mode in ['Tricycle', 'Train', 'FX/Van', 'Ferry', 'Walk']) {
      expect(PhFareCalculator.givesDiscount(mode), isFalse, reason: mode);
    }
  });

  test('a ride is discounted only on a jeepney or bus', () {
    expect(PhFareCalculator.rideFare(14, 'Jeepney', discount: true), 12);
    expect(PhFareCalculator.rideFare(16, 'Tricycle', discount: true), 16);
    expect(PhFareCalculator.rideFare(14, 'Jeepney', discount: false), 14);
  });

  test('a trip takes the discount off its jeepney and bus rides only', () {
    const trip = OrsRouteResult(
      distanceMeters: 8000,
      durationSeconds: 2400,
      polyline: [],
      steps: [
        OrsStep(
          instruction: 'Tricycle',
          distanceMeters: 1000,
          durationSeconds: 300,
          suggestedMode: 'Tricycle',
          estimatedFare: 16,
        ),
        OrsStep(
          instruction: 'Jeep',
          distanceMeters: 5000,
          durationSeconds: 1200,
          suggestedMode: 'Jeepney',
          estimatedFare: 14,
        ),
        OrsStep(
          instruction: 'Train',
          distanceMeters: 2000,
          durationSeconds: 900,
          suggestedMode: 'Train',
          estimatedFare: 20,
        ),
      ],
      bbox: [],
    );
    expect(PhFareCalculator.tripFare(trip, discount: false), 50);
    // Only the ₱14 jeep becomes ₱12.
    expect(PhFareCalculator.tripFare(trip, discount: true), 48);
  });
}
