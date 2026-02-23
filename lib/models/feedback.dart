enum FeedbackType { report, feedback }

enum FeedbackTargetType { post, user, general }

enum FeedbackStatus { pending, resolved, dismissed }

class Feedback {
  final String id;
  final String userId;
  final FeedbackType type;
  final String content;
  final String? targetId; // ID of the post or user being reported/feedbacked
  final FeedbackTargetType? targetType;
  final FeedbackStatus status;
  final DateTime timestamp;

  Feedback({
    required this.id,
    required this.userId,
    required this.type,
    required this.content,
    this.targetId,
    this.targetType,
    this.status = FeedbackStatus.pending,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'type': type.name,
      'content': content,
      'targetId': targetId,
      'targetType': targetType?.name,
      'status': status.name,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory Feedback.fromJson(Map<String, dynamic> json) {
    return Feedback(
      id: json['id'],
      userId: json['userId'],
      type: FeedbackType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => FeedbackType.feedback,
      ),
      content: json['content'],
      targetId: json['targetId'],
      targetType:
          json['targetType'] != null
              ? FeedbackTargetType.values.firstWhere(
                (e) => e.name == json['targetType'],
                orElse: () => FeedbackTargetType.general,
              )
              : null,
      status: FeedbackStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => FeedbackStatus.pending,
      ),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Feedback copyWith({
    String? id,
    String? userId,
    FeedbackType? type,
    String? content,
    String? targetId,
    FeedbackTargetType? targetType,
    FeedbackStatus? status,
    DateTime? timestamp,
  }) {
    return Feedback(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      content: content ?? this.content,
      targetId: targetId ?? this.targetId,
      targetType: targetType ?? this.targetType,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
