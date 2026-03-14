import 'gamification_service.dart';

class SearchService {
  static const String _recentSearchesKey = 'recent_searches';
  static const int _maxRecentSearches = 10;

  /// Save a search query to recent searches
  static Future<void> addRecentSearch(String query) async {
    if (query.trim().isEmpty) return;

    try {
      final user = await GamificationService.loadUser();
      final recentSearches = List<String>.from(user.recentSearches);

      // Remove if already exists (to move it to top)
      recentSearches.remove(query.trim());

      // Add to beginning
      recentSearches.insert(0, query.trim());

      // Limit to max recent searches
      if (recentSearches.length > _maxRecentSearches) {
        recentSearches.removeRange(_maxRecentSearches, recentSearches.length);
      }

      user.recentSearches = recentSearches;
      await GamificationService.saveUser(user);
    } catch (e) {
      print('Error saving recent search: $e');
    }
  }

  /// Get recent searches
  static Future<List<String>> getRecentSearches() async {
    try {
      final user = await GamificationService.loadUser();
      return List<String>.from(user.recentSearches);
    } catch (e) {
      print('Error loading recent searches: $e');
      return [];
    }
  }

  /// Clear all recent searches
  static Future<void> clearRecentSearches() async {
    try {
      final user = await GamificationService.loadUser();
      user.recentSearches = [];
      await GamificationService.saveUser(user);
    } catch (e) {
      print('Error clearing recent searches: $e');
    }
  }

  /// Remove a single recent search
  static Future<void> removeRecentSearch(String query) async {
    try {
      final user = await GamificationService.loadUser();
      user.recentSearches.remove(query);
      await GamificationService.saveUser(user);
    } catch (e) {
      print('Error removing recent search: $e');
    }
  }
}
