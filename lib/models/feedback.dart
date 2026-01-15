enum FeedbackType { report, feedback }

class Feedback {
  final String id;
  final String userId;
  final FeedbackType type;
  final String content;
  final String? targetId; // ID of the post or user being reported/feedbacked
  final DateTime timestamp;

  Feedback({
    required this.id,
    required this.userId,
    required this.type,
    required this.content,
    this.targetId,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'type': type.name,
      'content': content,
      'targetId': targetId,
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
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}
