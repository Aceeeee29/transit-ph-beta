import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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

  /// Goes up each time a prompt ends with location allowed, so things that
  /// load on their own, like the weather, can load without another tap.
  static final accessGrants = ValueNotifier<int>(0);

  static void noteGranted(LocationPermission permission) {
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      accessGrants.value++;
    }
  }

  /// Location is on and allowed; never shows a prompt.
  static Future<bool> hasAccess() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      return false;
    }
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
        noteGranted(await Geolocator.requestPermission());
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

      return await fixAllowingSettingsDialog(
        const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      return null;
    }
  }

  /// [Geolocator.getCurrentPosition], made once more when its time limit ran
  /// out while the app was off screen.
  ///
  /// With Google's "Location Accuracy" setting off, a fix first shows
  /// Google's dialog to turn it on. The time limit keeps running while the
  /// dialog is up, and once it runs out the request is cancelled, so tapping
  /// "Turn on" afterwards turns location on with nothing waiting for it.
  static Future<Position> fixAllowingSettingsDialog(
    LocationSettings settings,
  ) async {
    var leftScreen = false;
    final listener = AppLifecycleListener(onInactive: () => leftScreen = true);
    try {
      return await Geolocator.getCurrentPosition(locationSettings: settings);
    } on TimeoutException {
      if (!leftScreen && _isOnScreen) rethrow;
      await _untilOnScreen();
      if (!await Geolocator.isLocationServiceEnabled()) rethrow;
      return await Geolocator.getCurrentPosition(locationSettings: settings);
    } finally {
      listener.dispose();
    }
  }

  static bool get _isOnScreen =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  static Future<void> _untilOnScreen() {
    if (_isOnScreen) return Future.value();
    final resumed = Completer<void>();
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(
      onResume: () {
        listener.dispose();
        resumed.complete();
      },
    );
    return resumed.future;
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

  /// Forward geocode a location name into coordinates in the Philippines:
  /// the phone's geocoder searches the whole world ("253 Galicia Obando"
  /// came back in Galicia, Spain), so places elsewhere are skipped, and the
  /// name is tried again with ", Philippines" when nothing here matched.
  static Future<Location?> getCoordinatesFromAddress(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    bool inPhilippines(Location l) =>
        l.latitude >= 4.5 &&
        l.latitude <= 21.5 &&
        l.longitude >= 116.0 &&
        l.longitude <= 127.0;

    for (final attempt in [trimmed, '$trimmed, Philippines']) {
      try {
        final matches = await locationFromAddress(
          attempt,
        ).timeout(const Duration(seconds: 6));
        for (final match in matches) {
          if (inPhilippines(match)) return match;
        }
      } catch (e) {
        debugPrint('[Geocoding] Phone geocoder error for "$attempt": $e');
      }
    }
    return null;
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
