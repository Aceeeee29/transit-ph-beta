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
      await _firestore.collection('routes').doc(route.id).set(route.toJson());
    } catch (e) {
      print('Error saving route ${route.id}: $e');
      rethrow;
    }
  }

  /// Update an existing route
  static Future<void> updateRoute(route_model.Route route) async {
    try {
      await _firestore
          .collection('routes')
          .doc(route.id)
          .update(route.toJson());
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
}
