import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification.dart';
import '../models/route.dart' as route_model;
import '../services/notifications_service.dart';

class RouteService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

      return querySnapshot.docs
          .map((doc) => route_model.Route.fromJson(doc.data()))
          .where((r) => r.isApproved)
          .toList();
    } catch (e) {
      print('Error fetching approved routes: $e');
      return [];
    }
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
      await _firestore.collection('routes').doc(route.id).set(data);
      print('Route ${route.id} saved with status: pending');
    } catch (e) {
      print('Error saving route ${route.id}: $e');
      rethrow;
    }
  }

  /// Update an existing route
  static Future<void> updateRoute(route_model.Route route) async {
    try {
      final data = route.toJson();
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection('routes').doc(route.id).update(data);
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
        'approvalStatus': route_model.RouteApprovalStatus.approved.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final recipientId = await _resolveNotificationRecipientId(contributorId);
      if (recipientId != null && recipientId.isNotEmpty) {
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
      await _firestore.collection('routes').doc(routeId).update({
        'approvalStatus': route_model.RouteApprovalStatus.rejected.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
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
}