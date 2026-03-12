import 'package:cloud_firestore/cloud_firestore.dart';
import 'location.dart';

class Post {
  final String id;
  final String? userName;
  final String? userEmail;
  final String? userId;
  final bool anonymous;
  final String content;
  final PostType type;
  final PostCategory category;
  final DateTime timestamp;
  ModerationStatus moderationStatus;
  int likeCount;
  final List<String> likedBy;
  final Map<String, List<String>> reactions;
  final List<String> imageUrls;
  final String? videoUrl;
  final Location? taggedLocation;
  final List<String> taggedUsers;
  final String? routeId;
  final DateTime? expiresAt;

  Post({
    required this.id,
    this.userName,
    this.userEmail,
    this.userId,
    this.anonymous = false,
    required this.content,
    required this.type,
    required this.category,
    required this.timestamp,
    this.moderationStatus = ModerationStatus.approved,
    this.likeCount = 0,
    this.likedBy = const [],
    this.reactions = const {},
    this.imageUrls = const [],
    this.videoUrl,
    this.taggedLocation,
    this.taggedUsers = const [],
    this.routeId,
    this.expiresAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userName': userName,
      'userEmail': userEmail,
      'userId': userId,
      'anonymous': anonymous,
      'content': content,
      'type': type.name,
      'category': category.name,
      'timestamp': timestamp.toIso8601String(),
      'moderationStatus': moderationStatus.name,
      'likeCount': likeCount,
      'likedBy': likedBy,
      'reactions': reactions,
      'imageUrls': imageUrls,
      'videoUrl': videoUrl,
      'taggedLocation': taggedLocation?.toJson(),
      'taggedUsers': taggedUsers,
      'routeId': routeId,
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'],
      userName: json['userName'],
      userEmail: json['userEmail'],
      userId: json['userId'],
      anonymous: json['anonymous'] ?? false,
      content: json['content'],
      type: PostType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => PostType.text,
      ),
      category: PostCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => PostCategory.discussion,
      ),
      timestamp: (json['timestamp'] as Timestamp).toDate(),
      moderationStatus: ModerationStatus.values.firstWhere(
        (e) => e.name == json['moderationStatus'],
        orElse: () => ModerationStatus.approved,
      ),
      likeCount: json['likeCount'] ?? 0,
      likedBy: List<String>.from(json['likedBy'] ?? []),
      reactions: Map<String, List<String>>.from(
        json['reactions']?.map(
              (k, v) => MapEntry(k, List<String>.from(v ?? [])),
            ) ??
            {},
      ),
      imageUrls: List<String>.from(json['imageUrls'] ?? []),
      videoUrl: json['videoUrl'],
      taggedLocation:
          json['taggedLocation'] != null
              ? Location.fromJson(json['taggedLocation'])
              : null,
      taggedUsers: List<String>.from(json['taggedUsers'] ?? []),
      routeId: json['routeId'],
      expiresAt: json['expiresAt'] != null
          ? (json['expiresAt'] is Timestamp
              ? (json['expiresAt'] as Timestamp).toDate()
              : DateTime.tryParse(json['expiresAt'] as String))
          : null,
    );
  }
}

enum PostType { text, image, video, poll }

enum PostCategory {
  discussion,
  live,
  underReview,
  routeUpdate,
  delayReport,
  safetyAlert,
  recommendation,
}

enum ModerationStatus { pending, approved, rejected }
