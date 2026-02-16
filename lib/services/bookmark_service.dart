import 'package:shared_preferences/shared_preferences.dart';

class BookmarkService {
  static const String _bookmarksKey = 'bookmarked_routes';

  /// Add a route to bookmarks
  static Future<void> addBookmark(String routeId) async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarks = prefs.getStringList(_bookmarksKey) ?? [];
    
    if (!bookmarks.contains(routeId)) {
      bookmarks.add(routeId);
      await prefs.setStringList(_bookmarksKey, bookmarks);
    }
  }

  /// Remove a route from bookmarks
  static Future<void> removeBookmark(String routeId) async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarks = prefs.getStringList(_bookmarksKey) ?? [];
    
    bookmarks.remove(routeId);
    await prefs.setStringList(_bookmarksKey, bookmarks);
  }

  /// Check if a route is bookmarked
  static Future<bool> isBookmarked(String routeId) async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarks = prefs.getStringList(_bookmarksKey) ?? [];
    return bookmarks.contains(routeId);
  }

  /// Get all bookmarked route IDs
  static Future<List<String>> getBookmarkedRouteIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_bookmarksKey) ?? [];
  }

  /// Toggle bookmark status
  static Future<bool> toggleBookmark(String routeId) async {
    final isCurrentlyBookmarked = await isBookmarked(routeId);
    if (isCurrentlyBookmarked) {
      await removeBookmark(routeId);
      return false;
    } else {
      await addBookmark(routeId);
      return true;
    }
  }

  /// Clear all bookmarks
  static Future<void> clearBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bookmarksKey);
  }
}
