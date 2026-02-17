import 'location.dart';

class Post {
  final String id;
  final String? userName;
  final String? userEmail;
  final bool anonymous;
  final String content;
  final PostType type;
  final PostCategory category;
  final DateTime timestamp;
  ModerationStatus moderationStatus;
  int likeCount;
  final List<String> imageUrls;
  final String? videoUrl;
  final Location? taggedLocation;
  final List<String> taggedUsers;
  final String? routeId;

  Post({
    required this.id,
    this.userName,
    this.userEmail,
    this.anonymous = false,
    required this.content,
    required this.type,
    required this.category,
    required this.timestamp,
    this.moderationStatus = ModerationStatus.approved,
    this.likeCount = 0,
    this.imageUrls = const [],
    this.videoUrl,
    this.taggedLocation,
    this.taggedUsers = const [],
    this.routeId,
  });
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
