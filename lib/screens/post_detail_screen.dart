import 'package:flutter/material.dart';
import '../models/comment.dart';
import '../models/notification.dart';
import '../models/post.dart';
import '../services/notifications_service.dart';
import '../services/post_actions_service.dart';
import '../services/post_service.dart';
import '../widgets/feed/feed_colors.dart';
import '../widgets/feed/feed_post_card.dart';
import 'comments_screen.dart';

/// Deep-link target for post-related notifications
/// (upvote / like / downvote / comment / reply).
///
/// Shows the single post and lets the user jump into its comments.
class PostDetailScreen extends StatefulWidget {
  final String postId;
  final String currentUserId;
  final String currentUserName;
  final String? highlightCommentId;
  final bool openCommentsInitially;

  const PostDetailScreen({
    super.key,
    required this.postId,
    required this.currentUserId,
    required this.currentUserName,
    this.highlightCommentId,
    this.openCommentsInitially = false,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Post? _post;
  List<Comment> _comments = [];
  bool _isLoading = true;
  String? _error;
  bool? _userVote;
  int _upvoteCount = 0;
  int _downvoteCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final post = await PostService.getPostById(widget.postId);
      if (!mounted) return;
      if (post == null) {
        setState(() {
          _isLoading = false;
          _error = 'This post is no longer available.';
        });
        return;
      }
      final comments = await PostService.getComments(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = post;
        _comments = comments;
        _upvoteCount = post.upvoteCount;
        _downvoteCount = post.downvoteCount;
        if (post.upvotedBy.contains(widget.currentUserId)) {
          _userVote = true;
        } else if (post.downvotedBy.contains(widget.currentUserId)) {
          _userVote = false;
        } else {
          _userVote = null;
        }
        _isLoading = false;
      });
      if (widget.openCommentsInitially && mounted && _post != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openComments();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load post. Please try again.';
      });
    }
  }

  void _applyLocalVoteState(bool? previousVote, bool? nextVote) {
    if (previousVote == true) {
      _upvoteCount = (_upvoteCount - 1).clamp(0, 1 << 31);
    } else if (previousVote == false) {
      _downvoteCount = (_downvoteCount - 1).clamp(0, 1 << 31);
    }
    if (nextVote == true) {
      _upvoteCount += 1;
    } else if (nextVote == false) {
      _downvoteCount += 1;
    }
    _userVote = nextVote;
  }

  Future<void> _vote(bool isUpvote) async {
    final post = _post;
    if (post == null) return;
    final previousVote = _userVote;
    final nextVote = await PostActionsService.votePost(
      post.id,
      widget.currentUserId,
      isUpvote: isUpvote,
    );
    if (!mounted) return;
    setState(() => _applyLocalVoteState(previousVote, nextVote));
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
  }

  void _openComments() {
    final post = _post;
    if (post == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommentsScreen(
          postId: post.id,
          post: post,
          initialComments: _comments,
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          onCommentPosted: () async {
            final fresh = await PostService.getComments(post.id);
            if (mounted) setState(() => _comments = fresh);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedColors.bg,
      appBar: AppBar(
        backgroundColor: FeedColors.bg,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: FeedColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: FeedColors.border),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: FeedColors.textPrimary,
              size: 16,
            ),
          ),
        ),
        title: const Text(
          'Post',
          style: TextStyle(
            color: FeedColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: FeedColors.border, height: 1),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: FeedColors.accent,
          strokeWidth: 2,
        ),
      );
    }
    if (_error != null || _post == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: FeedColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.forum_outlined,
                  size: 32,
                  color: FeedColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Post unavailable',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: FeedColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error ?? 'This post may have been deleted.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: FeedColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: FeedColors.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Go back',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final post = _post!;
    return RefreshIndicator(
      onRefresh: _load,
      color: FeedColors.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          FeedPostCard(
            post: post,
            isUpvoted: _userVote == true,
            isDownvoted: _userVote == false,
            upvoteCount: _upvoteCount,
            downvoteCount: _downvoteCount,
            currentUserId: widget.currentUserId,
            currentUserName: widget.currentUserName,
            onUpvoteTapped: () => _vote(true),
            onDownvoteTapped: () => _vote(false),
            onCommentTapped: _openComments,
            onReportTapped: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Open the feed to report this post.'),
                ),
              );
            },
          ),
          GestureDetector(
            onTap: _openComments,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: FeedColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: FeedColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.comment_outlined,
                    size: 18,
                    color: FeedColors.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _comments.isEmpty
                          ? 'Be the first to comment'
                          : 'View ${_comments.length} comment${_comments.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: FeedColors.textPrimary,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: FeedColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
