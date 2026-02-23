import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/route.dart' as route_model;

class RouteService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get all routes contributed by a specific user
  static Future<List<route_model.Route>> getRoutesByUser(String userId) async {
    try {
      final querySnapshot =
          await _firestore
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

  /// Save a route to Firestore
  static Future<void> saveRoute(route_model.Route route) async {
    try {
      final data = route.toJson();
      data['createdAt'] = FieldValue.serverTimestamp();
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection('routes').doc(route.id).set(data);
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

  /// Increment upvote count for a route
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

  /// Increment downvote count for a route
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
    String routeId,
    route_model.Report report,
  ) async {
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

  /// Search routes by startLocation and endLocation
  static Future<List<route_model.Route>> searchRoutes(
    String startLocation,
    String endLocation,
  ) async {
    try {
      final querySnapshot =
          await _firestore
              .collection('routes')
              .where('startLocation', isEqualTo: startLocation)
              .where('endLocation', isEqualTo: endLocation)
              .get();

      return querySnapshot.docs
          .map((doc) => route_model.Route.fromJson(doc.data()))
          .toList();
    } catch (e) {
      print('Error searching routes from $startLocation to $endLocation: $e');
      return [];
    }
  }

  /// Get all routes
  static Future<List<route_model.Route>> getAllRoutes() async {
    try {
      final querySnapshot = await _firestore.collection('routes').get();
      return querySnapshot.docs
          .map((doc) => route_model.Route.fromJson(doc.data()))
          .toList();
    } catch (e) {
      print('Error fetching all routes: $e');
      return [];
    }
  }
}
