import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BookmarkService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Add a route to followed routes
  static Future<void> addBookmark(String routeId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _firestore.collection('users').doc(uid).update({
      'followedRouteIds': FieldValue.arrayUnion([routeId]),
    });
  }

  /// Remove a route from followed routes
  static Future<void> removeBookmark(String routeId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _firestore.collection('users').doc(uid).update({
      'followedRouteIds': FieldValue.arrayRemove([routeId]),
    });
  }

  /// Check if a route is followed
  static Future<bool> isBookmarked(String routeId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return false;

    final data = doc.data()!;
    final followed = List<String>.from(data['followedRouteIds'] ?? []);
    return followed.contains(routeId);
  }

  /// Get all followed route IDs
  static Future<List<String>> getBookmarkedRouteIds() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return [];

    final data = doc.data()!;
    return List<String>.from(data['followedRouteIds'] ?? []);
  }

  /// Toggle follow status for a route
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

  /// Clear all followed routes
  static Future<void> clearBookmarks() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _firestore.collection('users').doc(uid).update({
      'followedRouteIds': [],
    });
  }

}
