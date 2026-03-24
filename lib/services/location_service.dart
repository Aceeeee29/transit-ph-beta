import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  /// Check if location services are enabled and permissions are granted
  static Future<bool> checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Get the current GPS position
  static Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await checkLocationPermission();
      if (!hasPermission) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      return null;
    }
  }

  /// Reverse geocode coordinates to get address
  static Future<String?> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        // Build a readable address
        List<String> addressParts = [];
        
        if (place.street != null && place.street!.isNotEmpty) {
          addressParts.add(place.street!);
        }
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          addressParts.add(place.subLocality!);
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          addressParts.add(place.locality!);
        }
        if (place.administrativeArea != null && 
            place.administrativeArea!.isNotEmpty) {
          addressParts.add(place.administrativeArea!);
        }
        
        return addressParts.isNotEmpty 
            ? addressParts.join(', ') 
            : null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get current location as address
  static Future<String?> getCurrentLocationAddress() async {
    final position = await getCurrentPosition();
    if (position == null) {
      return null;
    }
    return await getAddressFromCoordinates(position.latitude, position.longitude);
  }

  /// Forward geocode a location name into coordinates
  static Future<Location?> getCoordinatesFromAddress(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    try {
      final matches = await locationFromAddress(trimmed);
      if (matches.isEmpty) {
        return null;
      }
      return matches.first;
    } catch (e) {
      return null;
    }
  }

  /// Check if it's rush hour (7-9 AM or 5-7 PM)
  static bool isRushHour() {
    final now = DateTime.now();
    final hour = now.hour;
    return (hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 19);
  }

  /// Get time of day description
  static String getTimeOfDayDescription() {
    final now = DateTime.now();
    final hour = now.hour;
    
    if (hour >= 5 && hour < 12) {
      return 'morning';
    } else if (hour >= 12 && hour < 14) {
      return 'noon';
    } else if (hour >= 14 && hour < 17) {
      return 'afternoon';
    } else if (hour >= 17 && hour < 20) {
      return 'evening';
    } else {
      return 'night';
    }
  }
}
