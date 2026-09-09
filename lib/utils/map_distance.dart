import 'package:latlong2/latlong.dart';

/// Great-circle (Haversine) distance in kilometers between two coordinates.
double kmBetween(LatLng a, LatLng b) {
  return const Distance().as(LengthUnit.Kilometer, a, b);
}

/// Human-readable distance label, e.g. `500 m`, `1.2 km`, `3.5 km`.
String formatDistanceKm(double km) {
  if (km < 1.0) {
    final meters = (km * 1000).round();
    return '$meters m';
  }
  return '${km.toStringAsFixed(1)} km';
}