import 'package:flutter/material.dart';
import 'achievement_notification.dart';

class NotificationOverlay extends StatefulWidget {
  final List<String> notifications;
  final VoidCallback onAllDismissed;

  const NotificationOverlay({
    super.key,
    required this.notifications,
    required this.onAllDismissed,
  });

  @override
  State<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlay> {
  late List<String> _currentNotifications;

  @override
  void initState() {
    super.initState();
    _currentNotifications = List.from(widget.notifications);
  }

  void _dismissNotification(int index) {
    setState(() {
      _currentNotifications.removeAt(index);
    });

    if (_currentNotifications.isEmpty) {
      widget.onAllDismissed();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentNotifications.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Semi-transparent background
        Container(color: Colors.black.withOpacity(0.1)),
        // Notifications
        ..._currentNotifications.asMap().entries.map((entry) {
          final index = entry.key;
          final notification = entry.value;

          // Parse notification string (format: "Type: Name")
          final parts = notification.split(': ');
          final type = parts[0]; // "Achievement" or "Badge"
          final name = parts.length > 1 ? parts[1] : notification;

          return Positioned(
            top: 50 + (index * 120), // Stack notifications vertically
            left: 16,
            right: 16,
            child: AchievementNotification(
              title: '$type Unlocked!',
              description: 'Congratulations! You earned the $name $type.',
              onDismiss: () => _dismissNotification(index),
            ),
          );
        }),
      ],
    );
  }
}
