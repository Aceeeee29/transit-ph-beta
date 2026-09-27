import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import '../services/notifications_service.dart';
import '../services/route_service.dart';
import '../models/notification.dart';
import 'post_detail_screen.dart';
import 'route_map_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final String currentUserId;
  final String? currentUserName;

  const NotificationsScreen({
    super.key,
    required this.currentUserId,
    this.currentUserName,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<NotificationModel>> _notificationsFuture;

  // ─── Color tokens (matches design system) ──────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);

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

  Future<void> _refreshNotifications() async {
    setState(_loadNotifications);
    try {
      await _notificationsFuture;
    } catch (_) {
      // UI already handles the error state.
    }
  }

  Widget _refreshableCenteredContent(Widget child) {
    return RefreshIndicator(
      color: _accent,
      onRefresh: _refreshNotifications,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Center(child: child),
          ),
        ],
      ),
    );
  }

  // ─── Notification type helpers ─────────────────────────────────────────────
  IconData _notifIcon(String type) => switch (type) {
    'upvote' || 'like' => Icons.thumb_up_rounded,
    'downvote' => Icons.thumb_down_rounded,
    'comment' => Icons.comment_rounded,
    'reply' => Icons.reply_rounded,
    'route_approved' => Icons.route_rounded,
    'route_rejected' => Icons.route_rounded,
    _ => Icons.notifications_rounded,
  };

  Color _notifColor(String type) => switch (type) {
    'upvote' || 'like' => const Color(0xFF2EA56E),
    'downvote' => const Color(0xFFE05C6A),
    'comment' => _accent,
    'reply' => const Color(0xFF9B7FE8),
    'route_approved' => const Color(0xFF2EA56E),
    'route_rejected' => _danger,
    _ => _textSecondary,
  };

  String _notifTypeLabel(String type) => switch (type) {
    'upvote' || 'like' => 'Upvote',
    'downvote' => 'Downvote',
    'comment' => 'Comment',
    'reply' => 'Reply',
    'route_approved' => 'Route Approved',
    'route_rejected' => 'Route Rejected',
    _ => 'Notification',
  };

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static const _postNotificationTypes = {
    'upvote',
    'like',
    'downvote',
    'comment',
    'reply',
  };

  static const _routeNotificationTypes = {'route_approved', 'route_rejected'};

  bool _isNavigable(NotificationModel n) {
    if (_postNotificationTypes.contains(n.type)) {
      return n.postId != null && n.postId!.trim().isNotEmpty;
    }
    if (_routeNotificationTypes.contains(n.type)) {
      return n.routeId != null && n.routeId!.trim().isNotEmpty;
    }
    return false;
  }

  String get _effectiveUserName {
    final passed = widget.currentUserName?.trim();
    if (passed != null && passed.isNotEmpty) return passed;
    final displayName =
        firebase_auth.FirebaseAuth.instance.currentUser?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return 'User';
  }

  Future<void> _handleNotificationTap(NotificationModel notification) async {
    // Always mark as read first.
    if (!notification.isRead) {
      try {
        await NotificationsService.markAsRead(notification.id);
      } catch (_) {
        // Non-fatal — continue to navigation.
      }
      if (mounted) {
        setState(() {
          _loadNotifications();
        });
      }
      notification.isRead = true;
    }

    if (!mounted) return;

    // ── Post notifications (like / upvote / downvote / comment / reply) ──
    if (_postNotificationTypes.contains(notification.type)) {
      final postId = notification.postId?.trim();
      if (postId == null || postId.isEmpty) {
        _showInfo('This notification is not linked to a post.');
        return;
      }
      _openPost(postId, notification);
      return;
    }

    // ── Route approval notifications ──
    if (_routeNotificationTypes.contains(notification.type)) {
      final routeId = notification.routeId?.trim();
      if (routeId == null || routeId.isEmpty) {
        // Legacy notification created before routeId was stored.
        _showInfo(notification.message);
        return;
      }
      await _openRoute(routeId, notification.type);
      return;
    }
  }

  void _openPost(String postId, NotificationModel notification) {
    final isCommentThread =
        notification.type == 'comment' || notification.type == 'reply';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          postId: postId,
          currentUserId: widget.currentUserId,
          currentUserName: _effectiveUserName,
          highlightCommentId: notification.commentId,
          openCommentsInitially: isCommentThread,
        ),
      ),
    );
  }

  Future<void> _openRoute(String routeId, String type) async {
    _showLoading('Loading route…');
    try {
      final route = await RouteService.getRouteById(routeId);
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      if (route == null) {
        final hint = type == 'route_rejected'
            ? 'The rejected route is no longer available.'
            : 'This route is no longer available.';
        _showInfo(hint);
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RouteMapScreen(route: route)),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      _showInfo('Failed to load route. Please try again.');
    }
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showLoading(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: _accent,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      // ─── AppBar ────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _border),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new,
              size: 15,
              color: _textSecondary,
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.notifications_outlined,
                color: _accent,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Notifications',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),

      // ─── Body ──────────────────────────────────────────────────────────
      body: FutureBuilder<List<NotificationModel>>(
        future: _notificationsFuture,
        builder: (context, snapshot) {
          // ── Loading ──
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
            );
          }

          // ── Error ──
          if (snapshot.hasError) {
            return _refreshableCenteredContent(
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: _danger.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      size: 32,
                      color: _danger,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Something went wrong',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${snapshot.error}',
                    style: const TextStyle(fontSize: 13, color: _textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // ── Empty ──
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _refreshableCenteredContent(
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _surfaceAlt,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.notifications_off_outlined,
                      size: 36,
                      color: _textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No notifications yet',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Upvotes, downvotes, comments, replies, and route approvals\nwill appear here.',
                    style: TextStyle(
                      fontSize: 13,
                      color: _textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // ── Notifications list ──
          final notifications = snapshot.data!;
          final unreadCount = notifications.where((n) => !n.isRead).length;

          return RefreshIndicator(
            color: _accent,
            onRefresh: _refreshNotifications,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              itemCount: notifications.length + (unreadCount > 0 ? 1 : 0),
              itemBuilder: (context, index) {
                if (unreadCount > 0 && index == 0) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.mark_email_unread_outlined,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$unreadCount unread notification${unreadCount > 1 ? 's' : ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            for (final n in notifications.where(
                              (n) => !n.isRead,
                            )) {
                              await NotificationsService.markAsRead(n.id);
                            }
                            setState(_loadNotifications);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                            child: const Text(
                              'Mark all read',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final dataIndex = unreadCount > 0 ? index - 1 : index;
                final notification = notifications[dataIndex];
                final color = _notifColor(notification.type);
                final isUnread = !notification.isRead;
                final navigable = _isNavigable(notification);

                    return GestureDetector(
                      onTap: () => _handleNotificationTap(notification),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: isUnread ? _accentSoft : _surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                isUnread ? _accent.withOpacity(0.25) : _border,
                            width: isUnread ? 1.5 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withOpacity(
                                isUnread ? 0.07 : 0.04,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icon badge
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: color.withOpacity(0.25),
                                  ),
                                ),
                                child: Icon(
                                  _notifIcon(notification.type),
                                  size: 20,
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Type label + time row
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                          ),
                                          child: Text(
                                            _notifTypeLabel(notification.type),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: color,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          _formatTime(notification.timestamp),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: _textSecondary,
                                          ),
                                        ),
                                        if (isUnread) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              color: _accent,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: _accent.withOpacity(
                                                    0.4,
                                                  ),
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // Message
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            notification.message,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: isUnread
                                                  ? _textPrimary
                                                  : _textSecondary,
                                              fontWeight: isUnread
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                        if (navigable) ...[
                                          const SizedBox(width: 8),
                                          const Padding(
                                            padding: EdgeInsets.only(top: 2),
                                            child: Icon(
                                              Icons
                                                  .arrow_forward_ios_rounded,
                                              size: 13,
                                              color: _textSecondary,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
              },
            ),
          );
        },
      ),
    );
  }
}
