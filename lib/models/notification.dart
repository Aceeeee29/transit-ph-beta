import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String userId; // recipient
  final String type; // 'upvote', 'downvote', 'comment', 'reply', 'achievement', 'system'
  final String? postId;
  final String? commentId;
  final String? fromUserId;
  final String? fromUserName;
  final DateTime timestamp;
  final String message;
  bool isRead;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    this.postId,
    this.commentId,
    this.fromUserId,
    this.fromUserName,
    required this.timestamp,
    required this.message,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'type': type,
      'postId': postId,
      'commentId': commentId,
      'fromUserId': fromUserId,
      'fromUserName': fromUserName,
      'timestamp': timestamp.toIso8601String(),
      'message': message,
      'isRead': isRead,
    };
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    // FIX: Handle both Firestore Timestamp and ISO string gracefully.
    // addNotification() overwrites timestamp with FieldValue.serverTimestamp()
    // so Firestore stores it as a Timestamp, but toJson() serialises it as a
    // String — support both to avoid a cast crash on read.
    DateTime parsedTimestamp;
    final raw = json['timestamp'];
    if (raw is Timestamp) {
      parsedTimestamp = raw.toDate();
    } else if (raw is String) {
      parsedTimestamp = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      parsedTimestamp = DateTime.now();
    }

    return NotificationModel(
      id: json['id'],
      userId: json['userId'],
      type: json['type'],
      postId: json['postId'],
      commentId: json['commentId'],
      fromUserId: json['fromUserId'],
      fromUserName: json['fromUserName'],
      timestamp: parsedTimestamp,
      message: json['message'],
      isRead: json['isRead'] ?? false,
    );
  }
}