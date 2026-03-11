import 'package:flutter/material.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../services/post_actions_service.dart';
import '../services/post_service.dart';
import '../widgets/create_post_dialog.dart';
import '../models/notification.dart';
import '../services/notifications_service.dart';
import '../screens/notifications_screen.dart';
import '../screens/post_search_screen.dart';
import '../widgets/feed/feed_colors.dart';
import '../widgets/feed/feed_post_card.dart';
import '../screens/comments_screen.dart';
import '../widgets/feed/report_post_dialog.dart';
import '../widgets/feed/emoji_picker_dialog.dart';

class FeedScreen extends StatefulWidget {
  final List<Post> posts;
  final Function(Post) onPostCreated;
  final String currentUserName;
  final String currentUserId;
  final Future<void> Function()? onRefresh;

  const FeedScreen({
    super.key,
    required this.posts,
    required this.onPostCreated,
    required this.currentUserName,
    required this.currentUserId,
    this.onRefresh,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _likedPosts = <String, bool>{};
  final _postComments = <String, List<Comment>>{};
  final _emojiReactions = <String, Map<String, List<String>>>{};
  final _bookmarkedPosts = <String, bool>{};
  final _loadedPostIds = <String>{};

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
      _postComments[postId] = comments;
      _loadedPostIds.add(postId);
    });
  }

  void _showCreatePostDialog() {
    showDialog(
      context: context,
      builder: (_) => CreatePostDialog(
        onPostCreated: widget.onPostCreated,
        currentUserName: widget.currentUserName,
        currentUserId: widget.currentUserId,
      ),
    );
  }

  void _showCommentSheet(String postId, Post post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommentsScreen(
          postId: postId,
          post: post,
          initialComments: _postComments[postId] ?? [],
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          onCommentPosted: () => _loadComments(postId),
        ),
      ),
    );
  }

  void _showReportDialog(Post post) {
    showDialog(
      context: context,
      builder: (_) => ReportPostDialog(post: post),
    );
  }

  void _showEmojiPicker(String postId) {
    showDialog(
      context: context,
      builder: (_) => EmojiPickerDialog(
        postId: postId,
        currentUserId: widget.currentUserId,
        reactions: _emojiReactions[postId] ?? {},
        onReactionToggled: (emoji, removed) {
          setState(() {
            _emojiReactions[postId] ??= {};
            _emojiReactions[postId]![emoji] ??= [];
            if (removed) {
              _emojiReactions[postId]![emoji]!.remove(widget.currentUserId);
            } else {
              _emojiReactions[postId]![emoji]!.add(widget.currentUserId);
            }
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final approvedPosts = widget.posts
        .where((p) => p.moderationStatus == ModerationStatus.approved)
        .toList();

    return Scaffold(
      backgroundColor: FeedColors.bg,
      appBar: _buildAppBar(approvedPosts),
      floatingActionButton: _buildFab(),
      body: approvedPosts.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: widget.onRefresh ?? () async {},
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: approvedPosts.length,
                itemBuilder: (context, index) =>
                    _buildPostCard(approvedPosts[index]),
              ),
            ),
    );
  }

  Widget _buildPostCard(Post post) {
    return FeedPostCard(
      post: post,
      isLiked: _likedPosts[post.id] ?? false,
      isBookmarked: _bookmarkedPosts[post.id] ?? false,
      reactions: _emojiReactions[post.id] ?? {},
      currentUserId: widget.currentUserId,
      currentUserName: widget.currentUserName,
      onLikeTapped: () async {
        await PostActionsService.likePost(post.id, widget.currentUserId);
        setState(() {
          _likedPosts[post.id] = !(_likedPosts[post.id] ?? false);
        });
        if (post.userId != null && post.userId != widget.currentUserId) {
          NotificationsService.addNotification(NotificationModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            userId: post.userId!,
            type: 'like',
            postId: post.id,
            fromUserName: widget.currentUserName,
            timestamp: DateTime.now(),
            message: '${widget.currentUserName} liked your post.',
          ));
        }
      },
      onCommentTapped: () async {
        if (!_loadedPostIds.contains(post.id)) await _loadComments(post.id);
        _showCommentSheet(post.id, post);
      },
      onReactTapped: () => _showEmojiPicker(post.id),
      onBookmarkTapped: () async {
        await PostActionsService.bookmarkPost(post.id, widget.currentUserId);
        setState(() {
          _bookmarkedPosts[post.id] = !(_bookmarkedPosts[post.id] ?? false);
        });
      },
      onReportTapped: () => _showReportDialog(post),
    );
  }

  AppBar _buildAppBar(List<Post> approvedPosts) {
    return AppBar(
      backgroundColor: FeedColors.bg,
      elevation: 0,
      centerTitle: false,
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: FeedColors.accentSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: FeedColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_rounded, color: FeedColors.accent, size: 16),
            SizedBox(width: 8),
            Text(
              'Community Feed',
              style: TextStyle(
                color: FeedColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
      actions: [
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostSearchScreen(posts: approvedPosts),
            ),
          ),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: FeedColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: FeedColors.border),
            ),
            child: const Icon(
              Icons.search,
              color: FeedColors.textPrimary,
              size: 20,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NotificationsScreen(
                currentUserId: widget.currentUserId,
              ),
            ),
          ),
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: FeedColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: FeedColors.border),
            ),
            child: const Icon(
              Icons.notifications_outlined,
              color: FeedColors.textPrimary,
              size: 20,
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: FeedColors.border, height: 1),
      ),
    );
  }

  Widget _buildFab() {
    return FloatingActionButton.extended(
      onPressed: _showCreatePostDialog,
      backgroundColor: Colors.transparent,
      elevation: 0,
      label: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: FeedColors.accent.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: const Row(
          children: [
            Icon(Icons.edit_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              'New Post',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: FeedColors.accentSoft,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: FeedColors.border),
            ),
            child: const Icon(
              Icons.forum_outlined,
              color: FeedColors.accent,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No posts yet',
            style: TextStyle(
              color: FeedColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Be the first to share something\nwith the community.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: FeedColors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
