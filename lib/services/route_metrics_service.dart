import 'package:latlong2/latlong.dart' show LatLng, Distance, LengthUnit;
import 'dart:math' as math;

class RouteMetricsService {
  static const String kilometersUnit = 'Kilometers';
  static const String milesUnit = 'Miles';

  static String _currentDistanceUnit = milesUnit;

  static const double _walkingSpeedKmh = 5.0; // Average walking speed in km/h
  static const double _jeepneySpeedKmh = 20.0; // Average jeepney speed in km/h
  static const double _busSpeedKmh = 25.0; // Average bus speed in km/h
  static const double _trainSpeedKmh = 40.0; // Average train speed in km/h
  static const double _tricycleSpeedKmh =
      15.0; // Average tricycle speed in km/h
  static const double _vanSpeedKmh = 30.0; // Average FX/Van speed in km/h
  static const double _ferrySpeedKmh = 20.0; // Average ferry speed in km/h

  static String get currentDistanceUnit => _currentDistanceUnit;

  static void setDistanceUnit(String? distanceUnit) {
    if (distanceUnit == null) return;
    if (distanceUnit == milesUnit || distanceUnit == kilometersUnit) {
      _currentDistanceUnit = distanceUnit;
    }
  }

  /// Calculate the total distance of a route in kilometers
  static double calculateRouteDistance(List<LatLng> points) {
    if (points.isEmpty) return 0;
    if (points.length < 2) {
      // If only one point, return 0 but don't error
      return 0;
    }

    double totalDistance = 0;
    final Distance distanceCalculator = Distance();

    for (int i = 0; i < points.length - 1; i++) {
      final point1 = points[i];
      final point2 = points[i + 1];
      final dist = distanceCalculator.as(
        LengthUnit.Kilometer,
        point1,
        point2,
      );
      totalDistance += dist;
        }

    return totalDistance;
  }

  /// Calculate the estimated time of arrival (ETA) in minutes
  static int calculateEta(
    List<LatLng> points,
    List<String> modes,
    List<int> stepBoundaries,
  ) {
    if (points.length < 2 || modes.isEmpty) return 0;

    double totalMinutes = 0;
    final Distance distanceCalculator = const Distance();

    // Calculate ETA for each step
    for (int i = 0; i < modes.length; i++) {
      final startIdx =
          (i == 0)
              ? 0
              : (i - 1 < stepBoundaries.length ? stepBoundaries[i - 1] : 0);
      final endIdx =
          (i < stepBoundaries.length) ? stepBoundaries[i] : points.length - 1;

      if (endIdx > startIdx) {
        double stepDistance = 0;
        for (int j = startIdx; j < endIdx && j + 1 < points.length; j++) {
          stepDistance += distanceCalculator.as(
            LengthUnit.Kilometer,
            points[j],
            points[j + 1],
          );
                }

        // Convert distance to time based on mode of transport
        final speedKmh = _getSpeedForMode(modes[i]);
        final hours = stepDistance / speedKmh;
        totalMinutes += hours * 60;
      }
    }

    // Add waiting time for transfers (2 minutes per transfer)
    if (modes.length > 1) {
      totalMinutes += (modes.length - 1) * 2;
    }

    return totalMinutes.ceil();
  }

  /// Get the average speed for a given mode of transport
  static double _getSpeedForMode(String mode) {
    switch (mode.toLowerCase()) {
      case 'walk':
        return _walkingSpeedKmh;
      case 'jeepney':
        return _jeepneySpeedKmh;
      case 'bus':
        return _busSpeedKmh;
      case 'train':
        return _trainSpeedKmh;
      case 'tricycle':
        return _tricycleSpeedKmh;
      case 'fx/van':
        return _vanSpeedKmh;
      case 'ferry':
        return _ferrySpeedKmh;
      default:
        return _walkingSpeedKmh;
    }
  }

  /// Format distance for display
  static String formatDistance(double distanceKm) {
    return formatDistanceForUnit(distanceKm, distanceUnit: _currentDistanceUnit);
  }

  /// Format distance for display using a selected unit preference.
  static String formatDistanceForUnit(
    double distanceKm, {
    String? distanceUnit,
  }) {
    final selectedUnit = distanceUnit ?? _currentDistanceUnit;
    final useMiles = selectedUnit == milesUnit;
    final convertedDistance = useMiles ? distanceKm * 0.621371 : distanceKm;
    final shortUnit = useMiles ? 'mi' : 'km';

    if (convertedDistance < 1) {
      if (!useMiles) {
        final meters = (convertedDistance * 1000).round();
        return '$meters m';
      }

      final milesRounded = (convertedDistance * 100).round() / 100;
      return '$milesRounded mi';
    }

    final roundedValue = (convertedDistance * 10).round() / 10;
    return '$roundedValue $shortUnit';
  }

  /// Format a distance value represented in meters for a selected unit.
  static String formatDistanceMetersForUnit(
    double distanceMeters, {
    String? distanceUnit,
  }) {
    return formatDistanceForUnit(
      distanceMeters / 1000,
      distanceUnit: distanceUnit,
    );
  }

  static String formatDistanceMeters(double distanceMeters) {
    return formatDistanceMetersForUnit(
      distanceMeters,
      distanceUnit: _currentDistanceUnit,
    );
  }

  static double? parseDistanceToKm(String? text) {
    if (text == null || text.trim().isEmpty) return null;

    final match = RegExp(
      r'^\s*(\d+(?:\.\d+)?)\s*(km|kilometers?|m|meters?|mi|miles?|ft|feet)?\s*$',
      caseSensitive: false,
    ).firstMatch(text.trim());

    if (match == null) return null;

    final value = double.tryParse(match.group(1)!);
    if (value == null) return null;

    final unit = (match.group(2) ?? 'km').toLowerCase();
    if (unit == 'km' || unit == 'kilometer' || unit == 'kilometers') {
      return value;
    }
    if (unit == 'm' || unit == 'meter' || unit == 'meters') {
      return value / 1000;
    }
    if (unit == 'mi' || unit == 'mile' || unit == 'miles') {
      return value * 1.60934;
    }
    if (unit == 'ft' || unit == 'feet') {
      return value * 0.0003048;
    }

    return null;
  }

  /// Format ETA for display
  static String formatEta(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '$hours h ${mins > 0 ? '$mins min' : ''}';
    }
  }

  /// Calculate the fare estimate based on distance and mode
  static String calculateFareEstimate(
    List<LatLng> points,
    List<String> modes,
    List<int> stepBoundaries,
  ) {
    if (points.length < 2 || modes.isEmpty) return 'PHP 0';

    double totalFare = 0;
    final Distance distanceCalculator = const Distance();

    // Calculate fare for each step
    for (int i = 0; i < modes.length; i++) {
      final startIdx =
          (i == 0)
              ? 0
              : (i - 1 < stepBoundaries.length ? stepBoundaries[i - 1] : 0);
      final endIdx =
          (i < stepBoundaries.length) ? stepBoundaries[i] : points.length - 1;

      if (endIdx > startIdx) {
        double stepDistance = 0;
        for (int j = startIdx; j < endIdx && j + 1 < points.length; j++) {
          stepDistance += distanceCalculator.as(
            LengthUnit.Kilometer,
            points[j],
            points[j + 1],
          );
                }

        // Calculate fare based on mode and distance
        totalFare += _calculateFareForMode(modes[i], stepDistance);
      }
    }

    // Round to nearest peso
    final roundedFare = totalFare.round();
    return 'PHP $roundedFare';
  }

  /// Calculate fare for a specific mode and distance (public)
  static double calculateFareForMode(String mode, double distanceKm) {
    return _calculateFareForMode(mode, distanceKm);
  }

  /// Calculate fare for a specific mode and distance
  static double _calculateFareForMode(String mode, double distanceKm) {
    switch (mode.toLowerCase()) {
      case 'walk':
        return 0; // Walking is free
      case 'jeepney':
        // Base fare + additional per km
        return 13.0 + math.max(0, distanceKm - 4) * 1.5;
      case 'bus':
        // Base fare + additional per km
        return 15.0 + distanceKm * 2.0;
      case 'train':
        // Base fare + additional per station (approx 1.5km per station)
        final stations = math.max(1, (distanceKm / 1.5).ceil());
        return 15.0 + (stations - 1) * 5.0;
      case 'tricycle':
        // Base fare + additional per km
        return 20.0 + distanceKm * 5.0;
      case 'fx/van':
        // Base fare + additional per km
        return 25.0 + distanceKm * 2.5;
      case 'ferry':
        // Base fare + additional per km
        return 0.0 + distanceKm * 3.0;
      default:
        return 0;
    }
  }

  /// Calculate CO2 emissions saved by using this route instead of driving
  /// Returns CO2 in kg
  static double calculateCo2Saved(
    List<LatLng> points,
    List<String> modes,
    List<int> stepBoundaries,
  ) {
    if (points.length < 2 || modes.isEmpty) return 0.0;

    double totalCo2Saved = 0;
    final Distance distanceCalculator = const Distance();

    // Calculate CO2 for each step
    for (int i = 0; i < modes.length; i++) {
      final startIdx =
          (i == 0)
              ? 0
              : (i - 1 < stepBoundaries.length ? stepBoundaries[i - 1] : 0);
      final endIdx =
          (i < stepBoundaries.length) ? stepBoundaries[i] : points.length - 1;

      if (endIdx > startIdx) {
        double stepDistance = 0;
        for (int j = startIdx; j < endIdx && j + 1 < points.length; j++) {
          stepDistance += distanceCalculator.as(
            LengthUnit.Kilometer,
            points[j],
            points[j + 1],
          );
                }

        // CO2 emissions per km for different modes (kg CO2 per km)
        // Average car emissions: ~0.2 kg CO2 per km
        // Public transport modes have lower emissions
        final carCo2PerKm = 0.2; // kg CO2 per km for average car
        final modeCo2PerKm = _getCo2PerKmForMode(modes[i]);

        // CO2 saved = (car emissions - mode emissions) * distance
        final co2Saved = (carCo2PerKm - modeCo2PerKm) * stepDistance;
        if (co2Saved > 0) {
          totalCo2Saved += co2Saved;
        }
      }
    }

    return totalCo2Saved;
  }

  /// Get CO2 emissions per km for a specific mode of transport
  static double _getCo2PerKmForMode(String mode) {
    switch (mode.toLowerCase()) {
      case 'walk':
        return 0.0; // No emissions
      case 'jeepney':
        return 0.08; // Lower emissions due to shared transport
      case 'bus':
        return 0.06; // Public transport
      case 'train':
        return 0.04; // Electric train
      case 'tricycle':
        return 0.15; // Motorcycle
      case 'fx/van':
        return 0.12; // Shared van
      case 'ferry':
        return 0.05; // Boat
      default:
        return 0.1; // Default
    }
  }
}
