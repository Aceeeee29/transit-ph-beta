import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'route_metrics_service.dart';

class SettingsService {
  static const String _prefsCacheKey = 'user_settings_preferences';
  static const String _preferencesField = 'preferences';

  static const Map<String, dynamic> _defaultPreferences = {
    'routeApprovalUpdates': true,
    'newDiscussions': true,
    'weeklyDigest': false,
    'distanceUnit': 'Miles',
    'showEmailInProfile': false,
  };

  static String? _getCurrentUserUid() {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    return user?.uid;
  }

  static Future<Map<String, dynamic>> loadPreferences() async {
    final uid = _getCurrentUserUid();

    if (uid != null) {
      try {
        final docSnapshot =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();

        final data = docSnapshot.data();
        final preferences = data?[_preferencesField];
        if (preferences is Map<String, dynamic>) {
          final merged = {
            ..._defaultPreferences,
            ...preferences,
          };
          RouteMetricsService.setDistanceUnit(
            merged['distanceUnit'] as String?,
          );
          return merged;
        }
      } catch (e) {
        // Fall back to local cache if Firestore is unavailable.
        debugPrint('Error loading user preferences from Firestore: $e');
      }
    }

    return _loadCachedPreferences();
  }

  static Future<void> savePreferences(Map<String, dynamic> preferences) async {
    final sanitized = {
      ..._defaultPreferences,
      ...preferences,
    };
    RouteMetricsService.setDistanceUnit(sanitized['distanceUnit'] as String?);

    final uid = _getCurrentUserUid();

    if (uid != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          _preferencesField: sanitized,
        }, SetOptions(merge: true));

        await _cachePreferences(sanitized);
        return;
      } catch (e) {
        debugPrint('Error saving user preferences to Firestore: $e');
      }
    }

    await _cachePreferences(sanitized);
  }

  static Future<Map<String, dynamic>> _loadCachedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsCacheKey);

    if (cached == null) {
      final defaults = {..._defaultPreferences};
      RouteMetricsService.setDistanceUnit(defaults['distanceUnit'] as String?);
      return defaults;
    }

    try {
      final decoded = jsonDecode(cached);
      if (decoded is Map<String, dynamic>) {
        final merged = {
          ..._defaultPreferences,
          ...decoded,
        };
        RouteMetricsService.setDistanceUnit(merged['distanceUnit'] as String?);
        return merged;
      }
    } catch (_) {
      // Ignore invalid cache and return defaults.
    }

    final defaults = {..._defaultPreferences};
    RouteMetricsService.setDistanceUnit(defaults['distanceUnit'] as String?);
    return defaults;
  }

  static Future<void> _cachePreferences(Map<String, dynamic> preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsCacheKey, jsonEncode(preferences));
  }
}
