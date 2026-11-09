import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../models/post.dart';
import '../models/user.dart';
import '../models/route.dart' as route_model;
import '../models/feedback.dart' as feedback_model;
import '../models/lockout.dart';
import 'lockout_service.dart';
import '../services/post_service.dart' show PostLifetime;
import '../services/route_service.dart';

class ModerationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final firebase_auth.FirebaseAuth _auth =
      firebase_auth.FirebaseAuth.instance;

  static ValueNotifier<List<Post>> postsNotifier = ValueNotifier([]);
  static ValueNotifier<List<User>> usersNotifier = ValueNotifier([]);
  static ValueNotifier<List<feedback_model.Feedback>> feedbacksNotifier =
      ValueNotifier([]);

  // New: pending routes notifier
  static ValueNotifier<List<route_model.Route>> pendingRoutesNotifier =
      ValueNotifier([]);

  static StreamSubscription<QuerySnapshot>? _postsSubscription;
  static StreamSubscription<QuerySnapshot>? _usersSubscription;
  static StreamSubscription<QuerySnapshot>? _feedbacksSubscription;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _roleSubscription;
  static String? _roleWatchUid;
  static bool _dataListenersRunning = false;
  static bool _initialized = false;
  static const int maxRestrictionDays = 7;

  /// Whether the signed-in user is a moderator or admin. Drives staff-only
  /// actions outside the moderator screen (like on feed posts).
  static final ValueNotifier<bool> isStaffNotifier = ValueNotifier(false);

  /// Whether the signed-in user is a superadmin. Only they can decide ban
  /// appeals. Moderators decide restriction appeals.
  static final ValueNotifier<bool> isSuperAdminNotifier = ValueNotifier(false);

  /// Initialize all real-time listeners
  static void init() {
    if (_initialized) return;
    _initialized = true;

    _auth.authStateChanges().listen(_onAuthUserChanged);

    // Also handle the current auth state immediately.
    _onAuthUserChanged(_auth.currentUser);
  }

  /// The whole-collection listeners below are for the moderator screen, and
  /// Firestore only lets staff read posts and feedbacks that way, so they run
  /// only while the signed-in user's profile has a moderator or admin role.
  /// Watching the profile means a promotion or demotion applies without an
  /// app restart. Regular users' feed loads through PostService instead.
  static void _onAuthUserChanged(firebase_auth.User? user) {
    if (user == null) {
      _roleSubscription?.cancel();
      _roleSubscription = null;
      _roleWatchUid = null;
      isStaffNotifier.value = false;
      isSuperAdminNotifier.value = false;
      _stopDataListeners(clearData: true);
      return;
    }
    if (user.uid == _roleWatchUid) return;

    _roleSubscription?.cancel();
    isStaffNotifier.value = false;
    _stopDataListeners(clearData: true);
    _roleWatchUid = user.uid;
    _roleSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (doc) {
            final role = doc.data()?['role'];
            final isStaff = _isStaffRole(role);
            isStaffNotifier.value = isStaff;
            // Same test as the Firestore rules' isSuperAdmin().
            isSuperAdminNotifier.value = role == 'superadmin';
            if (isStaff && !_dataListenersRunning) {
              _startDataListeners();
            } else if (!isStaff && _dataListenersRunning) {
              _stopDataListeners(clearData: true);
            }
          },
          onError: (error) {
            debugPrint('[ModerationService] Role watch failed: $error');
          },
        );
  }

  static bool _isStaffRole(Object? rawRole) {
    final role = (rawRole is String ? rawRole : '')
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    return role == 'moderator' || role == 'superadmin' || role == 'super_admin';
  }

  static void _startDataListeners() {
    _stopDataListeners(clearData: false);
    _dataListenersRunning = true;

    _postsSubscription = _firestore.collection('posts').snapshots().listen((
      snapshot,
    ) {
      final posts =
          snapshot.docs.map((doc) => Post.fromJson(doc.data())).toList();
      postsNotifier.value = posts;
    });

    _usersSubscription = _firestore.collection('users').snapshots().listen((
      snapshot,
    ) {
      final users =
          snapshot.docs.map((doc) => User.fromJson(doc.data())).toList();
      usersNotifier.value = users;
    });

    _feedbacksSubscription = _firestore
        .collection('feedbacks')
        .snapshots()
        .listen((snapshot) {
          final feedbacks =
              snapshot.docs
                  .map((doc) => feedback_model.Feedback.fromJson(doc.data()))
                  .toList();
          feedbacksNotifier.value = feedbacks;
        });

    // Routes moved to Supabase, which we don't listen to live, so the queue
    // loads here and refreshes after decisions and on pull-to-refresh.
    unawaited(refreshPendingRoutes());
  }

  /// Reloads the moderator queue. A failure keeps the current list, because an
  /// empty one would look like there's nothing left to review.
  static Future<void> refreshPendingRoutes() async {
    final uid = _roleWatchUid;
    try {
      final routes = await RouteService.getPendingRoutes();
      // They may have signed out while this was loading.
      if (uid == _roleWatchUid) pendingRoutesNotifier.value = routes;
    } catch (e) {
      debugPrint('[ModerationService] Queue refresh failed: $e');
    }
  }

  static void _stopDataListeners({required bool clearData}) {
    _dataListenersRunning = false;
    _postsSubscription?.cancel();
    _usersSubscription?.cancel();
    _feedbacksSubscription?.cancel();
    _postsSubscription = null;
    _usersSubscription = null;
    _feedbacksSubscription = null;

    if (clearData) {
      postsNotifier.value = [];
      usersNotifier.value = [];
      feedbacksNotifier.value = [];
      pendingRoutesNotifier.value = [];
    }
  }

  // Route moderation

  // A real failure reaches the screen, so the moderator knows it didn't save
  // and the route stays in the list. A decision someone else already made isn't
  // a failure. RouteService ignores it, and the refresh shows the new state.

  static Future<void> _afterDecision(String routeId) async {
    pendingRoutesNotifier.value =
        pendingRoutesNotifier.value.where((r) => r.id != routeId).toList();
    await refreshPendingRoutes();
  }

  static Future<void> approveRoute(String routeId) async {
    await RouteService.approveRoute(routeId);
    await _afterDecision(routeId);
  }

  static Future<void> rejectRoute(
    String routeId, {
    required List<String> reasonCodes,
    String? note,
  }) async {
    await RouteService.rejectRoute(
      routeId,
      reasonCodes: reasonCodes,
      note: note,
    );
    await _afterDecision(routeId);
  }

  // Post moderation

  static Future<void> approvePost(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'moderationStatus': ModerationStatus.approved.name,
        // Its time in the feed starts once it's approved.
        'expiresAt': PostLifetime.standard.expiresAtFromNow(),
      });
    } catch (_) {}
  }

  static Future<void> rejectPost(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'moderationStatus': ModerationStatus.rejected.name,
      });
    } catch (_) {}
  }

  static Future<void> dismissReportedPost(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'moderationStatus': ModerationStatus.approved.name,
      });

      final reportsSnap =
          await _firestore
              .collection('feedbacks')
              .where('targetId', isEqualTo: postId)
              .get();

      final batch = _firestore.batch();
      for (final doc in reportsSnap.docs) {
        final data = doc.data();
        if (data['type'] == feedback_model.FeedbackType.report.name &&
            data['targetType'] == feedback_model.FeedbackTargetType.post.name) {
          batch.delete(doc.reference);
        }
      }
      await batch.commit();

      postsNotifier.value = List.from(postsNotifier.value)..removeWhere(
        (p) => p.id == postId && p.moderationStatus == ModerationStatus.pending,
      );
      feedbacksNotifier.value =
          feedbacksNotifier.value
              .where(
                (f) =>
                    !(f.type == feedback_model.FeedbackType.report &&
                        f.targetType ==
                            feedback_model.FeedbackTargetType.post &&
                        f.targetId == postId),
              )
              .toList();
    } catch (_) {}
  }

  static Future<void> removePostPermanently(String postId) async {
    try {
      final reportsSnap =
          await _firestore
              .collection('feedbacks')
              .where('targetId', isEqualTo: postId)
              .get();

      final batch = _firestore.batch();
      batch.delete(_firestore.collection('posts').doc(postId));
      for (final doc in reportsSnap.docs) {
        final data = doc.data();
        if (data['type'] == feedback_model.FeedbackType.report.name &&
            data['targetType'] == feedback_model.FeedbackTargetType.post.name) {
          batch.delete(doc.reference);
        }
      }
      await batch.commit();

      postsNotifier.value =
          postsNotifier.value.where((p) => p.id != postId).toList();
      feedbacksNotifier.value =
          feedbacksNotifier.value
              .where(
                (f) =>
                    !(f.type == feedback_model.FeedbackType.report &&
                        f.targetType ==
                            feedback_model.FeedbackTargetType.post &&
                        f.targetId == postId),
              )
              .toList();
    } catch (_) {}
  }

  // User moderation

  /// Restricts [uid] for [days] and saves why, so the rider sees the
  /// reason and can appeal. Both writes go in one batch, so there's never
  /// a restriction without a reason or a reason without a restriction.
  /// Returns false when the save failed.
  static Future<bool> restrictUser(
    String uid, {
    required int days,
    required LockoutReason reason,
    String note = '',
  }) async {
    final sanitizedDays = days.clamp(1, maxRestrictionDays) as int;
    final restrictedUntil = DateTime.now().toUtc().add(
      Duration(days: sanitizedDays),
    );

    try {
      final batch = _firestore.batch();
      batch.update(_firestore.collection('users').doc(uid), {
        'isBanned': false,
        'status': 'restricted',
        'restrictedAt': FieldValue.serverTimestamp(),
        'restrictedUntil': Timestamp.fromDate(restrictedUntil),
      });
      batch.set(
        LockoutService.recordRef(uid),
        LockoutRecord.newRecord(
          action: 'restrict',
          reason: reason,
          note: note,
          byUid: _auth.currentUser?.uid ?? '',
          until: restrictedUntil,
        ),
      );
      await batch.commit();
      final index = usersNotifier.value.indexWhere((u) => u.uid == uid);
      if (index != -1) {
        final user = usersNotifier.value[index];
        user.isBanned = false;
        user.restrictedUntil = restrictedUntil.toLocal();
        usersNotifier.value = List<User>.from(usersNotifier.value);
      }
      return true;
    } catch (e) {
      debugPrint('[Moderation] restrict failed: $e');
      return false;
    }
  }

  /// Lifts a restriction (or a ban, for a superadmin). An appeal still
  /// waiting from this rider is closed as lifted, so it doesn't stay in
  /// the list after the matter is settled.
  static Future<bool> liftUserRestriction(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'isBanned': false,
        'status': 'active',
        'restrictedAt': FieldValue.delete(),
        'restrictedUntil': FieldValue.delete(),
      });
      final index = usersNotifier.value.indexWhere((u) => u.uid == uid);
      if (index != -1) {
        final user = usersNotifier.value[index];
        user.isBanned = false;
        user.restrictedUntil = null;
        usersNotifier.value = List<User>.from(usersNotifier.value);
      }
    } catch (e) {
      debugPrint('[Moderation] lift failed: $e');
      return false;
    }
    await LockoutService.closePendingAppeals(uid);
    return true;
  }

  // Feedback management

  static List<feedback_model.Feedback> getFeedbacks() {
    return feedbacksNotifier.value;
  }

  static Future<void> addFeedback(feedback_model.Feedback feedback) async {
    try {
      await _firestore
          .collection('feedbacks')
          .doc(feedback.id)
          .set(feedback.toJson());
    } catch (_) {}
  }

  static Future<void> saveFeedback(feedback_model.Feedback feedback) async {
    try {
      await _firestore
          .collection('feedbacks')
          .doc(feedback.id)
          .set(feedback.toJson());
    } catch (_) {
      rethrow;
    }
  }

  static Future<void> updateFeedbackStatus(
    String feedbackId,
    feedback_model.FeedbackStatus status,
  ) async {
    try {
      await _firestore.collection('feedbacks').doc(feedbackId).update({
        'status': status.name,
      });
      final index = feedbacksNotifier.value.indexWhere(
        (f) => f.id == feedbackId,
      );
      if (index != -1) {
        final updatedFeedback = feedbacksNotifier.value[index].copyWith(
          status: status,
        );
        feedbacksNotifier.value = List.from(feedbacksNotifier.value)
          ..[index] = updatedFeedback;
      }
    } catch (_) {}
  }

  static Future<void> deleteFeedback(String feedbackId) async {
    try {
      await _firestore.collection('feedbacks').doc(feedbackId).delete();
      feedbacksNotifier.value =
          feedbacksNotifier.value.where((f) => f.id != feedbackId).toList();
    } catch (_) {}
  }

  // Getters

  static List<Post> getPendingPosts() {
    return postsNotifier.value
        .where((p) => p.moderationStatus == ModerationStatus.pending)
        .toList();
  }

  static List<route_model.Route> getPendingRoutes() {
    return pendingRoutesNotifier.value;
  }

  static List<User> getUsers() {
    return usersNotifier.value;
  }

  static Post? getPost(String id) {
    try {
      return postsNotifier.value.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}
