import 'package:flutter/material.dart';
import '../services/notifications_service.dart';
import '../models/notification.dart';

class NotificationsScreen extends StatefulWidget {
  final String currentUserId;

  const NotificationsScreen({super.key, required this.currentUserId});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<NotificationModel>> _notificationsFuture;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  void _loadNotifications() {
    _notificationsFuture = NotificationsService.getNotificationsForUser(
      widget.currentUserId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: FutureBuilder<List<NotificationModel>>(
        future: _notificationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No notifications'));
          } else {
            final notifications = snapshot.data!;
            return ListView.builder(
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return ListTile(
                  leading: Icon(
                    notification.type == 'like'
                        ? Icons.thumb_up
                        : notification.type == 'comment'
                        ? Icons.comment
                        : Icons.reply,
                    color: notification.isRead ? Colors.grey : Colors.blue,
                  ),
                  title: Text(notification.message),
                  subtitle: Text(
                    '${notification.timestamp.hour}:${notification.timestamp.minute.toString().padLeft(2, '0')}',
                  ),
                  onTap: () async {
                    if (!notification.isRead) {
                      await NotificationsService.markAsRead(notification.id);
                      setState(() {
                        _loadNotifications();
                      });
                    }
                  },
                  tileColor: notification.isRead ? null : Colors.blue.shade50,
                );
              },
            );
          }
        },
      ),
    );
  }
}
