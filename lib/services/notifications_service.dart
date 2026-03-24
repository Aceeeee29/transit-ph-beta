import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification.dart';

class NotificationsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Set<String> _routeApprovalNotificationTypes = {
    'route_approved',
    'route_rejected',
  };
  static const Set<String> _discussionNotificationTypes = {
    'upvote',
    'downvote',
    'comment',
    'reply',
  };

  static Future<Map<String, dynamic>> _getUserPreferences(String userId) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final rawPreferences = userDoc.data()?['preferences'];
    if (rawPreferences is Map<String, dynamic>) {
      return rawPreferences;
    }
    return const <String, dynamic>{};
  }

  static bool _isTypeAllowed(
    String type,
    Map<String, dynamic> preferences,
  ) {
    if (_routeApprovalNotificationTypes.contains(type)) {
      return preferences['routeApprovalUpdates'] as bool? ?? true;
    }

    if (_discussionNotificationTypes.contains(type)) {
      return preferences['newDiscussions'] as bool? ?? true;
    }

    return true;
  }

  static Future<bool> _shouldDeliverNotification(NotificationModel notification) async {
    final preferences = await _getUserPreferences(notification.userId);
    return _isTypeAllowed(notification.type, preferences);
  }

  /// Add a notification to Firestore
  static Future<void> addNotification(NotificationModel notification) async {
    try {
      final shouldDeliver = await _shouldDeliverNotification(notification);
      if (!shouldDeliver) {
        return;
      }

      final data = notification.toJson();
      data['timestamp'] = FieldValue.serverTimestamp();
      await _firestore
          .collection('notifications')
          .doc(notification.id)
          .set(data);
    } catch (e) {
      print('Error adding notification ${notification.id}: $e');
      rethrow;
    }
  }

  /// Get notifications for a user
  static Future<List<NotificationModel>> getNotificationsForUser(
    String userId,
  ) async {
    try {
      final querySnapshot =
          await _firestore
              .collection('notifications')
              .where('userId', isEqualTo: userId)
              .orderBy('timestamp', descending: true)
              .get();
      return querySnapshot.docs
          .map((doc) => NotificationModel.fromJson(doc.data()))
          .toList();
    } catch (e) {
      print('Error fetching notifications for user $userId: $e');
      return [];
    }
  }

  /// Mark a notification as read
  static Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
      });
    } catch (e) {
      print('Error marking notification $notificationId as read: $e');
      rethrow;
    }
  }

  /// Get unread count for a user
  static Future<int> getUnreadCount(String userId) async {
    try {
      final querySnapshot =
          await _firestore
              .collection('notifications')
              .where('userId', isEqualTo: userId)
              .where('isRead', isEqualTo: false)
              .get();
      return querySnapshot.docs.length;
    } catch (e) {
      print('Error fetching unread count for user $userId: $e');
      return 0;
    }
  }

  /// Stream unread notification count for a user in realtime.
  static Stream<int> unreadCountStream(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Delete a notification
  static Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
    } catch (e) {
      print('Error deleting notification $notificationId: $e');
      rethrow;
    }
  }
}
