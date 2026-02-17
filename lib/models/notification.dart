class NotificationModel {
  final String id;
  final String userId; // recipient
  final String type; // 'like', 'comment', 'reply'
  final String postId;
  final String? commentId;
  final String fromUserName;
  final DateTime timestamp;
  final String message;
  bool isRead;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.postId,
    this.commentId,
    required this.fromUserName,
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
      'fromUserName': fromUserName,
      'timestamp': timestamp.toIso8601String(),
      'message': message,
      'isRead': isRead,
    };
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'],
      userId: json['userId'],
      type: json['type'],
      postId: json['postId'],
      commentId: json['commentId'],
      fromUserName: json['fromUserName'],
      timestamp: DateTime.parse(json['timestamp']),
      message: json['message'],
      isRead: json['isRead'] ?? false,
    );
  }
}
