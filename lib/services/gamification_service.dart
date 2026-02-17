import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart' as app_user;
import '../models/achievement.dart';
import '../models/badge.dart';
import '../models/route.dart' as route_model;
import 'route_service.dart';
import 'route_metrics_service.dart';

class GamificationService {
  static const String _userKey = 'user_data';
  static const String _achievementsKey = 'achievements_data';
  static const String _badgesKey = 'badges_data';

  /// Get the current user's UID from Firebase Auth
  static String? _getCurrentUserUid() {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    return user?.uid;
  }

  /// Load user data from Firestore
  static Future<app_user.User> loadUser() async {
    final uid = _getCurrentUserUid();

    if (uid != null) {
      try {
        final docSnapshot =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();

        if (docSnapshot.exists) {
          final data = docSnapshot.data() as Map<String, dynamic>;
          return app_user.User(
            name: data['name'] ?? 'User',
            email: data['email'] ?? '',
            userCategory: data['userCategory'],
            badges: List<String>.from(data['badges'] ?? []),
            achievements: List<String>.from(data['achievements'] ?? []),
            routesContributed: data['routesContributed'] ?? 0,
            routesSearched: data['routesSearched'] ?? 0,
            reportsSubmitted: data['reportsSubmitted'] ?? 0,
            role: app_user.UserRole.values.firstWhere(
              (e) => e.name == data['role'],
              orElse: () => app_user.UserRole.user,
            ),
            isBanned: data['isBanned'] ?? false,
          );
        } else {
          // Create a new user document in Firestore if it doesn't exist
          final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
          final newUser = app_user.User(
            name:
                firebaseUser?.displayName ??
                firebaseUser?.email?.split('@').first ??
                'User',
            email: firebaseUser?.email ?? '',
          );

          // Save to Firestore
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .set(newUser.toJson());

          return newUser;
        }
      } catch (e) {
        print('Error loading user from Firestore: $e');
      }
    }

    // Fallback to SharedPreferences if Firebase Auth is not available
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      return app_user.User.fromJson(jsonDecode(userJson));
    }
    return app_user.User(name: 'User', email: 'user@example.com');
  }

  /// Save user data to Firestore
  static Future<void> saveUser(app_user.User user) async {
    final uid = _getCurrentUserUid();

    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update(user.toJson());

        // Also save to SharedPreferences as backup
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userKey, jsonEncode(user.toJson()));
        return;
      } catch (e) {
        print('Error saving user to Firestore: $e');
        // If update fails (document might not exist), try to set it
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .set(user.toJson());

          // Also save to SharedPreferences as backup
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_userKey, jsonEncode(user.toJson()));
          return;
        } catch (e2) {
          print('Error creating user document in Firestore: $e2');
        }
      }
    }

    // Fallback to SharedPreferences if Firebase Auth is not available
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  static Future<List<Achievement>> loadAchievements() async {
    final prefs = await SharedPreferences.getInstance();
    final achievementsJson = prefs.getString(_achievementsKey);
    if (achievementsJson != null) {
      final List<dynamic> decoded = jsonDecode(achievementsJson);
      return decoded.map((e) => Achievement.fromJson(e)).toList();
    }
    return getPredefinedAchievements();
  }

  static Future<void> saveAchievements(List<Achievement> achievements) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = achievements.map((e) => e.toJson()).toList();
    await prefs.setString(_achievementsKey, jsonEncode(encoded));
  }

  static Future<List<Badge>> loadBadges() async {
    final prefs = await SharedPreferences.getInstance();
    final badgesJson = prefs.getString(_badgesKey);
    if (badgesJson != null) {
      final List<dynamic> decoded = jsonDecode(badgesJson);
      return decoded.map((e) => Badge.fromJson(e)).toList();
    }
    return getPredefinedBadges();
  }

  static Future<void> saveBadges(List<Badge> badges) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = badges.map((e) => e.toJson()).toList();
    await prefs.setString(_badgesKey, jsonEncode(encoded));
  }

  static Future<List<String>> incrementRoutesSearched(
    app_user.User user,
  ) async {
    user.routesSearched++;
    await saveUser(user);
    return await checkAchievements(user, 'searched');
  }

  static Future<List<String>> incrementRoutesContributed(
    app_user.User user,
  ) async {
    user.routesContributed++;
    await saveUser(user);
    return await checkAchievements(user, 'contributed');
  }

  static Future<List<String>> incrementReportsSubmitted(
    app_user.User user,
  ) async {
    user.reportsSubmitted++;
    await saveUser(user);
    return await checkAchievements(user, 'reported');
  }

  /// Recalculate user stats from contributed routes
  static Future<void> recalculateUserStats(app_user.User user) async {
    final uid = _getCurrentUserUid();
    if (uid == null) return;

    try {
      final routes = await RouteService.getRoutesByUser(uid);

      double totalDistance = 0.0;
      double totalCo2Saved = 0.0;
      Map<String, int> regionCounts = {};
      String? mostActiveRegion;

      for (final route in routes) {
        // Calculate distance
        final distance = RouteMetricsService.calculateRouteDistance(
          route.pathPoints,
        );
        totalDistance += distance;

        // Calculate CO2 saved
        final modes = route.steps.map((s) => s.mode).toList();
        final co2Saved = RouteMetricsService.calculateCo2Saved(
          route.pathPoints,
          modes,
          route.stepBoundaries,
        );
        totalCo2Saved += co2Saved;

        // Count regions (simplified: use start location as region)
        final region = _extractRegionFromLocation(route.startLocation);
        if (region != null) {
          regionCounts[region] = (regionCounts[region] ?? 0) + 1;
        }
      }

      // Find most active region
      if (regionCounts.isNotEmpty) {
        mostActiveRegion =
            regionCounts.entries
                .reduce((a, b) => a.value > b.value ? a : b)
                .key;
      }

      // Calculate streak days (simplified: assume current streak based on recent activity)
      // This would need more complex logic with activity timestamps
      final streakDays = _calculateStreakDays(routes);

      // Update user stats
      user.totalDistance = totalDistance;
      user.co2Saved = totalCo2Saved;
      user.mostActiveRegion = mostActiveRegion;
      user.streakDays = streakDays;

      await saveUser(user);
    } catch (e) {
      print('Error recalculating user stats: $e');
    }
  }

  /// Extract region from location string (simplified implementation)
  static String? _extractRegionFromLocation(String location) {
    // This is a simplified implementation
    // In a real app, you'd use geocoding or region mapping
    final regions = [
      'NCR',
      'CALABARZON',
      'Central Luzon',
      'Ilocos',
      'Cagayan Valley',
      'Bicol',
      'Western Visayas',
      'Central Visayas',
      'Eastern Visayas',
      'Zamboanga',
      'Northern Mindanao',
      'Davao',
      'SOCCSKSARGEN',
      'Caraga',
    ];

    for (final region in regions) {
      if (location.toLowerCase().contains(region.toLowerCase())) {
        return region;
      }
    }
    return null;
  }

  /// Calculate streak days (simplified implementation)
  static int _calculateStreakDays(List<route_model.Route> routes) {
    // This is a placeholder - in a real implementation,
    // you'd track daily activity timestamps
    // For now, return a simple calculation based on route count
    if (routes.length >= 7) return 7;
    if (routes.length >= 3) return 3;
    return routes.length;
  }

  // Favorites functionality removed

  static Future<List<String>> checkAchievements(
    app_user.User user,
    String action,
  ) async {
    final achievements = await loadAchievements();
    final badges = await loadBadges();
    List<String> unlockedItems = [];
    bool updated = false;

    if (action == 'searched') {
      // Check Rookie Commuter
      final rookieAchievement = achievements.firstWhere(
        (a) => a.id == 'rookie_commuter',
      );
      if (!rookieAchievement.isUnlocked && user.routesSearched >= 1) {
        achievements[achievements.indexOf(
          rookieAchievement,
        )] = rookieAchievement.copyWith(isUnlocked: true);
        user.achievements.add('rookie_commuter');
        unlockedItems.add('Achievement: Rookie Commuter');
        updated = true;
      }

      // Check Metro Master
      final masterAchievement = achievements.firstWhere(
        (a) => a.id == 'metro_master',
      );
      if (!masterAchievement.isUnlocked && user.routesSearched >= 100) {
        achievements[achievements.indexOf(
          masterAchievement,
        )] = masterAchievement.copyWith(isUnlocked: true);
        user.achievements.add('metro_master');
        unlockedItems.add('Achievement: Metro Master');
        updated = true;
      }

      // Check Explorer Badge
      final explorerBadge = badges.firstWhere((b) => b.id == 'explorer');
      if (!explorerBadge.isUnlocked && user.routesSearched >= 50) {
        badges[badges.indexOf(explorerBadge)] = explorerBadge.copyWith(
          isUnlocked: true,
        );
        user.badges.add('explorer');
        unlockedItems.add('Badge: Explorer');
        updated = true;
      }
    } else if (action == 'contributed') {
      // Check Route Pioneer
      final pioneerAchievement = achievements.firstWhere(
        (a) => a.id == 'route_pioneer',
      );
      if (!pioneerAchievement.isUnlocked && user.routesContributed >= 10) {
        achievements[achievements.indexOf(
          pioneerAchievement,
        )] = pioneerAchievement.copyWith(isUnlocked: true);
        if (!user.achievements.contains('route_pioneer')) {
          user.achievements.add('route_pioneer');
        }
        unlockedItems.add('Achievement: Route Pioneer');
        updated = true;
      }

      // Check Contributor Badge
      final contributorBadge = badges.firstWhere((b) => b.id == 'contributor');
      if (!contributorBadge.isUnlocked && user.routesContributed >= 10) {
        badges[badges.indexOf(contributorBadge)] = contributorBadge.copyWith(
          isUnlocked: true,
        );
        if (!user.badges.contains('contributor')) {
          user.badges.add('contributor');
        }
        unlockedItems.add('Badge: Contributor');
        updated = true;
      }
    } else if (action == 'reported') {
      // Check Daily Rider (assuming it's for reports submitted, e.g., 7 reports)
      final dailyRiderAchievement = achievements.firstWhere(
        (a) => a.id == 'daily_rider',
      );
      if (!dailyRiderAchievement.isUnlocked && user.reportsSubmitted >= 7) {
        achievements[achievements.indexOf(
          dailyRiderAchievement,
        )] = dailyRiderAchievement.copyWith(isUnlocked: true);
        if (!user.achievements.contains('daily_rider')) {
          user.achievements.add('daily_rider');
        }
        unlockedItems.add('Achievement: Daily Rider');
        updated = true;
      }
    }

    if (updated) {
      await saveUser(user);
      await saveAchievements(achievements);
      await saveBadges(badges);
    }

    return unlockedItems;
  }
}
