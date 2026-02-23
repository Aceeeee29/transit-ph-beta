import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification.dart';

class NotificationsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Add a notification to Firestore
  static Future<void> addNotification(NotificationModel notification) async {
    try {
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
