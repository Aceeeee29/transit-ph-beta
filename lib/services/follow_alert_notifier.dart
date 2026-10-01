import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications for a followed route, so a traveler with the app in
/// the background (phone in pocket) still hears about it.
class FollowAlertNotifier {
  FollowAlertNotifier._();

  /// Status-bar icon, shared with the tracking notification.
  static const statusIcon = 'ic_stat_transitph';

  static const _channelId = 'follow_route_alerts';
  static const _channelName = 'Follow Route alerts';
  static const _arrivalId = 4101;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  static Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(statusIcon),
      ),
    );
    _isInitialized = true;
  }

  static Future<void> showArrived(String destination) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _ensureInitialized();
      await _plugin.show(
        id: _arrivalId,
        title: "You've arrived",
        body: destination,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Arrival alerts while following a route.',
            importance: Importance.high,
            priority: Priority.high,
            icon: statusIcon,
          ),
        ),
      );
    } catch (e) {
      debugPrint('FollowAlertNotifier: could not show arrival: $e');
    }
  }
}
