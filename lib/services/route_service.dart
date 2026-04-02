import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/notification.dart';
import '../models/route.dart' as route_model;
import '../services/notifications_service.dart';

class RouteService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const int _staleReviewDays = 45;

  static Future<String?> _resolveNotificationRecipientId(
    String? contributorId,
  ) async {
    final raw = contributorId?.trim();
    if (raw == null || raw.isEmpty) return null;

    if (!raw.contains('@')) {
      return raw;
    }

    try {
      final userByEmail = await _firestore
          .collection('users')
          .where('email', isEqualTo: raw)
          .limit(1)
          .get();
      if (userByEmail.docs.isNotEmpty) {
        final data = userByEmail.docs.first.data();
        final uidFromField = (data['uid'] as String?)?.trim();
        if (uidFromField != null && uidFromField.isNotEmpty) {
          return uidFromField;
        }
        return userByEmail.docs.first.id;
      }
    } catch (e) {
      print('Error resolving contributor email to uid ($raw): $e');
    }

    return null;
  }

  static DocumentReference<Map<String, dynamic>> _routeDoc(String routeId) {
    return _firestore.collection('routes').doc(routeId);
  }

  static DocumentReference<Map<String, dynamic>> _routeVoteDoc(
    String routeId,
    String userId,
  ) {
    return _routeDoc(routeId).collection('routeVotes').doc(userId);
  }

  static DocumentReference<Map<String, dynamic>> _routeViewDoc(
    String routeId,
    String userId,
  ) {
    return _routeDoc(routeId).collection('routeViews').doc(userId);
  }

  static DocumentReference<Map<String, dynamic>> _routeFeedbackDoc(
    String routeId,
    String userId,
  ) {
    return _routeDoc(routeId).collection('routeFeedback').doc(userId);
  }

  static Future<String> _currentActorIdOrSystem() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return (uid == null || uid.trim().isEmpty) ? 'system' : uid;
  }

  static Future<void> _writeRouteAuditLog({
    required String routeId,
    required String action,
    required String actorId,
    Map<String, dynamic>? meta,
  }) async {
    try {
      await _routeDoc(routeId).collection('auditLogs').add({
        'routeId': routeId,
        'action': action,
        'actorId': actorId,
        'meta': meta ?? const <String, dynamic>{},
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error writing route audit log for $routeId ($action): $e');
    }
  }

  static Future<void> _incrementApprovedContributionStats(
    String contributorUid,
  ) async {
    final uid = contributorUid.trim();
    if (uid.isEmpty) return;

    final userRef = _firestore.collection('users').doc(uid);
    await userRef.set({
      'routesContributed': FieldValue.increment(1),
      'contributionCount': FieldValue.increment(1),
    }, SetOptions(merge: true));

    final userSnap = await userRef.get();
    if (!userSnap.exists) return;

    final data = userSnap.data() ?? const <String, dynamic>{};
    final routesContributed =
        (data['routesContributed'] as num?)?.toInt() ??
        (data['contributionCount'] as num?)?.toInt() ??
        0;
    final unlockedAchievements = List<String>.from(
      data['achievements'] ?? const <String>[],
    );
    final unlockedBadges = List<String>.from(data['badges'] ?? const <String>[]);

    final pioneerUnlocked = routesContributed >= 10;
    final heroUnlocked = routesContributed >= 50;
    final contributorBadgeUnlocked = routesContributed >= 10;

    final newlyUnlockedAchievements = <String>[];
    final newlyUnlockedBadges = <String>[];

    if (pioneerUnlocked && !unlockedAchievements.contains('route_pioneer')) {
      newlyUnlockedAchievements.add('route_pioneer');
    }
    if (heroUnlocked && !unlockedAchievements.contains('community_hero')) {
      newlyUnlockedAchievements.add('community_hero');
    }
    if (contributorBadgeUnlocked && !unlockedBadges.contains('contributor')) {
      newlyUnlockedBadges.add('contributor');
    }

    await userRef.collection('achievements').doc('route_pioneer').set({
      'id': 'route_pioneer',
      'progress': routesContributed,
      'isUnlocked': pioneerUnlocked,
      if (newlyUnlockedAchievements.contains('route_pioneer'))
        'unlockedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await userRef.collection('achievements').doc('community_hero').set({
      'id': 'community_hero',
      'progress': routesContributed,
      'isUnlocked': heroUnlocked,
      if (newlyUnlockedAchievements.contains('community_hero'))
        'unlockedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await userRef.collection('badges').doc('contributor').set({
      'id': 'contributor',
      'isUnlocked': contributorBadgeUnlocked,
      if (newlyUnlockedBadges.contains('contributor'))
        'earnedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final userUpdates = <String, dynamic>{};
    if (newlyUnlockedAchievements.isNotEmpty) {
      userUpdates['achievements'] = FieldValue.arrayUnion(
        newlyUnlockedAchievements,
      );
    }
    if (newlyUnlockedBadges.isNotEmpty) {
      userUpdates['badges'] = FieldValue.arrayUnion(newlyUnlockedBadges);
    }

    if (userUpdates.isNotEmpty) {
      await userRef.set(userUpdates, SetOptions(merge: true));
    }
  }

  static Future<void> _markStaleRoutesForReviewIfNeeded({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  }) async {
    final now = DateTime.now();
    for (final doc in docs) {
      final data = doc.data();
      final routeId = data['id']?.toString() ?? doc.id;
      final approvalStatus = data['approvalStatus']?.toString();
      if (approvalStatus != route_model.RouteApprovalStatus.approved.name) {
        continue;
      }

      final updatedTs = data['updatedAt'] as Timestamp?;
      final createdTs = data['createdAt'] as Timestamp?;
      final referenceTime = (updatedTs ?? createdTs)?.toDate();
      if (referenceTime == null) continue;

      final ageDays = now.difference(referenceTime).inDays;
      if (ageDays < _staleReviewDays) continue;

      final alreadyFlagged = data['staleNeedsReview'] == true;
      if (alreadyFlagged) continue;

      final hasFare = (data['price']?.toString().trim().isNotEmpty ?? false);
      final hasSchedule = (data['schedule']?.toString().trim().isNotEmpty ?? false);

      final patch = <String, dynamic>{
        'staleNeedsReview': true,
        'staleReason': 'Auto-flagged: fare/schedule data older than $_staleReviewDays days.',
        'staleFlaggedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (hasFare) {
        patch['fareExpired'] = true;
      }
      if (hasSchedule) {
        patch['scheduleExpired'] = true;
      }

      await _routeDoc(routeId).update(patch);
      await _writeRouteAuditLog(
        routeId: routeId,
        action: 'auto_stale_flagged',
        actorId: 'system',
        meta: {
          'staleDays': ageDays,
          'fareExpired': hasFare,
          'scheduleExpired': hasSchedule,
        },
      );
    }
  }

  /// Get only APPROVED community routes — what regular users see.
  /// We filter client-side (not in the query) so that legacy routes
  /// without an approvalStatus field are correctly defaulted to approved
  /// by fromJson, rather than being excluded by Firestore's where clause.
  static Future<List<route_model.Route>> getAllRoutes() async {
    try {
      final querySnapshot = await _firestore
          .collection('routes')
          .orderBy('createdAt', descending: true)
          .get();

      try {
        await _markStaleRoutesForReviewIfNeeded(docs: querySnapshot.docs);
      } catch (e) {
        print('Skipped stale-route auto-flagging due to permissions/runtime issue: $e');
      }

      return querySnapshot.docs
          .map((doc) => route_model.Route.fromJson(doc.data()))
          .where((r) => r.isApproved)
          .toList();
    } catch (e) {
      print('Error fetching approved routes: $e');
      return [];
    }
  }

  static Stream<List<route_model.Route>> watchAllRoutes() {
    return _firestore
        .collection('routes')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((querySnapshot) => querySnapshot.docs
            .map((doc) => route_model.Route.fromJson(doc.data()))
            .where((r) => r.isApproved)
            .toList());
  }

  /// Get PENDING routes — for the moderator review tab
  static Future<List<route_model.Route>> getPendingRoutes() async {
    try {
      final querySnapshot = await _firestore
          .collection('routes')
          .where(
            'approvalStatus',
            isEqualTo: route_model.RouteApprovalStatus.pending.name,
          )
          .get();

      final routes = querySnapshot.docs
          .map((doc) => route_model.Route.fromJson(doc.data()))
          .toList();
      // Sort newest first client-side
      routes.sort((a, b) {
        final aTime = a.createdAt ?? DateTime(2000);
        final bTime = b.createdAt ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });
      return routes;
    } catch (e) {
      print('Error fetching pending routes: $e');
      return [];
    }
  }

  /// Get all routes contributed by a specific user (all statuses — for profile)
  static Future<List<route_model.Route>> getRoutesByUser(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('routes')
          .where('contributorId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => route_model.Route.fromJson(doc.data()))
          .toList();
    } catch (e) {
      print('Error fetching routes for user $userId: $e');
      return [];
    }
  }

  /// Get a specific route by ID
  static Future<route_model.Route?> getRouteById(String routeId) async {
    try {
      final docSnapshot =
          await _firestore.collection('routes').doc(routeId).get();
      if (docSnapshot.exists) {
        return route_model.Route.fromJson(docSnapshot.data()!);
      }
      return null;
    } catch (e) {
      print('Error fetching route $routeId: $e');
      return null;
    }
  }

  /// Save a new route — always starts as PENDING, awaiting moderator approval
  static Future<void> saveRoute(route_model.Route route) async {
    try {
      final data = route.toJson();
      data['approvalStatus'] = route_model.RouteApprovalStatus.pending.name;
      data['createdAt'] = FieldValue.serverTimestamp();
      data['updatedAt'] = FieldValue.serverTimestamp();
      data['feedbackSummary'] = {
        'fareAccurateYes': 0,
        'fareAccurateNo': 0,
        'scheduleAccurateYes': 0,
        'scheduleAccurateNo': 0,
        'stillOperatingYes': 0,
        'stillOperatingNo': 0,
      };
      await _firestore.collection('routes').doc(route.id).set(data);
      final actorId = await _currentActorIdOrSystem();
      await _writeRouteAuditLog(
        routeId: route.id,
        action: 'route_created',
        actorId: actorId,
      );
      print('Route ${route.id} saved with status: pending');
    } catch (e) {
      print('Error saving route ${route.id}: $e');
      rethrow;
    }
  }

  /// Update an existing route
  static Future<void> updateRoute(route_model.Route route) async {
    try {
      final before = await _firestore.collection('routes').doc(route.id).get();
      final data = route.toJson();
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection('routes').doc(route.id).update(data);
      final actorId = await _currentActorIdOrSystem();
      await _writeRouteAuditLog(
        routeId: route.id,
        action: 'route_updated',
        actorId: actorId,
        meta: {
          'beforeApprovalStatus': before.data()?['approvalStatus'],
          'afterApprovalStatus': data['approvalStatus'],
          'changedPrice': before.data()?['price'] != data['price'],
          'changedSchedule': before.data()?['schedule'] != data['schedule'],
        },
      );
    } catch (e) {
      print('Error updating route ${route.id}: $e');
      rethrow;
    }
  }

  /// Approve a route — called by moderator
  static Future<void> approveRoute(String routeId) async {
    try {
      String? contributorId;
      String routeTitle = 'your submitted route';
      bool wasAlreadyApproved = false;

      final routeSnapshot = await _firestore.collection('routes').doc(routeId).get();
      if (routeSnapshot.exists) {
        final routeData = routeSnapshot.data();
        contributorId = (routeData?['contributorId'] as String?)?.trim();
        final currentStatus = (routeData?['approvalStatus'] as String?)?.trim();
        wasAlreadyApproved =
            currentStatus == route_model.RouteApprovalStatus.approved.name;
        final start = routeData?['startLocation'] as String?;
        final end = routeData?['endLocation'] as String?;
        if (start != null && end != null) {
          routeTitle = '$start to $end';
        }
      }

      await _firestore.collection('routes').doc(routeId).update({
        'approvalStatus': route_model.RouteApprovalStatus.approved.name,
        'staleNeedsReview': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final actorId = await _currentActorIdOrSystem();
      await _writeRouteAuditLog(
        routeId: routeId,
        action: 'moderator_approved',
        actorId: actorId,
      );

      final recipientId = await _resolveNotificationRecipientId(contributorId);
      if (recipientId != null && recipientId.isNotEmpty) {
        if (!wasAlreadyApproved) {
          try {
            await _incrementApprovedContributionStats(recipientId);
          } catch (e) {
            print(
              'Error updating approved contribution stats for $recipientId: $e',
            );
          }
        }

        try {
          await NotificationsService.addNotification(
            NotificationModel(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              userId: recipientId,
              type: 'route_approved',
              timestamp: DateTime.now(),
              message: 'Your submitted route ($routeTitle) was approved and is now live.',
            ),
          );
        } catch (e) {
          print('Error creating approval notification for route $routeId: $e');
        }
      }

      print('Route $routeId approved');
    } catch (e) {
      print('Error approving route $routeId: $e');
      rethrow;
    }
  }

  /// Reject a route — called by moderator
  static Future<void> rejectRoute(String routeId) async {
    try {
      String? contributorId;
      String routeTitle = 'your submitted route';

      final routeSnapshot = await _firestore.collection('routes').doc(routeId).get();
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
        'approvalStatus': route_model.RouteApprovalStatus.rejected.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final actorId = await _currentActorIdOrSystem();
      await _writeRouteAuditLog(
        routeId: routeId,
        action: 'moderator_rejected',
        actorId: actorId,
      );

      final recipientId = await _resolveNotificationRecipientId(contributorId);
      if (recipientId != null && recipientId.isNotEmpty) {
        try {
          await NotificationsService.addNotification(
            NotificationModel(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              userId: recipientId,
              type: 'route_rejected',
              timestamp: DateTime.now(),
              message:
                  'Your submitted route ($routeTitle) was rejected by moderators.',
            ),
          );
        } catch (e) {
          print('Error creating rejection notification for route $routeId: $e');
        }
      }

      print('Route $routeId rejected');
    } catch (e) {
      print('Error rejecting route $routeId: $e');
      rethrow;
    }
  }

  /// Delete a route
  static Future<void> deleteRoute(String routeId) async {
    try {
      await _firestore.collection('routes').doc(routeId).delete();
    } catch (e) {
      print('Error deleting route $routeId: $e');
      rethrow;
    }
  }

  /// Increment view count for a route
  static Future<void> incrementView(String routeId) async {
    try {
      await _firestore.collection('routes').doc(routeId).update({
        'views': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error incrementing view for route $routeId: $e');
      rethrow;
    }
  }

  /// Increment a route view once per user
  static Future<void> incrementViewForUser(
      String routeId, String userId) async {
    final routeRef = _routeDoc(routeId);
    final viewRef = _routeViewDoc(routeId, userId);

    await _firestore.runTransaction((transaction) async {
      final routeSnap = await transaction.get(routeRef);
      if (!routeSnap.exists) throw StateError('route_not_found');

      final viewSnap = await transaction.get(viewRef);
      if (viewSnap.exists) return;

      transaction.set(viewRef, {
        'userId': userId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.update(routeRef, {
        'views': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Returns true for upvote, false for downvote, null if no vote
  static Future<bool?> getUserVote(String routeId, String userId) async {
    try {
      final voteSnap = await _routeVoteDoc(routeId, userId).get();
      if (!voteSnap.exists) return null;
      final vote = voteSnap.data()?['vote'] as String?;
      if (vote == 'up') return true;
      if (vote == 'down') return false;
      return null;
    } catch (e) {
      print('Error fetching vote for route $routeId, user $userId: $e');
      return null;
    }
  }

  /// Applies an up/down vote
  static Future<bool?> setUserVote({
    required String routeId,
    required String userId,
    required bool isUpvote,
  }) async {
    final routeRef = _routeDoc(routeId);
    final voteRef = _routeVoteDoc(routeId, userId);

    return _firestore.runTransaction<bool?>((transaction) async {
      final routeSnap = await transaction.get(routeRef);
      if (!routeSnap.exists) throw StateError('route_not_found');

      final voteSnap = await transaction.get(voteRef);
      final existingVote = voteSnap.data()?['vote'] as String?;
      final nextVote = isUpvote ? 'up' : 'down';

      if (existingVote == null) {
        transaction.set(voteRef, {
          'userId': userId,
          'vote': nextVote,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(routeRef, {
          isUpvote ? 'upvotes' : 'downvotes': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return isUpvote;
      }

      if (existingVote == nextVote) {
        transaction.delete(voteRef);
        transaction.update(routeRef, {
          isUpvote ? 'upvotes' : 'downvotes': FieldValue.increment(-1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return null;
      }

      throw StateError('remove_first');
    });
  }

  /// Increment upvote count
  static Future<void> incrementUpvote(String routeId) async {
    try {
      await _firestore.collection('routes').doc(routeId).update({
        'upvotes': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error incrementing upvote for route $routeId: $e');
      rethrow;
    }
  }

  /// Increment downvote count
  static Future<void> incrementDownvote(String routeId) async {
    try {
      await _firestore.collection('routes').doc(routeId).update({
        'downvotes': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error incrementing downvote for route $routeId: $e');
      rethrow;
    }
  }

  /// Add a report to a route
  static Future<void> addReport(
      String routeId, route_model.Report report) async {
    try {
      await _firestore.collection('routes').doc(routeId).update({
        'reports': FieldValue.arrayUnion([
          {
            'type': report.type,
            'description': report.description,
            'timestamp': report.timestamp.millisecondsSinceEpoch,
          },
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error adding report to route $routeId: $e');
      rethrow;
    }
  }

  /// Search routes by startLocation and endLocation (approved only)
  static Future<List<route_model.Route>> searchRoutes(
    String startLocation,
    String endLocation,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection('routes')
          .where('startLocation', isEqualTo: startLocation)
          .where('endLocation', isEqualTo: endLocation)
          .get();

      return querySnapshot.docs
          .map((doc) => route_model.Route.fromJson(doc.data()))
          .where((r) => r.isApproved)
          .toList();
    } catch (e) {
      print('Error searching routes from $startLocation to $endLocation: $e');
      return [];
    }
  }

  static Future<Map<String, int>> getRouteFeedbackSummary(String routeId) async {
    try {
      final doc = await _routeDoc(routeId).get();
      final summary = doc.data()?['feedbackSummary'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      return {
        'fareAccurateYes': (summary['fareAccurateYes'] as num?)?.toInt() ?? 0,
        'fareAccurateNo': (summary['fareAccurateNo'] as num?)?.toInt() ?? 0,
        'scheduleAccurateYes': (summary['scheduleAccurateYes'] as num?)?.toInt() ?? 0,
        'scheduleAccurateNo': (summary['scheduleAccurateNo'] as num?)?.toInt() ?? 0,
        'stillOperatingYes': (summary['stillOperatingYes'] as num?)?.toInt() ?? 0,
        'stillOperatingNo': (summary['stillOperatingNo'] as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      print('Error loading route feedback summary for $routeId: $e');
      return {
        'fareAccurateYes': 0,
        'fareAccurateNo': 0,
        'scheduleAccurateYes': 0,
        'scheduleAccurateNo': 0,
        'stillOperatingYes': 0,
        'stillOperatingNo': 0,
      };
    }
  }

  static Stream<Map<String, int>> watchRouteFeedbackSummary(String routeId) {
    return _routeDoc(routeId).snapshots().map((doc) {
      final summary = doc.data()?['feedbackSummary'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      return {
        'fareAccurateYes': (summary['fareAccurateYes'] as num?)?.toInt() ?? 0,
        'fareAccurateNo': (summary['fareAccurateNo'] as num?)?.toInt() ?? 0,
        'scheduleAccurateYes': (summary['scheduleAccurateYes'] as num?)?.toInt() ?? 0,
        'scheduleAccurateNo': (summary['scheduleAccurateNo'] as num?)?.toInt() ?? 0,
        'stillOperatingYes': (summary['stillOperatingYes'] as num?)?.toInt() ?? 0,
        'stillOperatingNo': (summary['stillOperatingNo'] as num?)?.toInt() ?? 0,
      };
    });
  }

  static Future<void> submitRouteQualityFeedback({
    required String routeId,
    required String userId,
    required bool fareAccurate,
    required bool scheduleAccurate,
    required bool stillOperating,
  }) async {
    final routeRef = _routeDoc(routeId);
    final feedbackRef = _routeFeedbackDoc(routeId, userId);

    await _firestore.runTransaction((transaction) async {
      final routeSnap = await transaction.get(routeRef);
      if (!routeSnap.exists) throw StateError('route_not_found');
      final prevSnap = await transaction.get(feedbackRef);

      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'feedbackSummary.lastFeedbackAt': FieldValue.serverTimestamp(),
        'feedbackSummary.fareAccurateYes': FieldValue.increment(fareAccurate ? 1 : 0),
        'feedbackSummary.fareAccurateNo': FieldValue.increment(fareAccurate ? 0 : 1),
        'feedbackSummary.scheduleAccurateYes': FieldValue.increment(scheduleAccurate ? 1 : 0),
        'feedbackSummary.scheduleAccurateNo': FieldValue.increment(scheduleAccurate ? 0 : 1),
        'feedbackSummary.stillOperatingYes': FieldValue.increment(stillOperating ? 1 : 0),
        'feedbackSummary.stillOperatingNo': FieldValue.increment(stillOperating ? 0 : 1),
      };

      transaction.set(feedbackRef, {
        'routeId': routeId,
        'userId': userId,
        'fareAccurate': fareAccurate,
        'scheduleAccurate': scheduleAccurate,
        'stillOperating': stillOperating,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!prevSnap.exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.update(routeRef, updates);
    });

    await _writeRouteAuditLog(
      routeId: routeId,
      action: 'commuter_feedback_submitted',
      actorId: userId,
      meta: {
        'fareAccurate': fareAccurate,
        'scheduleAccurate': scheduleAccurate,
        'stillOperating': stillOperating,
      },
    );
  }

  static Future<Map<String, bool>?> getUserRouteQualityFeedback({
    required String routeId,
    required String userId,
  }) async {
    try {
      final doc = await _routeFeedbackDoc(routeId, userId).get();
      if (!doc.exists) return null;
      final data = doc.data() ?? const <String, dynamic>{};
      return {
        'fareAccurate': (data['fareAccurate'] as bool?) ?? true,
        'scheduleAccurate': (data['scheduleAccurate'] as bool?) ?? true,
        'stillOperating': (data['stillOperating'] as bool?) ?? true,
      };
    } catch (e) {
      print('Error loading user route quality feedback for $routeId: $e');
      return null;
    }
  }
}