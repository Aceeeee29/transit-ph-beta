import 'package:latlong2/latlong.dart';

class DistanceService {
  static const Distance _distance = Distance();

  static double calculateKm(double lat1, double lng1, double lat2, double lng2) {
    return _distance.as(
      LengthUnit.Kilometer,
      LatLng(lat1, lng1),
      LatLng(lat2, lng2),
    );
  }

  static double calculateM(double lat1, double lng1, double lat2, double lng2) {
    return _distance.as(
      LengthUnit.Meter,
      LatLng(lat1, lng1),
      LatLng(lat2, lng2),
    );
  }

  static String formatDistance(double km) {
    if (km < 1) {
      final m = (km * 1000).round();
      return '$m m';
    }
    return '${km.toStringAsFixed(1)} km';
  }
}
