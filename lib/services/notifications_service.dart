import '../models/notification.dart';

class NotificationsService {
  static final List<NotificationModel> _notifications = [];

  static void addNotification(NotificationModel notification) {
    _notifications.add(notification);
  }

  static List<NotificationModel> getNotificationsForUser(String userId) {
    return _notifications.where((n) => n.userId == userId).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  static void markAsRead(String notificationId) {
    final notification = _notifications.firstWhere(
      (n) => n.id == notificationId,
    );
    notification.isRead = true;
  }

  static int getUnreadCount(String userId) {
    return _notifications.where((n) => n.userId == userId && !n.isRead).length;
  }
}
