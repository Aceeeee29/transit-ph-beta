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

class FeedScreen extends StatefulWidget {
  final List<Post> posts;
  final Function(Post) onPostCreated;
  final Function(Post)? onPostDeleted;
  final String currentUserName;
  final String currentUserId;
  final Future<void> Function()? onRefresh;

  const FeedScreen({
    super.key,
    required this.posts,
    required this.onPostCreated,
    this.onPostDeleted,
    required this.currentUserName,
    required this.currentUserId,
    this.onRefresh,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _postVotes = <String, bool?>{};
  final _upvoteCounts = <String, int>{};
  final _downvoteCounts = <String, int>{};
  final _postComments = <String, List<Comment>>{};
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

  Future<void> _deletePost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Post'),
        content: const Text(
          'Are you sure you want to delete this post? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await PostService.deletePost(post.id);
        widget.onPostDeleted?.call(post);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete post. Please try again.')),
          );
        }
      }
    }
  }

  bool? _initialVoteForPost(Post post) {
    if (post.upvotedBy.contains(widget.currentUserId)) return true;
    if (post.downvotedBy.contains(widget.currentUserId)) return false;
    return null;
  }

  int _effectiveUpvoteCount(Post post) => _upvoteCounts[post.id] ?? post.upvoteCount;

  int _effectiveDownvoteCount(Post post) =>
      _downvoteCounts[post.id] ?? post.downvoteCount;

  bool? _effectiveVote(Post post) => _postVotes[post.id] ?? _initialVoteForPost(post);

  void _applyLocalVoteState(Post post, bool? previousVote, bool? nextVote) {
    var upvotes = _effectiveUpvoteCount(post);
    var downvotes = _effectiveDownvoteCount(post);

    if (previousVote == true) {
      upvotes = (upvotes - 1).clamp(0, 1 << 31);
    } else if (previousVote == false) {
      downvotes = (downvotes - 1).clamp(0, 1 << 31);
    }

    if (nextVote == true) {
      upvotes += 1;
    } else if (nextVote == false) {
      downvotes += 1;
    }

    _postVotes[post.id] = nextVote;
    _upvoteCounts[post.id] = upvotes;
    _downvoteCounts[post.id] = downvotes;
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
      isUpvoted: _effectiveVote(post) == true,
      isDownvoted: _effectiveVote(post) == false,
      upvoteCount: _effectiveUpvoteCount(post),
      downvoteCount: _effectiveDownvoteCount(post),
      currentUserId: widget.currentUserId,
      currentUserName: widget.currentUserName,
      onUpvoteTapped: () async {
        final previousVote = _effectiveVote(post);
        final nextVote = await PostActionsService.votePost(
          post.id,
          widget.currentUserId,
          isUpvote: true,
        );
        if (!mounted) return;
        setState(() => _applyLocalVoteState(post, previousVote, nextVote));
        if (nextVote == true &&
            post.userId != null &&
            post.userId != widget.currentUserId) {
          NotificationsService.addNotification(
            NotificationModel(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              userId: post.userId!,
              type: 'upvote',
              postId: post.id,
              fromUserName: widget.currentUserName,
              timestamp: DateTime.now(),
              message: '${widget.currentUserName} upvoted your post.',
            ),
          );
        }
      },
      onDownvoteTapped: () async {
        final previousVote = _effectiveVote(post);
        final nextVote = await PostActionsService.votePost(
          post.id,
          widget.currentUserId,
          isUpvote: false,
        );
        if (!mounted) return;
        setState(() => _applyLocalVoteState(post, previousVote, nextVote));
        if (nextVote == false &&
            post.userId != null &&
            post.userId != widget.currentUserId) {
          NotificationsService.addNotification(
            NotificationModel(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              userId: post.userId!,
              type: 'downvote',
              postId: post.id,
              fromUserName: widget.currentUserName,
              timestamp: DateTime.now(),
              message: '${widget.currentUserName} downvoted your post.',
            ),
          );
        }
      },
      onCommentTapped: () async {
        if (!_loadedPostIds.contains(post.id)) await _loadComments(post.id);
        _showCommentSheet(post.id, post);
      },
      onReportTapped: () => _showReportDialog(post),
      onDeleteTapped: post.userId == widget.currentUserId
          ? () => _deletePost(post)
          : null,
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
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_outlined,
                  color: FeedColors.textPrimary,
                  size: 20,
                ),
                Positioned(
                  right: -6,
                  top: -6,
                  child: StreamBuilder<int>(
                    stream: NotificationsService.unreadCountStream(
                      widget.currentUserId,
                    ),
                    builder: (context, snapshot) {
                      final unread = snapshot.data ?? 0;
                      if (unread <= 0) return const SizedBox.shrink();

                      final label = unread > 99 ? '99+' : unread.toString();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: FeedColors.danger,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: FeedColors.surface,
                            width: 1.5,
                          ),
                        ),
                        constraints: const BoxConstraints(minWidth: 16),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
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
