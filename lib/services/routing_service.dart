import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import '../config.dart';

class RoutingService {
  static String _getProfileForMode(String mode) {
    switch (mode.toLowerCase()) {
      case 'walk':
        return 'foot-walking';
      case 'jeepney':
      case 'bus':
      case 'fx/van':
        return 'driving-car'; // Approximation for road vehicles
      case 'train':
        return 'driving-car'; // No train profile, fallback
      case 'tricycle':
        return 'cycling-regular'; // Approximation
      case 'ferry':
        return 'driving-car'; // No ferry profile, fallback
      default:
        return 'driving-car';
    }
  }

  static Future<List<LatLng>> getRoute(LatLng start, LatLng end, String mode) async {
    final profile = _getProfileForMode(mode);
    final url = Uri.parse(
      'https://api.openrouteservice.org/v2/directions/$profile?api_key=${Config.openRouteServiceApiKey}&start=${start.longitude},${start.latitude}&end=${end.longitude},${end.latitude}',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coordinates = data['features'][0]['geometry']['coordinates'] as List;
        return coordinates.map((coord) => LatLng(coord[1], coord[0])).toList();
      } else {
        throw Exception('Failed to fetch route: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }
}
