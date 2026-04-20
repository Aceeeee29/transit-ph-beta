import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart' as app_user;
import '../models/achievement.dart';
import '../models/badge.dart';
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
          return app_user.User.fromJson(data);
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
      } catch (_) {
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

        return;
      } catch (_) {
        // If update fails (document might not exist), try to set it
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .set(user.toJson());

          return;
        } catch (_) {
        }
      }
    }

    // Fallback to SharedPreferences if Firebase Auth is not available
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  static ({List<Achievement> achievements, bool changed})
  _normalizeAchievements(List<Achievement> achievements) {
    bool changed = false;
    final normalized =
        achievements.map((achievement) {
          final cappedProgress = _clampProgress(
            achievement.progress,
            achievement.maxProgress,
          );
          final shouldBeUnlocked =
              achievement.isUnlocked || cappedProgress >= achievement.maxProgress;
          final normalizedProgress =
              shouldBeUnlocked ? achievement.maxProgress : cappedProgress;

          final needsUpdate =
              achievement.progress != normalizedProgress ||
              achievement.isUnlocked != shouldBeUnlocked ||
              (shouldBeUnlocked && achievement.unlockedAt == null);

          if (!needsUpdate) {
            return achievement;
          }

          changed = true;
          return achievement.copyWith(
            progress: normalizedProgress,
            isUnlocked: shouldBeUnlocked,
            unlockedAt: shouldBeUnlocked
                ? (achievement.unlockedAt ?? Timestamp.now())
                : achievement.unlockedAt,
          );
        }).toList();

    return (achievements: normalized, changed: changed);
  }

  static Future<List<Achievement>> loadAchievements() async {
    final uid = _getCurrentUserUid();
    if (uid != null) {
      try {
        final querySnapshot =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('achievements')
                .get();
        if (querySnapshot.docs.isNotEmpty) {
          final loaded = querySnapshot.docs
              .map((doc) => Achievement.fromJson(doc.data()))
              .toList();
          final normalized = _normalizeAchievements(loaded);
          if (normalized.changed) {
            await saveAchievements(normalized.achievements);
          }
          return normalized.achievements;
        } else {
          // Seed predefined achievements
          final predefined = getPredefinedAchievements();
          await saveAchievements(predefined);
          return predefined;
        }
      } catch (_) {
      }
    }
    // Fallback to SharedPreferences if not logged in or error
    final prefs = await SharedPreferences.getInstance();
    final achievementsJson = prefs.getString(_achievementsKey);
    if (achievementsJson != null) {
      final List<dynamic> decoded = jsonDecode(achievementsJson);
      final loaded = decoded.map((e) => Achievement.fromJson(e)).toList();
      final normalized = _normalizeAchievements(loaded);
      if (normalized.changed) {
        await prefs.setString(
          _achievementsKey,
          jsonEncode(normalized.achievements.map((a) => a.toJson()).toList()),
        );
      }
      return normalized.achievements;
    }
    return getPredefinedAchievements();
  }

  static Future<void> saveAchievements(List<Achievement> achievements) async {
    final uid = _getCurrentUserUid();
    if (uid != null) {
      try {
        final batch = FirebaseFirestore.instance.batch();
        for (final achievement in achievements) {
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('achievements')
              .doc(achievement.id);
          batch.set(docRef, achievement.toJson());
        }
        await batch.commit();
      } catch (_) {
      }
    }
  }

  static Future<List<Badge>> loadBadges() async {
    final uid = _getCurrentUserUid();
    if (uid != null) {
      try {
        final querySnapshot =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('badges')
                .get();
        if (querySnapshot.docs.isNotEmpty) {
          return querySnapshot.docs
              .map((doc) => Badge.fromJson(doc.data()))
              .toList();
        }
      } catch (_) {
      }
    }
    // Fallback to SharedPreferences if not logged in or error
    final prefs = await SharedPreferences.getInstance();
    final badgesJson = prefs.getString(_badgesKey);
    if (badgesJson != null) {
      final List<dynamic> decoded = jsonDecode(badgesJson);
      return decoded.map((e) => Badge.fromJson(e)).toList();
    }
    return getPredefinedBadges();
  }

  static Future<void> saveBadges(List<Badge> badges) async {
    final uid = _getCurrentUserUid();
    if (uid != null) {
      try {
        final batch = FirebaseFirestore.instance.batch();
        for (final badge in badges) {
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('badges')
              .doc(badge.id);
          batch.set(docRef, badge.toJson());
        }
        await batch.commit();
      } catch (_) {
      }
    }
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

      // Update user stats (streak is handled separately on app open)
      user.totalDistance = totalDistance;
      user.co2Saved = totalCo2Saved;
      user.mostActiveRegion = mostActiveRegion;

      await saveUser(user);
    } catch (_) {
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

  /// Calculate streak days based on lastActiveDate
  static int _calculateStreakDays(DateTime? lastActiveDate, int currentStreak) {
    if (lastActiveDate == null) return 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastActive = DateTime(
      lastActiveDate.year,
      lastActiveDate.month,
      lastActiveDate.day,
    );

    final difference = today.difference(lastActive).inDays;

    if (difference == 0) {
      // Active today, keep current streak
      return currentStreak;
    } else if (difference == 1) {
      // Active yesterday, increment streak
      return currentStreak + 1;
    } else {
      // Gap in activity, reset to 1
      return 1;
    }
  }

  static int _clampProgress(int value, int maxProgress) {
    if (value < 0) return 0;
    if (value > maxProgress) return maxProgress;
    return value;
  }

  /// Update streak on app open
  static Future<void> updateStreakOnAppOpen() async {
    final uid = _getCurrentUserUid();
    if (uid == null) return;

    try {
      final user = await loadUser();
      final now = DateTime.now();
      final newStreakDays = _calculateStreakDays(
        user.lastActiveDate,
        user.streakDays,
      );

      user.lastActiveDate = now;
      user.streakDays = newStreakDays;

      await saveUser(user);

      // Update daily_rider progress
      final achievements = await loadAchievements();
      final dailyRiderIndex = achievements.indexWhere(
        (a) => a.id == 'daily_rider',
      );
      if (dailyRiderIndex != -1) {
        final dailyRider = achievements[dailyRiderIndex];
        final nextProgress =
            dailyRider.isUnlocked
                ? dailyRider.maxProgress
                : _clampProgress(user.streakDays, dailyRider.maxProgress);

        if (dailyRider.progress != nextProgress) {
          achievements[dailyRiderIndex] = dailyRider.copyWith(
            progress: nextProgress,
          );
        }

        // Check for unlock
        if (!dailyRider.isUnlocked && nextProgress >= dailyRider.maxProgress) {
          achievements[dailyRiderIndex] = achievements[dailyRiderIndex]
              .copyWith(isUnlocked: true, unlockedAt: Timestamp.now());
          if (!user.achievements.contains('daily_rider')) {
            user.achievements.add('daily_rider');
            await saveUser(user);
          }
        } else if (dailyRider.isUnlocked &&
            !user.achievements.contains('daily_rider')) {
          user.achievements.add('daily_rider');
          await saveUser(user);
        }

        await saveAchievements(achievements);
      }
    } catch (_) {
    }
  }

  // Favorites functionality removed

  static Future<List<String>> checkAchievements(
    app_user.User user,
    String action,
  ) async {
    final achievements = await loadAchievements();
    final badges = await loadBadges();
    List<String> unlockedItems = [];
    bool achievementsUpdated = false;
    bool badgesUpdated = false;
    bool userUpdated = false;

    void incrementAchievementProgress(String achievementId) {
      final index = achievements.indexWhere((a) => a.id == achievementId);
      if (index == -1) return;

      final achievement = achievements[index];
      final cappedCurrent = _clampProgress(
        achievement.progress,
        achievement.maxProgress,
      );

      if (achievement.isUnlocked) {
        if (cappedCurrent != achievement.maxProgress) {
          achievements[index] = achievement.copyWith(
            progress: achievement.maxProgress,
          );
          achievementsUpdated = true;
        }
        return;
      }

      final nextProgress = _clampProgress(
        cappedCurrent + 1,
        achievement.maxProgress,
      );
      if (nextProgress != achievement.progress) {
        achievements[index] = achievement.copyWith(progress: nextProgress);
        achievementsUpdated = true;
      }
    }

    void unlockBadgeIfQualified(
      String badgeId,
      bool shouldUnlock,
      String badgeName,
    ) {
      final badgeIndex = badges.indexWhere((b) => b.id == badgeId);
      if (badgeIndex == -1) return;

      final badge = badges[badgeIndex];

      if (badge.isUnlocked) {
        if (!user.badges.contains(badgeId)) {
          user.badges.add(badgeId);
          userUpdated = true;
        }
        return;
      }

      if (!shouldUnlock) return;

      badges[badgeIndex] = badge.copyWith(
        isUnlocked: true,
        earnedAt: Timestamp.now(),
      );
      if (!user.badges.contains(badgeId)) {
        user.badges.add(badgeId);
        userUpdated = true;
      }
      unlockedItems.add('Badge: $badgeName');
      badgesUpdated = true;
    }

    // Increment progress based on action
    if (action == 'searched') {
      incrementAchievementProgress('rookie_commuter');
      incrementAchievementProgress('metro_master');
      unlockBadgeIfQualified('explorer', user.routesSearched >= 50, 'Explorer');
    } else if (action == 'contributed') {
      incrementAchievementProgress('route_pioneer');
      incrementAchievementProgress('community_hero');
      unlockBadgeIfQualified(
        'contributor',
        user.routesContributed >= 10,
        'Contributor',
      );
    }

    // Check for unlocks
    for (int i = 0; i < achievements.length; i++) {
      final achievement = achievements[i];
      if (achievement.isUnlocked) {
        if (achievement.progress != achievement.maxProgress) {
          achievements[i] = achievement.copyWith(progress: achievement.maxProgress);
          achievementsUpdated = true;
        }
        if (!user.achievements.contains(achievement.id)) {
          user.achievements.add(achievement.id);
          userUpdated = true;
        }
        continue;
      }

      final cappedProgress = _clampProgress(
        achievement.progress,
        achievement.maxProgress,
      );
      if (cappedProgress != achievement.progress) {
        achievements[i] = achievement.copyWith(progress: cappedProgress);
        achievementsUpdated = true;
      }

      final currentAchievement = achievements[i];
      if (currentAchievement.progress >= currentAchievement.maxProgress) {
        achievements[i] = currentAchievement.copyWith(
          isUnlocked: true,
          unlockedAt: Timestamp.now(),
        );
        if (!user.achievements.contains(currentAchievement.id)) {
          user.achievements.add(currentAchievement.id);
          userUpdated = true;
        }
        unlockedItems.add('Achievement: ${currentAchievement.name}');
        achievementsUpdated = true;
      }
    }

    if (achievementsUpdated) {
      await saveAchievements(achievements);
    }
    if (badgesUpdated) {
      await saveBadges(badges);
    }
    if (achievementsUpdated || badgesUpdated || userUpdated) {
      await saveUser(user);
    }

    return unlockedItems;
  }
}
