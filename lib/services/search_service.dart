import 'package:shared_preferences/shared_preferences.dart';

class SearchService {
  static const String _recentSearchesKey = 'recent_searches';
  static const int _maxRecentSearches = 10;

  /// Save a search query to recent searches
  static Future<void> addRecentSearch(String query) async {
    if (query.trim().isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    final recentSearches = prefs.getStringList(_recentSearchesKey) ?? [];
    
    // Remove if already exists (to move it to top)
    recentSearches.remove(query.trim());
    
    // Add to beginning
    recentSearches.insert(0, query.trim());
    
    // Limit to max recent searches
    if (recentSearches.length > _maxRecentSearches) {
      recentSearches.removeRange(_maxRecentSearches, recentSearches.length);
    }
    
    await prefs.setStringList(_recentSearchesKey, recentSearches);
  }

  /// Get recent searches
  static Future<List<String>> getRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentSearchesKey) ?? [];
  }

  /// Clear all recent searches
  static Future<void> clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSearchesKey);
  }

  /// Remove a single recent search
  static Future<void> removeRecentSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final recentSearches = prefs.getStringList(_recentSearchesKey) ?? [];
    recentSearches.remove(query);
    await prefs.setStringList(_recentSearchesKey, recentSearches);
  }
}
