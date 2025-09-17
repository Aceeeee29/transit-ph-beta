class Post {
  final String id;
  final String? userName;
  final String? userEmail;
  final bool anonymous;
  final String content;
  final PostType type;
  final PostCategory category;
  final DateTime timestamp;
  int likeCount;

  Post({
    required this.id,
    this.userName,
    this.userEmail,
    this.anonymous = false,
    required this.content,
    required this.type,
    required this.category,
    required this.timestamp,
    this.likeCount = 0,
  });
}

enum PostType { text, image, poll }

enum PostCategory { discussion, live, underReview }
