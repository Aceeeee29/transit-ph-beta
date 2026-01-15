import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/achievement.dart';
import '../models/badge.dart';

class GamificationService {
  static const String _userKey = 'user_data';
  static const String _achievementsKey = 'achievements_data';
  static const String _badgesKey = 'badges_data';

  static Future<User> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      return User.fromJson(jsonDecode(userJson));
    }
    return User(name: 'User', email: 'user@example.com');
  }

  static Future<void> saveUser(User user) async {
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
    return predefinedAchievements;
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
    return predefinedBadges;
  }

  static Future<void> saveBadges(List<Badge> badges) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = badges.map((e) => e.toJson()).toList();
    await prefs.setString(_badgesKey, jsonEncode(encoded));
  }

  static Future<List<String>> incrementRoutesSearched(User user) async {
    user.routesSearched++;
    await saveUser(user);
    return await checkAchievements(user, 'searched');
  }

  static Future<List<String>> incrementRoutesContributed(User user) async {
    user.routesContributed++;
    await saveUser(user);
    return await checkAchievements(user, 'contributed');
  }

  static Future<List<String>> incrementReportsSubmitted(User user) async {
    user.reportsSubmitted++;
    await saveUser(user);
    return await checkAchievements(user, 'reported');
  }

  // Favorites functionality removed

  static Future<List<String>> checkAchievements(
    User user,
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
        user.achievements.add('route_pioneer');
        unlockedItems.add('Achievement: Route Pioneer');
        updated = true;
      }

      // Check Contributor Badge
      final contributorBadge = badges.firstWhere((b) => b.id == 'contributor');
      if (!contributorBadge.isUnlocked && user.routesContributed >= 10) {
        badges[badges.indexOf(contributorBadge)] = contributorBadge.copyWith(
          isUnlocked: true,
        );
        user.badges.add('contributor');
        unlockedItems.add('Badge: Contributor');
        updated = true;
      }
    }
    // Add other actions if needed

    if (updated) {
      await saveUser(user);
      await saveAchievements(achievements);
      await saveBadges(badges);
    }

    return unlockedItems;
  }
}
