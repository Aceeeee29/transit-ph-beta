import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String postId;
  final String userId;
  final String userName;
  final String content;
  final String? parentId;
  final List<Comment> replies;
  final DateTime timestamp;

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.userName,
    required this.content,
    this.parentId,
    this.replies = const [],
    required this.timestamp,
  });

  // Add reply
  Comment addReply(Comment reply) {
    return Comment(
      id: id,
      postId: postId,
      userId: userId,
      userName: userName,
      content: content,
      parentId: parentId,
      replies: [...replies, reply],
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'postId': postId,
      'userId': userId,
      'userName': userName,
      'content': content,
      'parentId': parentId,
    };
  }

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'],
      postId: json['postId'],
      userId: json['userId'],
      userName: json['userName'],
      content: json['content'],
      parentId: json['parentId'],
      replies:
          (json['replies'] as List?)
              ?.map((r) => Comment.fromJson(r))
              .toList() ??
          [],
      timestamp: (json['timestamp'] as Timestamp).toDate(),
    );
  }
}
