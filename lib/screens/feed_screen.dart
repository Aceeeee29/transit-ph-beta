import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:video_player/video_player.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../services/post_actions_service.dart';
import '../services/post_service.dart';
import '../security/security_manager.dart';
import '../widgets/create_post_dialog.dart';
import '../models/notification.dart';
import '../services/notifications_service.dart';
import '../screens/notifications_screen.dart';
import '../screens/post_search_screen.dart';

class FeedScreen extends StatefulWidget {
  final List<Post> posts;
  final Function(Post) onPostCreated;
  final String currentUserName;
  final String currentUserId;

  const FeedScreen({
    super.key,
    required this.posts,
    required this.onPostCreated,
    required this.currentUserName,
    required this.currentUserId,
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
  Set<String> _loadedPostIds = {};

  Map<String, VideoPlayerController> videoControllers = {};

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
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadComments(String postId) async {
    final comments = await PostService.getComments(postId);
    setState(() {
      postComments[postId] = comments;
      _loadedPostIds.add(postId);
    });
  }

  Widget buildComment(Comment comment, {int depth = 0}) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0, top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: depth == 0 ? _surfaceAlt : _accentSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: _accentSoft,
                  child: Text(
                    comment.userName.isNotEmpty
                        ? comment.userName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.userName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        comment.content,
                        style: const TextStyle(
                          fontSize: 13,
                          color: _textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    _showCommentDialog(comment.postId, parentComment: comment);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _border),
                    ),
                    child: const Icon(
                      Icons.reply_rounded,
                      size: 13,
                      color: _textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (comment.replies.isNotEmpty)
            ...comment.replies.map(
              (reply) => buildComment(reply, depth: depth + 1),
            ),
        ],
      ),
    );
  }

  // ─── Category helpers ───────────────────────────────────────────────────────
  Color _categoryColor(PostCategory cat) => switch (cat) {
    PostCategory.safetyAlert => const Color(0xFFE05C6A),
    PostCategory.delayReport => const Color(0xFFE89A3C),
    PostCategory.live => const Color(0xFF3EC97A),
    PostCategory.recommendation => const Color(0xFF9B7FE8),
    PostCategory.routeUpdate => const Color(0xFF3EC9D6),
    _ => _accent,
  };

  String _categoryLabel(PostCategory cat) => switch (cat) {
    PostCategory.discussion => 'Discussion',
    PostCategory.live => 'Questions',
    PostCategory.underReview => 'Tips',
    PostCategory.routeUpdate => 'Route Update',
    PostCategory.delayReport => 'Delay Report',
    PostCategory.safetyAlert => 'Safety Alert',
    PostCategory.recommendation => 'Recommendation',
    _ => 'Unknown',
  };

  IconData _categoryIcon(PostCategory cat) => switch (cat) {
    PostCategory.discussion => Icons.forum_outlined,
    PostCategory.live => Icons.help_outline,
    PostCategory.underReview => Icons.lightbulb_outline,
    PostCategory.routeUpdate => Icons.alt_route,
    PostCategory.delayReport => Icons.schedule,
    PostCategory.safetyAlert => Icons.warning_amber_outlined,
    PostCategory.recommendation => Icons.thumb_up_outlined,
    _ => Icons.label_outline,
  };

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

    final catColor = _categoryColor(post.category);
    final isLiked = likedPosts[post.id] ?? false;
    final isBookmarked = bookmarkedPosts[post.id] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Post header ──────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: post.anonymous ? _surfaceAlt : _accentSoft,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time,
                            size: 11,
                            color: _textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${post.timestamp.hour}:${post.timestamp.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Category badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: catColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: catColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _categoryIcon(post.category),
                        size: 12,
                        color: catColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _categoryLabel(post.category),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: catColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ─── Post content ─────────────────────────────────────────
            Linkify(
              onOpen: (link) async {
                await SecurityManager.openLink(context, link.url);
              },
              text: post.content,
              style: const TextStyle(
                fontSize: 15,
                color: _textPrimary,
                height: 1.5,
              ),
              linkStyle: const TextStyle(
                color: _accent,
                decoration: TextDecoration.underline,
              ),
            ),

            // ─── Images ───────────────────────────────────────────────
            if (post.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: post.imageUrls.length,
                    itemBuilder:
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              post.imageUrls[index],
                              width: 200,
                              height: 200,
                              fit: BoxFit.cover,
                              loadingBuilder: (
                                context,
                                child,
                                loadingProgress,
                              ) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  width: 200,
                                  height: 200,
                                  color: _surfaceAlt,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: _accent,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder:
                                  (context, error, stackTrace) => Container(
                                    width: 200,
                                    height: 200,
                                    color: _surfaceAlt,
                                    child: const Icon(
                                      Icons.broken_image_outlined,
                                      color: _textSecondary,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                  ),
                ),
              ),
            ],

            // ─── Video ────────────────────────────────────────────────
            if (post.videoUrl != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FutureBuilder<VideoPlayerController>(
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
                        decoration: BoxDecoration(
                          color: _surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: _accent,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],

            // ─── Tagged location ──────────────────────────────────────
            if (post.taggedLocation != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _accent.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 13,
                      color: _accent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      post.taggedLocation!.name,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            Divider(color: _border, height: 1),
            const SizedBox(height: 8),

            // ─── Action bar ───────────────────────────────────────────
            Row(
              children: [
                _actionButton(
                  icon: isLiked ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                  color: isLiked ? _accent : _textSecondary,
                  active: isLiked,
                  onTap: () async {
                    await PostActionsService.likePost(
                      post.id,
                      widget.currentUserId,
                    );
                    setState(() {
                      likedPosts[post.id] = !isLiked;
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
                ),
                const SizedBox(width: 6),
                _actionButton(
                  icon: Icons.comment_outlined,
                  color: _textSecondary,
                  onTap: () async {
                    if (!_loadedPostIds.contains(post.id)) {
                      await _loadComments(post.id);
                    }
                    _showCommentDialog(post.id);
                  },
                ),
                const SizedBox(width: 6),
                _actionButton(
                  icon: Icons.emoji_emotions_outlined,
                  color: _textSecondary,
                  onTap: () {
                    _showEmojiPicker(post.id);
                  },
                ),
                const SizedBox(width: 6),
                _actionButton(
                  icon: isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                  color: isBookmarked ? _accent : _textSecondary,
                  active: isBookmarked,
                  onTap: () async {
                    await PostActionsService.bookmarkPost(
                      post.id,
                      widget.currentUserId,
                    );
                    setState(() {
                      bookmarkedPosts[post.id] = !isBookmarked;
                    });
                  },
                ),
                const Spacer(),
                _actionButton(
                  icon: Icons.flag_outlined,
                  color: _danger,
                  onTap: () {
                    _reportPost(post);
                  },
                ),
              ],
            ),

            // ─── Emoji reactions ──────────────────────────────────────
            if (emojiReactions[post.id]?.isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    emojiReactions[post.id]!.entries.map((entry) {
                      if (entry.value.isEmpty) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _surfaceAlt,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _border),
                        ),
                        child: Text(
                          '${entry.key} ${entry.value.length}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      );
                    }).toList(),
              ),
            ],

            // ─── Comments ─────────────────────────────────────────────
            if (postComments[post.id]?.isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              ...postComments[post.id]!.map((comment) => buildComment(comment)),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Reusable action button ─────────────────────────────────────────────────
  Widget _actionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.1) : _surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: active ? color.withOpacity(0.3) : _border),
        ),
        child: Icon(icon, size: 17, color: color),
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
            currentUserId: widget.currentUserId,
          ),
    );
  }

  void _showCommentDialog(String postId, {Comment? parentComment}) {
    TextEditingController commentController = TextEditingController();
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.08),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      border: Border(
                        bottom: BorderSide(color: _border, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _accentSoft,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.comment_outlined,
                            color: _accent,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          parentComment != null
                              ? 'Reply to ${parentComment.userName}'
                              : 'Add Comment',
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                      ),
                      child: TextField(
                        controller: commentController,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 14,
                        ),
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Write your comment...',
                          hintStyle: TextStyle(
                            color: _textSecondary,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(14),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: _surface,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(color: _border),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: () async {
                              if (commentController.text.isNotEmpty) {
                                final comment = Comment(
                                  id:
                                      DateTime.now().millisecondsSinceEpoch
                                          .toString(),
                                  postId: postId,
                                  userId: widget.currentUserId,
                                  userName: widget.currentUserName,
                                  content: commentController.text,
                                  parentId: parentComment?.id,
                                  timestamp: DateTime.now(),
                                );
                                await PostActionsService.addComment(comment);
                                await _loadComments(postId);
                                final post = widget.posts.firstWhere(
                                  (p) => p.id == postId,
                                );
                                if (post.userName != null &&
                                    post.userName != widget.currentUserName) {
                                  NotificationsService.addNotification(
                                    NotificationModel(
                                      id:
                                          DateTime.now().millisecondsSinceEpoch
                                              .toString(),
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
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF4A7CE0),
                                    Color(0xFF6A9EFF),
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: [
                                  BoxShadow(
                                    color: _accent.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'Post Comment',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.08),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      border: Border(
                        bottom: BorderSide(color: _border, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _danger.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.flag_outlined,
                            color: _danger,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Report Post',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Why are you reporting this post?',
                          style: TextStyle(color: _textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        StatefulBuilder(
                          builder: (context, setDialogState) {
                            return Column(
                              children:
                                  [
                                        'Spam',
                                        'Inappropriate Content',
                                        'Harassment',
                                        'Misinformation',
                                        'Other',
                                      ]
                                      .map(
                                        (reason) => GestureDetector(
                                          onTap: () {
                                            setDialogState(
                                              () => selectedReason = reason,
                                            );
                                          },
                                          child: Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  selectedReason == reason
                                                      ? _danger.withOpacity(
                                                        0.08,
                                                      )
                                                      : _surface,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color:
                                                    selectedReason == reason
                                                        ? _danger.withOpacity(
                                                          0.4,
                                                        )
                                                        : _border,
                                                width:
                                                    selectedReason == reason
                                                        ? 1.5
                                                        : 1,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 16,
                                                  height: 16,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color:
                                                          selectedReason ==
                                                                  reason
                                                              ? _danger
                                                              : _border,
                                                      width: 2,
                                                    ),
                                                    color:
                                                        selectedReason == reason
                                                            ? _danger
                                                            : Colors
                                                                .transparent,
                                                  ),
                                                  child:
                                                      selectedReason == reason
                                                          ? const Icon(
                                                            Icons.check,
                                                            size: 10,
                                                            color: Colors.white,
                                                          )
                                                          : null,
                                                ),
                                                const SizedBox(width: 10),
                                                Text(
                                                  reason,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight:
                                                        selectedReason == reason
                                                            ? FontWeight.w600
                                                            : FontWeight.w400,
                                                    color:
                                                        selectedReason == reason
                                                            ? _textPrimary
                                                            : _textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: _surface,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(color: _border),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: () {
                              if (selectedReason != null) {
                                PostActionsService.reportPost(
                                  post,
                                  selectedReason!,
                                  'currentUser@example.com',
                                ); // Replace with actual user
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Post reported for moderation',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: _danger,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: [
                                  BoxShadow(
                                    color: _danger.withOpacity(0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.flag_outlined,
                                    color: Colors.white,
                                    size: 15,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Submit Report',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _showEmojiPicker(String postId) {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '😡'];
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.08),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      border: Border(
                        bottom: BorderSide(color: _border, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _accentSoft,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.emoji_emotions_outlined,
                            color: _accent,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'React to Post',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children:
                          emojis.map((emoji) {
                            final isActive =
                                emojiReactions[postId]?[emoji]?.contains(
                                  widget.currentUserId,
                                ) ??
                                false;
                            return GestureDetector(
                              onTap: () async {
                                final contains =
                                    emojiReactions[postId]?[emoji]?.contains(
                                      widget.currentUserId,
                                    ) ??
                                    false;
                                if (contains) {
                                  await PostActionsService.removeReaction(
                                    postId,
                                    emoji,
                                    widget.currentUserId,
                                  );
                                } else {
                                  await PostActionsService.addReaction(
                                    postId,
                                    emoji,
                                    widget.currentUserId,
                                  );
                                }
                                setState(() {
                                  emojiReactions[postId] ??= {};
                                  emojiReactions[postId]![emoji] ??= [];
                                  if (contains) {
                                    emojiReactions[postId]![emoji]!.remove(
                                      widget.currentUserId,
                                    );
                                  } else {
                                    emojiReactions[postId]![emoji]!.add(
                                      widget.currentUserId,
                                    );
                                  }
                                });
                                Navigator.pop(context);
                              },
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: isActive ? _accentSoft : _surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color:
                                        isActive
                                            ? _accent.withOpacity(0.4)
                                            : _border,
                                    width: isActive ? 1.5 : 1,
                                  ),
                                  boxShadow:
                                      isActive
                                          ? [
                                            BoxShadow(
                                              color: _accent.withOpacity(0.12),
                                              blurRadius: 8,
                                            ),
                                          ]
                                          : null,
                                ),
                                child: Center(
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 28),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: double.infinity,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: _border),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

    return Scaffold(
      backgroundColor: _bg,
      // ─── AppBar ────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
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
                Icons.people_outline_rounded,
                color: _accent,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Community Feed',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          GestureDetector(
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => PostSearchScreen(posts: approvedPosts),
                  ),
                ),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: const Icon(
                Icons.search_rounded,
                color: _textSecondary,
                size: 18,
              ),
            ),
          ),
          GestureDetector(
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => NotificationsScreen(
                          currentUserId: widget.currentUserId,
                        ),
                  ),
                ),
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: const Icon(
                Icons.notifications_outlined,
                color: _textSecondary,
                size: 18,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),

      // ─── FAB ────────────────────────────────────────────────────────────
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _showCreatePostDialog,
            borderRadius: BorderRadius.circular(16),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_outlined, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'New Post',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      // ─── Body ────────────────────────────────────────────────────────────
      body:
          approvedPosts.isEmpty
              ? Center(
                child: Column(
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
                        Icons.forum_outlined,
                        size: 36,
                        color: _textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No posts yet',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Be the first to post in the community!',
                      style: TextStyle(fontSize: 14, color: _textSecondary),
                    ),
                  ],
                ),
              )
              : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: approvedPosts.length,
                itemBuilder:
                    (context, index) => buildPostItem(approvedPosts[index]),
              ),
    );
  }
}
