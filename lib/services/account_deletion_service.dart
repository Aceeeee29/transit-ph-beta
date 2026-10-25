import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Thrown when signing in again (needed before deleting) didn't work.
class ReauthException implements Exception {
  final String message;
  const ReauthException(this.message);

  @override
  String toString() => message;
}

/// Settings → Delete account: removes the signed-in rider's posts,
/// comments, routes that aren't live yet, notifications, feedback and
/// profile, hands their approved routes over as "Former rider" (other
/// riders use them), then deletes the sign-in account itself.
///
/// Runs on the phone: the free Firebase plan has no server code. A user
/// may delete their own sign-in account, but only right after signing in,
/// hence [reauthenticate] first.
class AccountDeletionService {
  AccountDeletionService._();

  static const formerRiderName = 'Former rider';

  /// True while [deleteCurrentAccount] runs: the profile is removed just
  /// before the sign-in account, and AuthGate must not sign out in between.
  static bool inProgress = false;

  static bool get usesGoogle =>
      FirebaseAuth.instance.currentUser?.providerData.any(
        (p) => p.providerId == 'google.com',
      ) ??
      false;

  /// Signs in again so Firebase allows the deletion: the Google account
  /// picker, or the account's [password]. False when the rider cancels.
  static Future<bool> reauthenticate({String? password}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ReauthException('You are signed out.');
    try {
      final AuthCredential credential;
      if (usesGoogle) {
        final account = await GoogleSignIn().signIn();
        if (account == null) return false;
        final auth = await account.authentication;
        credential = GoogleAuthProvider.credential(
          accessToken: auth.accessToken,
          idToken: auth.idToken,
        );
      } else {
        if (password == null || password.isEmpty) return false;
        credential = EmailAuthProvider.credential(
          email: user.email ?? '',
          password: password,
        );
      }
      await user.reauthenticateWithCredential(credential);
      return true;
    } on FirebaseAuthException catch (e) {
      throw ReauthException(switch (e.code) {
        'wrong-password' || 'invalid-credential' => 'That password is wrong.',
        'user-mismatch' =>
          'That is a different Google account. Pick the one you use here.',
        'too-many-requests' => 'Too many tries. Wait a bit, then try again.',
        'network-request-failed' => 'No internet connection.',
        _ => 'Could not confirm it is you (${e.code}).',
      });
    }
  }

  /// Deletes everything listed above. Call [reauthenticate] first. A step
  /// that fails (e.g. older security rules) is logged and skipped so the
  /// rest still goes; the sign-in account is deleted last.
  static Future<void> deleteCurrentAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final db = FirebaseFirestore.instance;
    inProgress = true;
    try {
      await _step('posts', () => _deletePosts(db, uid));
      await _step('comments', () => _deleteComments(db, uid));
      await _step('routes', () => _releaseRoutes(db, uid));
      await _step(
        'notifications',
        () => _deleteWhere(db.collection('notifications'), 'userId', uid),
      );
      await _step(
        'feedback',
        () => _deleteWhere(db.collection('feedbacks'), 'userId', uid),
      );
      final profile = db.collection('users').doc(uid);
      for (final sub in const ['achievements', 'badges', 'routeHistory']) {
        await _step(sub, () => _deleteAll(profile.collection(sub)));
      }
      try {
        await profile.delete();
      } catch (e) {
        // Rules from before account deletion: empty it instead.
        debugPrint('[AccountDeletion] profile delete failed: $e');
        await _step('profile wipe', () => profile.update(_wipedProfile()));
      }
      await user.delete();
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}
    } finally {
      inProgress = false;
    }
  }

  /// The personal parts of a profile, emptied (what a closed account
  /// keeps is only its stats and role).
  static Map<String, dynamic> _wipedProfile() => {
    'name': 'Deleted rider',
    'email': FieldValue.delete(),
    'photoUrl': null,
    'userCategory': null,
    'userTags': <String>[],
    'recentSearches': <String>[],
    'followedRouteIds': <String>[],
    'bookmarkedPostIds': <String>[],
    'preferences': FieldValue.delete(),
  };

  static Future<void> _step(String name, Future<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      debugPrint('[AccountDeletion] $name failed: $e');
    }
  }

  static Future<void> _deleteAll(Query<Map<String, dynamic>> query) async {
    final snapshot = await query.get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  static Future<void> _deleteWhere(
    CollectionReference<Map<String, dynamic>> collection,
    String field,
    String uid,
  ) => _deleteAll(collection.where(field, isEqualTo: uid));

  /// Their posts, each with its comments (a post's comments aren't removed
  /// with it).
  static Future<void> _deletePosts(FirebaseFirestore db, String uid) async {
    final posts =
        await db.collection('posts').where('userId', isEqualTo: uid).get();
    for (final post in posts.docs) {
      await _step(
        'comments of ${post.id}',
        () => _deleteAll(post.reference.collection('comments')),
      );
      await post.reference.delete();
    }
  }

  /// Their comments on other riders' posts.
  static Future<void> _deleteComments(FirebaseFirestore db, String uid) =>
      _deleteAll(
        db.collectionGroup('comments').where('userId', isEqualTo: uid),
      );

  /// Routes not live yet go; approved ones stay for everyone, credited to
  /// "Former rider".
  static Future<void> _releaseRoutes(FirebaseFirestore db, String uid) async {
    final routes =
        await db
            .collection('routes')
            .where('contributorId', isEqualTo: uid)
            .get();
    for (final route in routes.docs) {
      final approved = route.data()['approvalStatus'] == 'approved';
      if (!approved) {
        try {
          await route.reference.delete();
          continue;
        } catch (e) {
          debugPrint('[AccountDeletion] route ${route.id} delete failed: $e');
        }
      }
      await _step(
        'route ${route.id}',
        () => route.reference.update({
          'contributorId': null,
          'contributorName': formerRiderName,
          'contributorClosed': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );
    }
  }
}
