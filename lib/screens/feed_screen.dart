import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:video_player/video_player.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../services/post_actions_service.dart';
import '../security/security_manager.dart';
import '../widgets/create_post_dialog.dart';
import '../models/notification.dart';
import '../services/notifications_service.dart';
import '../screens/notifications_screen.dart';

class FeedScreen extends StatefulWidget {
  final List<Post> posts;
  final Function(Post) onPostCreated;
  final String currentUserName;

  const FeedScreen({
    super.key,
    required this.posts,
    required this.onPostCreated,
    required this.currentUserName,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  Map<String, bool> likedPosts = {};
  Map<String, List<Comment>> postComments = {};
  Map<String, Map<String, List<String>>> emojiReactions =
      {}; // postId -> emoji -> userIds
  Map<String, bool> bookmarkedPosts = {};
  String searchQuery = '';

  Map<String, VideoPlayerController> videoControllers = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget buildComment(Comment comment, {int depth = 0}) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${comment.userName}: ${comment.content}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (comment.replies.isNotEmpty)
            ...comment.replies.map(
              (reply) => buildComment(reply, depth: depth + 1),
            ),
        ],
      ),
    );
  }

  Widget buildPostItem(Post post) {
    String displayName =
        post.anonymous
            ? 'Anonymous'
            : (post.userName ?? post.userEmail ?? 'User');
    String initials =
        post.anonymous
            ? 'A'
            : (post.userName != null && post.userName!.isNotEmpty
                ? post.userName![0].toUpperCase()
                : (post.userEmail != null && post.userEmail!.isNotEmpty
                    ? post.userEmail![0].toUpperCase()
                    : 'U'));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.blue.shade100,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${post.timestamp.hour}:${post.timestamp.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        post.category == PostCategory.live
                            ? Colors.green.shade100
                            : post.category == PostCategory.discussion
                            ? Colors.blue.shade100
                            : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    switch (post.category) {
                      PostCategory.discussion => 'Discussion',
                      PostCategory.live => 'Questions',
                      PostCategory.underReview => 'Tips',
                      PostCategory.routeUpdate => 'Route Update',
                      PostCategory.delayReport => 'Delay Report',
                      PostCategory.safetyAlert => 'Safety Alert',
                      PostCategory.recommendation => 'Recommendation',
                      _ => 'Unknown',
                    },
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Linkify(
              onOpen: (link) async {
                await SecurityManager.openLink(context, link.url);
              },
              text: post.content,
              style: const TextStyle(fontSize: 16),
              linkStyle: const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
            ),
            if (post.imageUrls.isNotEmpty) const SizedBox(height: 8),
            if (post.imageUrls.isNotEmpty)
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: post.imageUrls.length,
                  itemBuilder:
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Image.network(
                          post.imageUrls[index],
                          width: 200,
                          height: 200,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const CircularProgressIndicator();
                          },
                          errorBuilder:
                              (context, error, stackTrace) =>
                                  const Icon(Icons.error),
                        ),
                      ),
                ),
              ),
            if (post.videoUrl != null) const SizedBox(height: 8),
            if (post.videoUrl != null)
              FutureBuilder<VideoPlayerController>(
                future: _initializeVideoController(post.videoUrl!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    final controller = snapshot.data!;
                    return AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    );
                  } else {
                    return Container(
                      height: 200,
                      color: Colors.black,
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    );
                  }
                },
              ),
            if (post.taggedLocation != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Location: ${post.taggedLocation!.name}',
                  style: const TextStyle(fontSize: 14, color: Colors.blue),
                ),
              ),

            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      PostActionsService.likePost(post.id, likedPosts);
                    });
                    if (post.userName != null &&
                        post.userName != widget.currentUserName) {
                      NotificationsService.addNotification(
                        NotificationModel(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          userId: post.userName!,
                          type: 'like',
                          postId: post.id,
                          fromUserName: widget.currentUserName,
                          timestamp: DateTime.now(),
                          message: '${widget.currentUserName} liked your post.',
                        ),
                      );
                    }
                  },
                  icon: Icon(
                    (likedPosts[post.id] ?? false)
                        ? Icons.thumb_up
                        : Icons.thumb_up_alt_outlined,
                    size: 20,
                    color: (likedPosts[post.id] ?? false) ? Colors.blue : null,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    _showCommentDialog(post.id);
                  },
                  icon: const Icon(Icons.comment_outlined, size: 20),
                ),
                IconButton(
                  onPressed: () {
                    _showEmojiPicker(post.id);
                  },
                  icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      bookmarkedPosts[post.id] =
                          !(bookmarkedPosts[post.id] ?? false);
                    });
                  },
                  icon: Icon(
                    (bookmarkedPosts[post.id] ?? false)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    size: 20,
                    color:
                        (bookmarkedPosts[post.id] ?? false)
                            ? Colors.blue
                            : null,
                  ),
                ),

                IconButton(
                  onPressed: () {
                    _reportPost(post);
                  },
                  icon: const Icon(
                    Icons.report_outlined,
                    size: 20,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            // Display emoji reactions
            if (emojiReactions[post.id]?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children:
                      emojiReactions[post.id]!.entries.map((entry) {
                        if (entry.value.isEmpty) return const SizedBox.shrink();
                        return Text(
                          '${entry.key} ${entry.value.length}',
                          style: const TextStyle(fontSize: 14),
                        );
                      }).toList(),
                ),
              ),
            if (postComments[post.id]?.isNotEmpty ?? false)
              ...postComments[post.id]!.map((comment) => buildComment(comment)),
          ],
        ),
      ),
    );
  }

  void _showCreatePostDialog() {
    showDialog(
      context: context,
      builder:
          (context) => CreatePostDialog(
            onPostCreated: widget.onPostCreated,
            currentUserName: widget.currentUserName,
          ),
    );
  }

  void _showCommentDialog(String postId) {
    TextEditingController commentController = TextEditingController();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Comment'),
            content: TextField(
              controller: commentController,
              decoration: const InputDecoration(hintText: 'Enter your comment'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (commentController.text.isNotEmpty) {
                    final comment = Comment(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      postId: postId,
                      userId: 'currentUserId', // Replace with actual user
                      userName: widget.currentUserName,
                      content: commentController.text,
                      timestamp: DateTime.now(),
                    );
                    setState(() {
                      PostActionsService.addComment(
                        postId,
                        comment,
                        postComments,
                      );
                    });
                    final post = widget.posts.firstWhere((p) => p.id == postId);
                    if (post.userName != null &&
                        post.userName != widget.currentUserName) {
                      NotificationsService.addNotification(
                        NotificationModel(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          userId: post.userName!,
                          type: 'comment',
                          postId: postId,
                          fromUserName: widget.currentUserName,
                          timestamp: DateTime.now(),
                          message:
                              '${widget.currentUserName} commented on your post.',
                        ),
                      );
                    }
                  }
                  Navigator.pop(context);
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }

  void _reportPost(Post post) {
    _showReportDialog(post);
  }

  void _showReportDialog(Post post) {
    String? selectedReason;
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Report Post'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Why are you reporting this post?'),
                const SizedBox(height: 16),
                ...[
                  'Spam',
                  'Inappropriate Content',
                  'Harassment',
                  'Misinformation',
                  'Other',
                ].map(
                  (reason) => RadioListTile<String>(
                    title: Text(reason),
                    value: reason,
                    groupValue: selectedReason,
                    onChanged: (value) {
                      selectedReason = value;
                      (context as Element).markNeedsBuild();
                    },
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (selectedReason != null) {
                    PostActionsService.reportPost(
                      post,
                      selectedReason!,
                      'currentUser@example.com',
                    ); // Replace with actual user
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Post reported for moderation'),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Report'),
              ),
            ],
          ),
    );
  }

  void _showEmojiPicker(String postId) {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '😡'];
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('React with Emoji'),
            content: Wrap(
              spacing: 8,
              children:
                  emojis.map((emoji) {
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          emojiReactions[postId] ??= {};
                          emojiReactions[postId]![emoji] ??= [];
                          if (emojiReactions[postId]![emoji]!.contains(
                            'currentUserId',
                          )) {
                            emojiReactions[postId]![emoji]!.remove(
                              'currentUserId',
                            );
                          } else {
                            emojiReactions[postId]![emoji]!.add(
                              'currentUserId',
                            );
                          }
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    );
                  }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );
  }

  Future<VideoPlayerController> _initializeVideoController(String url) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    await controller.initialize();
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final approvedPosts =
        widget.posts
            .where((p) => p.moderationStatus == ModerationStatus.approved)
            .toList();
    final filteredPosts =
        approvedPosts
            .where(
              (p) =>
                  p.content.toLowerCase().contains(searchQuery.toLowerCase()),
            )
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Feed'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => NotificationsScreen(
                          currentUserName: widget.currentUserName,
                        ),
                  ),
                ),
          ),
        ],
      ),
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreatePostDialog,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search posts...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: filteredPosts.length,
                itemBuilder:
                    (context, index) => buildPostItem(filteredPosts[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
