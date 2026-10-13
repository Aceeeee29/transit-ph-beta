import 'package:flutter/material.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../services/post_actions_service.dart';
import '../services/moderation_service.dart';
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
import '../widgets/translated_text.dart';

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
  final _pendingVotePostIds = <String>{};
  final _postComments = <String, List<Comment>>{};
  final _loadedPostIds = <String>{};

  @override
  void initState() {
    super.initState();
    ModerationService.isStaffNotifier.addListener(_onStaffChanged);
  }

  @override
  void dispose() {
    ModerationService.isStaffNotifier.removeListener(_onStaffChanged);
    super.dispose();
  }

  // Staff get a "Keep in feed for…" action on every post.
  void _onStaffChanged() {
    if (mounted) setState(() {});
  }

  /// Moderators: choose how long [post] stays in the feed, from now.
  Future<void> _choosePostLifetime(Post post) async {
    final expiresAt = post.expiresAt;
    final choice = await showDialog<PostLifetime>(
      context: context,
      builder:
          (ctx) => SimpleDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const TranslatedText('Keep in feed for'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  expiresAt == null
                      ? 'Now: stays until deleted'
                      : 'Now: until ${expiresAt.month}/${expiresAt.day} '
                          '${expiresAt.hour}:${expiresAt.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 13,
                    color: FeedColors.textSecondary,
                  ),
                ),
              ),
              for (final lifetime in PostLifetime.values)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(lifetime),
                  child: TranslatedText(lifetime.label),
                ),
            ],
          ),
    );
    if (choice == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PostService.setLifetime(post.id, choice);
      messenger.showSnackBar(
        SnackBar(
          content: TranslatedText(
            choice.duration == null
                ? 'Post will stay until deleted.'
                : 'Post will stay for ${choice.label} from now.',
          ),
        ),
      );
      await widget.onRefresh?.call();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: TranslatedText('Could not update the post. Try again.'),
        ),
      );
    }
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
      builder:
          (_) => CreatePostDialog(
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
        builder:
            (_) => CommentsScreen(
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
    showDialog(context: context, builder: (_) => ReportPostDialog(post: post));
  }

  Future<void> _deletePost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const TranslatedText('Delete Post'),
            content: const TranslatedText(
              'Are you sure you want to delete this post? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const TranslatedText('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const TranslatedText('Delete'),
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
            const SnackBar(
              content: TranslatedText(
                'Failed to delete post. Please try again.',
              ),
            ),
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

  int _effectiveUpvoteCount(Post post) =>
      _upvoteCounts[post.id] ?? post.upvoteCount;

  int _effectiveDownvoteCount(Post post) =>
      _downvoteCounts[post.id] ?? post.downvoteCount;

  bool? _effectiveVote(Post post) =>
      _postVotes[post.id] ?? _initialVoteForPost(post);

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

  Future<void> _handleVote(Post post, {required bool isUpvote}) async {
    if (_pendingVotePostIds.contains(post.id)) return;

    final previousVote = _effectiveVote(post);
    // Mirror the server's toggle logic optimistically: tapping the same
    // vote again clears it, otherwise it becomes the tapped vote.
    final optimisticVote = previousVote == isUpvote ? null : isUpvote;

    setState(() {
      _pendingVotePostIds.add(post.id);
      _applyLocalVoteState(post, previousVote, optimisticVote);
    });

    try {
      final serverVote = await PostActionsService.votePost(
        post.id,
        widget.currentUserId,
        isUpvote: isUpvote,
      );
      if (!mounted) return;

      if (serverVote != optimisticVote) {
        // Reconcile with the server's actual result (e.g. state changed
        // elsewhere between our optimistic guess and this response).
        setState(() => _applyLocalVoteState(post, optimisticVote, serverVote));
      }

      if (serverVote == isUpvote &&
          post.userId != null &&
          post.userId != widget.currentUserId) {
        NotificationsService.addNotification(
          NotificationModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            userId: post.userId!,
            type: isUpvote ? 'upvote' : 'downvote',
            postId: post.id,
            fromUserName: widget.currentUserName,
            timestamp: DateTime.now(),
            message:
                '${widget.currentUserName} ${isUpvote ? 'upvoted' : 'downvoted'} your post.',
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      // Roll back the optimistic update — the request never landed.
      setState(() => _applyLocalVoteState(post, optimisticVote, previousVote));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText('Vote failed. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pendingVotePostIds.remove(post.id));
      } else {
        _pendingVotePostIds.remove(post.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final approvedPosts =
        widget.posts
            .where((p) => p.moderationStatus == ModerationStatus.approved)
            .toList();

    return Scaffold(
      backgroundColor: FeedColors.bg,
      appBar: _buildAppBar(approvedPosts),
      floatingActionButton: _buildFab(),
      body:
          approvedPosts.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                onRefresh: widget.onRefresh ?? () async {},
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: approvedPosts.length,
                  itemBuilder:
                      (context, index) => _buildPostCard(approvedPosts[index]),
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
      onUpvoteTapped: () => _handleVote(post, isUpvote: true),
      onDownvoteTapped: () => _handleVote(post, isUpvote: false),
      onCommentTapped: () async {
        if (!_loadedPostIds.contains(post.id)) await _loadComments(post.id);
        _showCommentSheet(post.id, post);
      },
      onReportTapped: () => _showReportDialog(post),
      onDeleteTapped:
          post.userId == widget.currentUserId ? () => _deletePost(post) : null,
      onLifetimeTapped:
          ModerationService.isStaffNotifier.value
              ? () => _choosePostLifetime(post)
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_rounded, color: FeedColors.accent, size: 16),
            SizedBox(width: 8),
            Flexible(
              child: TranslatedText(
                'Community Feed',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: FeedColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        GestureDetector(
          onTap:
              () => Navigator.push(
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
            child: Icon(Icons.search, color: FeedColors.textPrimary, size: 20),
          ),
        ),
        GestureDetector(
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => NotificationsScreen(
                        currentUserId: widget.currentUserId,
                        currentUserName: widget.currentUserName,
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
                Icon(
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
                            fontWeight: FontWeight.w600,
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

  // The pill itself is the button: wrapped in FloatingActionButton.extended
  // it sat inside invisible padding and looked shifted left of the posts.
  Widget _buildFab() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B8FD6), Color(0xFF2BB5F0)],
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
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _showCreatePostDialog,
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                TranslatedText(
                  'New Post',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
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
          TranslatedText(
            'No posts yet',
            style: TextStyle(
              color: FeedColors.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 6),
          TranslatedText(
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
