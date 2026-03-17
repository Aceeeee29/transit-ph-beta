import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../models/post.dart';
import '../models/notification.dart';
import '../models/user.dart';
import '../models/route.dart' as route_model;
import '../models/feedback.dart' as feedback_model;
import '../services/notifications_service.dart';

class ModerationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final firebase_auth.FirebaseAuth _auth =
      firebase_auth.FirebaseAuth.instance;

  static Future<String?> _resolveNotificationRecipientId(
    String? contributorId,
  ) async {
    final raw = contributorId?.trim();
    if (raw == null || raw.isEmpty) return null;

    // Already a UID — return directly
    if (!raw.contains('@')) return raw;

    // Check current user FIRST so self-approval always resolves correctly,
    // even when the moderator exists in the Firestore users collection.
    final currentUser = _auth.currentUser;
    if (currentUser != null &&
        currentUser.email?.toLowerCase() == raw.toLowerCase()) {
      return currentUser.uid;
    }

    // Fall back to Firestore lookup for other contributors stored by email
    try {
      final snap = await _firestore
          .collection('users')
          .where('email', isEqualTo: raw)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final uidFromField = (data['uid'] as String?)?.trim();
        if (uidFromField != null && uidFromField.isNotEmpty) {
          return uidFromField;
        }
        return snap.docs.first.id;
      }
    } catch (e) {
      print('Error resolving contributor email to uid ($raw): $e');
    }

    return null;
  }

  static ValueNotifier<List<Post>> postsNotifier = ValueNotifier([]);
  static ValueNotifier<List<User>> usersNotifier = ValueNotifier([]);
  static ValueNotifier<List<feedback_model.Feedback>> feedbacksNotifier =
      ValueNotifier([]);

  // ── New: pending routes notifier ──────────────────────────────────────────
  static ValueNotifier<List<route_model.Route>> pendingRoutesNotifier =
      ValueNotifier([]);

  static StreamSubscription<QuerySnapshot>? _postsSubscription;
  static StreamSubscription<QuerySnapshot>? _usersSubscription;
  static StreamSubscription<QuerySnapshot>? _feedbacksSubscription;
  static StreamSubscription<QuerySnapshot>? _routesSubscription;
  static bool _initialized = false;

  /// Initialize all real-time listeners
  static void init() {
    if (_initialized) return;
    _initialized = true;

    _auth.authStateChanges().listen((user) {
      if (user == null) {
        _stopDataListeners(clearData: true);
        return;
      }
      _startDataListeners();
    });

    // Also handle the current auth state immediately.
    if (_auth.currentUser != null) {
      _startDataListeners();
    } else {
      _stopDataListeners(clearData: true);
    }
  }

  static void _startDataListeners() {
    _stopDataListeners(clearData: false);

    _postsSubscription =
        _firestore.collection('posts').snapshots().listen((snapshot) {
      final posts =
          snapshot.docs.map((doc) => Post.fromJson(doc.data())).toList();
      postsNotifier.value = posts;
    });

    _usersSubscription =
        _firestore.collection('users').snapshots().listen((snapshot) {
      final users =
          snapshot.docs.map((doc) => User.fromJson(doc.data())).toList();
      usersNotifier.value = users;
    });

    _feedbacksSubscription =
        _firestore.collection('feedbacks').snapshots().listen((snapshot) {
      final feedbacks = snapshot.docs
          .map((doc) => feedback_model.Feedback.fromJson(doc.data()))
          .toList();
      feedbacksNotifier.value = feedbacks;
    });

    // ── Listen only to pending routes ──────────────────────────────────────
    // Note: no orderBy here — combining where() + orderBy() on different
    // fields requires a Firestore composite index which may not exist yet.
    // We sort client-side instead.
    _routesSubscription = _firestore
        .collection('routes')
        .where(
          'approvalStatus',
          isEqualTo: route_model.RouteApprovalStatus.pending.name,
        )
        .snapshots()
        .listen(
      (snapshot) {
        final routes = snapshot.docs
            .map((doc) => route_model.Route.fromJson(doc.data()))
            .toList();
        // Sort newest first client-side
        routes.sort((a, b) {
          final aTime = a.createdAt ?? DateTime(2000);
          final bTime = b.createdAt ?? DateTime(2000);
          return bTime.compareTo(aTime);
        });
        pendingRoutesNotifier.value = routes;
      },
      onError: (error) {
        print('Error listening to pending routes: $error');
      },
    );
  }

  static void _stopDataListeners({required bool clearData}) {
    _postsSubscription?.cancel();
    _usersSubscription?.cancel();
    _feedbacksSubscription?.cancel();
    _routesSubscription?.cancel();
    _postsSubscription = null;
    _usersSubscription = null;
    _feedbacksSubscription = null;
    _routesSubscription = null;

    if (clearData) {
      postsNotifier.value = [];
      usersNotifier.value = [];
      feedbacksNotifier.value = [];
      pendingRoutesNotifier.value = [];
    }
  }

  // ── Route moderation ───────────────────────────────────────────────────────

  static Future<void> approveRoute(String routeId) async {
    try {
      String? contributorId;
      String routeTitle = 'your submitted route';

      final routeSnapshot =
          await _firestore.collection('routes').doc(routeId).get();
      if (routeSnapshot.exists) {
        final routeData = routeSnapshot.data();
        contributorId = (routeData?['contributorId'] as String?)?.trim();
        final start = routeData?['startLocation'] as String?;
        final end = routeData?['endLocation'] as String?;
        if (start != null && end != null) {
          routeTitle = '$start to $end';
        }
      }

      await _firestore.collection('routes').doc(routeId).update({
        'approvalStatus': route_model.RouteApprovalStatus.approved.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final recipientId = await _resolveNotificationRecipientId(contributorId);
      if (recipientId != null && recipientId.isNotEmpty) {
        // Notification delivery should not block route approval completion.
        try {
          await NotificationsService.addNotification(
            NotificationModel(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              userId: recipientId,
              type: 'route_approved',
              timestamp: DateTime.now(),
              message:
                  'Your submitted route ($routeTitle) was approved and is now live.',
            ),
          );
        } catch (e) {
          print('Error creating approval notification for route $routeId: $e');
        }
      }

      // Remove from local pending list immediately
      pendingRoutesNotifier.value = pendingRoutesNotifier.value
          .where((r) => r.id != routeId)
          .toList();
      print('Approved route $routeId');
    } catch (e) {
      print('Error approving route $routeId: $e');
    }
  }

  static Future<void> rejectRoute(String routeId) async {
    try {
      await _firestore.collection('routes').doc(routeId).update({
        'approvalStatus': route_model.RouteApprovalStatus.rejected.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Remove from local pending list immediately
      pendingRoutesNotifier.value = pendingRoutesNotifier.value
          .where((r) => r.id != routeId)
          .toList();
      print('Rejected route $routeId');
    } catch (e) {
      print('Error rejecting route $routeId: $e');
    }
  }

  // ── Post moderation ────────────────────────────────────────────────────────

  static Future<void> approvePost(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'moderationStatus': ModerationStatus.approved.name,
      });
      print('Approved post $postId');
    } catch (e) {
      print('Error approving post $postId: $e');
    }
  }

  static Future<void> rejectPost(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'moderationStatus': ModerationStatus.rejected.name,
      });
      print('Rejected post $postId');
    } catch (e) {
      print('Error rejecting post $postId: $e');
    }
  }

  // ── User moderation ────────────────────────────────────────────────────────

  static Future<void> banUser(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({'isBanned': true});
      final user = usersNotifier.value.firstWhere((u) => u.uid == uid);
      user.isBanned = true;
      print('Banned user $uid');
    } catch (e) {
      print('Error banning user $uid: $e');
    }
  }

  static Future<void> unbanUser(String uid) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .update({'isBanned': false});
      final user = usersNotifier.value.firstWhere((u) => u.uid == uid);
      user.isBanned = false;
      print('Unbanned user $uid');
    } catch (e) {
      print('Error unbanning user $uid: $e');
    }
  }

  // ── Feedback management ────────────────────────────────────────────────────

  static List<feedback_model.Feedback> getFeedbacks() {
    return feedbacksNotifier.value;
  }

  static Future<void> addFeedback(feedback_model.Feedback feedback) async {
    try {
      await _firestore
          .collection('feedbacks')
          .doc(feedback.id)
          .set(feedback.toJson());
      feedbacksNotifier.value = [...feedbacksNotifier.value, feedback];
    } catch (e) {
      print('Error adding feedback ${feedback.id}: $e');
    }
  }

  static Future<void> saveFeedback(feedback_model.Feedback feedback) async {
    try {
      await _firestore
          .collection('feedbacks')
          .doc(feedback.id)
          .set(feedback.toJson());
    } catch (e) {
      print('Error saving feedback ${feedback.id}: $e');
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
      final index =
          feedbacksNotifier.value.indexWhere((f) => f.id == feedbackId);
      if (index != -1) {
        final updatedFeedback =
            feedbacksNotifier.value[index].copyWith(status: status);
        feedbacksNotifier.value = List.from(feedbacksNotifier.value)
          ..[index] = updatedFeedback;
      }
      print('Updated feedback $feedbackId status to ${status.name}');
    } catch (e) {
      print('Error updating feedback $feedbackId status: $e');
    }
  }

  // ── Getters ────────────────────────────────────────────────────────────────

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