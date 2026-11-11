// =============================================================================
// PHILIPPINE FARE MATRIX
//
// The single source for every fare TransitPH computes or displays: route
// generation, the route map, the contribute screen, the Fare Matrix dialog
// and the search help sheet all read from here. Change fares in this file only.
//
// Jeepney (traditional) and Metro Manila buses, ordinary and aircon, use the
// LTFRB fare guides effective September 28, 2026. FX/UV and tricycle are still
// our own estimates: LTFRB gives UV Express only a per-km rate, and tricycle
// fares are set by each city. LRT/MRT fares are unchanged.
// =============================================================================
import '../models/ors_route_result.dart';

/// [base] covers the first [baseKm] kilometres. Every km after that adds
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
    return '${PhFareCalculator.peso(base)} – ${PhFareCalculator.peso(high)}+';
  }
}

class PhFareCalculator {
  /// Students, PWD and seniors pay 20% less.
  static const studentDiscount = 0.8;

  /// A ride's discounted fare: 20% off, rounded up to the next peso, as
  /// drivers charge it (the ₱14 jeepney minimum is ₱12, not ₱11.20).
  static double discountedFare(double fare) =>
      fare <= 0 ? fare : (fare * studentDiscount).ceilToDouble();

  /// The 20% discount is given on jeepneys and buses only (EDSA Carousel
  /// included). Tricycles, trains, FX/vans and ferries charge everyone the
  /// same.
  static bool givesDiscount(String mode) {
    final m = mode.toLowerCase();
    return m.contains('jeep') || m.contains('bus') || m.contains('carousel');
  }

  /// A ride's fare on [mode], discounted when [discount] and [mode] gives
  /// the discount.
  static double rideFare(double fare, String mode, {required bool discount}) =>
      discount && givesDiscount(mode) ? discountedFare(fare) : fare;

  /// A generated trip's fare, with the discount on its jeepney and bus
  /// rides when [discount].
  static double tripFare(OrsRouteResult trip, {required bool discount}) {
    final base = trip.baseFarePhp;
    if (!discount) return base;
    var off = 0.0;
    for (final step in trip.steps) {
      if (step.estimatedFare <= 0) continue;
      off +=
          step.estimatedFare -
          rideFare(step.estimatedFare, step.suggestedMode, discount: true);
    }
    return base - off < 0 ? 0 : base - off;
  }

  /// A trip's estimated [fare] as riders see it, like "₱14–18": a range,
  /// since the real fare depends on where you board and get off.
  static String tripEstimateLabel(double fare) {
    if (!fare.isFinite) return '₱—';
    if (fare <= 0) return 'Free';
    return '₱${(fare * 0.9).round()}–${(fare * 1.15).round()}';
  }

  // These numbers are the offline fallback. FareRuleService replaces them with
  // the current rates from the server when it can reach it.
  static FareRule jeepney = const FareRule(
    base: 14.0,
    baseKm: 4,
    perKm: 2.00,
    typicalKm: 10,
  );
  static FareRule busOrdinary = const FareRule(
    base: 15.0,
    baseKm: 5,
    perKm: 2.49,
    typicalKm: 10,
  );
  static FareRule busAircon = const FareRule(
    base: 18.0,
    baseKm: 5,
    perKm: 2.98,
    typicalKm: 15,
  );
  static FareRule fxVan = const FareRule(
    base: 40.0,
    baseKm: 5,
    perKm: 4.57,
    typicalKm: 15,
  );
  static FareRule tricycle = const FareRule(
    base: 16.0,
    baseKm: 2,
    perKm: 5.33,
    typicalKm: 5,
  );

  /// Uses rates from the server's `fare_rules` table. [rows] is newest first,
  /// so the first row seen for a mode wins. Unknown modes and rows with bad
  /// numbers are skipped, which keeps the rate that was already in use.
  static void applyRules(List<Map<String, dynamic>> rows) {
    FareRule? replaced(String mode, FareRule current) {
      for (final row in rows) {
        if (row['mode'] != mode) continue;
        final base = (row['base'] as num?)?.toDouble();
        final baseKm = (row['base_km'] as num?)?.toDouble();
        final perKm = (row['per_km'] as num?)?.toDouble();
        if (base == null || baseKm == null || perKm == null || base <= 0) {
          return null;
        }
        return FareRule(
          base: base,
          baseKm: baseKm,
          perKm: perKm,
          typicalKm: current.typicalKm,
        );
      }
      return null;
    }

    jeepney = replaced('jeepney', jeepney) ?? jeepney;
    busOrdinary = replaced('bus', busOrdinary) ?? busOrdinary;
    busAircon = replaced('bus_aircon', busAircon) ?? busAircon;
    fxVan = replaced('fx_van', fxVan) ?? fxVan;
    tricycle = replaced('tricycle', tricycle) ?? tricycle;
  }

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
      case 'boat':
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

  /// "₱14" or "₱2.98". Whole pesos drop the decimals.
  static String peso(double amount) =>
      amount == amount.roundToDouble()
          ? '₱${amount.toStringAsFixed(0)}'
          : '₱${amount.toStringAsFixed(2)}';
}
