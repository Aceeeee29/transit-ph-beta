import 'dart:async';

import 'package:flutter/foundation.dart';
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

  static final _startupAsk = Completer<void>();

  /// Done once the launch-time prompt below has been answered (or wasn't
  /// needed). Things that load on their own at startup, like the weather,
  /// wait for it instead of asking too: Android allows one permission
  /// request at a time and fails the other, so two at once can mean no
  /// prompt and no weather.
  static Future<void> get startupPermissionSettled =>
      kIsWeb ? Future.value() : _startupAsk.future;

  /// Shows the OS location prompt if the user hasn't answered it yet.
  /// Deliberately silent after a permanent denial so the app doesn't nag on
  /// every launch; features explain how to re-enable it when they need it.
  static Future<void> requestPermissionIfUndecided() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } catch (_) {
    } finally {
      if (!_startupAsk.isCompleted) _startupAsk.complete();
    }
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
      final placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      ).timeout(const Duration(seconds: 6));
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

        return addressParts.isNotEmpty ? addressParts.join(', ') : null;
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
    return await getAddressFromCoordinates(
      position.latitude,
      position.longitude,
    );
  }

  /// Forward geocode a location name into coordinates
  static Future<Location?> getCoordinatesFromAddress(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    try {
      final matches = await locationFromAddress(
        trimmed,
      ).timeout(const Duration(seconds: 6));
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
