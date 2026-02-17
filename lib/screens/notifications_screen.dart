import 'package:flutter/material.dart';
import '../models/notification.dart';
import '../services/notifications_service.dart';

class NotificationsScreen extends StatefulWidget {
  final String currentUserName;

  const NotificationsScreen({super.key, required this.currentUserName});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    final notifications = NotificationsService.getNotificationsForUser(
      widget.currentUserName,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body:
          notifications.isEmpty
              ? const Center(child: Text('No notifications'))
              : ListView.builder(
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
                    onTap: () {
                      if (!notification.isRead) {
                        setState(() {
                          NotificationsService.markAsRead(notification.id);
                        });
                      }
                    },
                    tileColor: notification.isRead ? null : Colors.blue.shade50,
                  );
                },
              ),
    );
  }
}
