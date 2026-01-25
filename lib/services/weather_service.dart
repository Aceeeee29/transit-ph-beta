import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geocoding/geocoding.dart';

class WeatherData {
  final String temp;
  final String condition;
  final String precipitation;
  final String humidity;
  final bool isStorm;
  final double? lat;
  final double? lng;
  final String address;

  WeatherData({
    required this.temp,
    required this.condition,
    required this.precipitation,
    required this.humidity,
    required this.isStorm,
    this.lat,
    this.lng,
    required this.address,
  });
}

class WeatherService {
  static Future<WeatherData?> getCurrentWeatherAndLocation() async {
    try {
      // Request location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied forever');
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final lat = position.latitude;
      final lng = position.longitude;

      // Get address from coordinates
      String address = '';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          // Prioritize full name if available
          if (place.name != null && place.name!.isNotEmpty) {
            address = place.name!;
          } else {
            // Build from available parts
            List<String> parts = [];
            if (place.street != null && place.street!.isNotEmpty) {
              parts.add(place.street!);
            }
            if (place.locality != null && place.locality!.isNotEmpty) {
              parts.add(place.locality!);
            }
            if (place.country != null && place.country!.isNotEmpty) {
              parts.add(place.country!);
            }
            address = parts.join(', ');
          }
        }
        if (address.isEmpty) {
          address = 'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}';
        }
      } catch (e) {
        address = 'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}';
      }

      // Fetch weather from OpenMeteo
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng&current_weather=true&hourly=precipitation,relative_humidity_2m&timezone=Asia/Manila',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final currentWeather = data['current_weather'];
        final hourly = data['hourly'];

        final temp = '${currentWeather['temperature']}°C';
        final code = currentWeather['weathercode'];
        final condition = _getWeatherDescription(code);
        final precipitation = hourly != null && hourly['precipitation'] != null
            ? '${hourly['precipitation'][0] ?? 0} mm'
            : '0 mm';
        final humidity = hourly != null && hourly['relative_humidity_2m'] != null
            ? '${hourly['relative_humidity_2m'][0] ?? 0}%'
            : '0%';
        final isStorm = code >= 95;

        return WeatherData(
          temp: temp,
          condition: condition,
          precipitation: precipitation,
          humidity: humidity,
          isStorm: isStorm,
          lat: lat,
          lng: lng,
          address: address,
        );
      } else {
        throw Exception('Failed to load weather');
      }
    } catch (e) {
      rethrow;
    }
  }

  static String _getWeatherDescription(int code) {
    switch (code) {
      case 0:
        return 'Clear sky';
      case 1:
      case 2:
      case 3:
        return 'Mainly clear';
      case 45:
      case 48:
        return 'Fog';
      case 51:
      case 53:
      case 55:
        return 'Drizzle';
      case 61:
      case 63:
      case 65:
        return 'Rain';
      case 71:
      case 73:
      case 75:
        return 'Snow';
      case 80:
      case 81:
      case 82:
        return 'Showers';
      case 95:
      case 96:
      case 99:
        return 'Thunderstorm';
      default:
        return 'Unknown';
    }
  }
}
