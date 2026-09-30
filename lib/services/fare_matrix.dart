// =============================================================================
// PHILIPPINE FARE MATRIX
//
// The single source for every fare TransitPH computes or displays: route
// generation, the route map, the contribute screen, the Fare Matrix dialog
// and the search help sheet all read from here. Change fares in this file only.
//
// Base fares: jeepney ₱14, bus ₱18, tricycle ₱16, FX/UV ₱40. Each mode's
// per-km rate was scaled by the same percentage as its base fare change from
// the previous LTFRB rates (e.g. jeepney ₱13 → ₱14 is +7.7%, so ₱1.80/km →
// ₱1.94/km). LRT/MRT fares are unchanged.
// =============================================================================

/// [base] covers the first [baseKm] kilometres; every km after that adds
/// [perKm]. [typicalKm] is the long end of an everyday CAMANAVA ride on this
/// mode, used only for the "₱18 – ₱30" estimate shown in the Fare Matrix.
class FareRule {
  final double base;
  final double baseKm;
  final double perKm;
  final double typicalKm;

  const FareRule({
    required this.base,
    required this.baseKm,
    required this.perKm,
    required this.typicalKm,
  });

  double fareForKm(double distanceKm) =>
      distanceKm <= baseKm ? base : base + (distanceKm - baseKm) * perKm;

  /// "₱18 – ₱30": the base fare up to a [typicalKm] ride, rounded up to the
  /// next ₱5.
  String get estimateRange {
    final high = (fareForKm(typicalKm) / 5).ceil() * 5.0;
    return '${PhFareCalculator.peso(base)} – ${PhFareCalculator.peso(high)}';
  }
}

class PhFareCalculator {
  static const jeepney = FareRule(
    base: 14.0,
    baseKm: 4,
    perKm: 1.94,
    typicalKm: 10,
  );
  static const busOrdinary = FareRule(
    base: 18.0,
    baseKm: 5,
    perKm: 2.22,
    typicalKm: 10,
  );
  static const busAircon = FareRule(
    base: 18.0,
    baseKm: 5,
    perKm: 3.18,
    typicalKm: 15,
  );
  static const fxVan = FareRule(
    base: 40.0,
    baseKm: 5,
    perKm: 4.57,
    typicalKm: 15,
  );
  static const tricycle = FareRule(
    base: 16.0,
    baseKm: 2,
    perKm: 5.33,
    typicalKm: 5,
  );

  /// Bus rides longer than this are priced as aircon.
  static const busAirconAboveKm = 10.0;

  // LRT/MRT: ₱13 boarding + ₱2 per station (~500 m apart), kept within the
  // real ₱20–₱50 range of a single-line ride.
  static const _trainBoarding = 13.0;
  static const _trainPerStation = 2.0;
  static const trainMin = 20.0;
  static const trainMax = 50.0;

  static const ferryFlat = 50.0;

  /// Fare in pesos for riding [mode] over [distanceMeters]. [mode] is one of
  /// the app's mode names ('Jeepney', 'Bus', 'FX/Van', ...), any case.
  /// Unknown modes are priced as a jeepney.
  static double compute(String mode, double distanceMeters) {
    final km = distanceMeters / 1000.0;
    switch (mode.toLowerCase()) {
      case 'walk':
        return 0.0;
      case 'bus':
        return (km > busAirconAboveKm ? busAircon : busOrdinary).fareForKm(km);
      case 'fx/van':
        return fxVan.fareForKm(km);
      case 'tricycle':
        return tricycle.fareForKm(km);
      case 'train':
        final stations = (distanceMeters / 500).ceil().clamp(1, 20);
        return (_trainBoarding + (stations - 1) * _trainPerStation).clamp(
          trainMin,
          trainMax,
        );
      case 'ferry':
        return ferryFlat;
      default:
        return jeepney.fareForKm(km);
    }
  }

  static String format(double fare) =>
      fare == 0 ? 'Free' : '₱${fare.toStringAsFixed(0)}';

  static String formatRange(double fare) {
    if (fare == 0) return 'Free';
    return '₱${(fare * 0.9).round()}-₱${(fare * 1.1).round()}';
  }

  /// "₱14" or "₱1.94" — whole pesos drop the decimals.
  static String peso(double amount) =>
      amount == amount.roundToDouble()
          ? '₱${amount.toStringAsFixed(0)}'
          : '₱${amount.toStringAsFixed(2)}';
}
