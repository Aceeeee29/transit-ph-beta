import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserProfileBootstrapService {
  static Future<void> createUserProfile({
    required User user,
    required String email,
  }) async {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          _buildDefaultUserProfile(
            user: user,
            email: email,
          ),
        );
  }

  static Future<void> ensureUserProfileExists(User user) async {
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (userDoc.exists) return;

    await createUserProfile(
      user: user,
      email: user.email ?? '',
    );
  }

  static Map<String, dynamic> _buildDefaultUserProfile({
    required User user,
    required String email,
  }) {
    return {
      'uid': user.uid,
      'name': user.displayName ?? 'Anonymous',
      'email': email,
      'photoUrl': user.photoURL,
      'userCategory': null,
      'userTags': [],
      'role': 'user',
      'isBanned': false,
      'routesContributed': 0,
      'routesSearched': 0,
      'reportsSubmitted': 0,
      'totalDistance': 0.0,
      'co2Saved': 0.0,
      'mostActiveRegion': null,
      'streakDays': 0,
      'lastActiveDate': null,
      'createdAt': FieldValue.serverTimestamp(),
      'badges': [],
      'achievements': [],
      'followedRouteIds': [],
      'hasSeenTutorial': false,
    };
  }
}