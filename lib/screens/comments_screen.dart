import 'package:flutter/material.dart';
import '../models/comment.dart';
import '../models/notification.dart';
import '../models/post.dart';
import '../services/notifications_service.dart';
import '../services/post_actions_service.dart';
import '../widgets/feed/comment_item.dart';
import '../widgets/feed/feed_colors.dart';

class CommentsScreen extends StatefulWidget {
  final String postId;
  final Post post;
  final List<Comment> initialComments;
  final String currentUserId;
  final String currentUserName;
  final Future<void> Function() onCommentPosted;

  const CommentsScreen({
    super.key,
    required this.postId,
    required this.post,
    required this.initialComments,
    required this.currentUserId,
    required this.currentUserName,
    required this.onCommentPosted,
  });

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _controller = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  Comment? _replyingTo;
  bool _isSubmitting = false;
  late List<Comment> _comments;

  @override
  void initState() {
    super.initState();
    _comments = List<Comment>.from(widget.initialComments);
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Submit ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    final comment = Comment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      postId: widget.postId,
      userId: widget.currentUserId,
      userName: widget.currentUserName,
      content: text,
      parentId: _replyingTo?.id,
      timestamp: DateTime.now(),
    );

    // Optimistic update — show immediately
    setState(() {
      if (_replyingTo != null) {
        final idx = _comments.indexWhere((c) => c.id == _replyingTo!.id);
        if (idx != -1) {
          _comments[idx] = _comments[idx].addReply(comment);
        } else {
          _comments.add(comment);
        }
      } else {
        _comments.add(comment);
      }
      _controller.clear();
      _replyingTo = null;
      _isSubmitting = false;
    });

    // Scroll to new comment
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // Persist in background
    try {
      await PostActionsService.addComment(comment);
      await widget.onCommentPosted();
      final post = widget.post;
      if (post.userId != null && post.userId != widget.currentUserId) {
        NotificationsService.addNotification(
          NotificationModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            userId: post.userId!,
            type: comment.parentId != null ? 'reply' : 'comment',
            postId: widget.postId,
            fromUserName: widget.currentUserName,
            timestamp: DateTime.now(),
            message: comment.parentId != null
                ? '${widget.currentUserName} replied to a comment.'
                : '${widget.currentUserName} commented on your post.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to sync comment. Please check your connection.'),
          ),
        );
      }
    }
  }

  void _startReply(Comment comment) {
    setState(() => _replyingTo = comment);
    _inputFocusNode.requestFocus();
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedColors.bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildCommentsList()),
          if (_replyingTo != null) _buildReplyBanner(),
          _buildInput(context),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
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
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: FeedColors.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.comment_outlined,
              color: FeedColors.accent,
              size: 15,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Comments${_comments.isNotEmpty ? ' (${_comments.length})' : ''}',
            style: const TextStyle(
              color: FeedColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: FeedColors.border, height: 1),
      ),
    );
  }

  Widget _buildCommentsList() {
    if (_comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: FeedColors.surfaceAlt,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 30,
                color: FeedColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No comments yet',
              style: TextStyle(
                color: FeedColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Be the first to comment!',
              style: TextStyle(color: FeedColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _comments.length,
      itemBuilder: (_, i) => CommentItem(
        comment: _comments[i],
        depth: 0,
        onReply: _startReply,
      ),
    );
  }

  Widget _buildReplyBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: FeedColors.accentSoft,
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, size: 14, color: FeedColors.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Replying to ${_replyingTo!.userName}',
              style: const TextStyle(
                fontSize: 12,
                color: FeedColors.accent,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: _cancelReply,
            child: const Icon(
              Icons.close_rounded,
              size: 16,
              color: FeedColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomPadding),
      decoration: const BoxDecoration(
        color: FeedColors.surface,
        border: Border(top: BorderSide(color: FeedColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: FeedColors.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: FeedColors.border),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _inputFocusNode,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                  color: FeedColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: _replyingTo != null
                      ? 'Reply to ${_replyingTo!.userName}...'
                      : 'Write a comment...',
                  hintStyle: const TextStyle(
                    color: FeedColors.textSecondary,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isSubmitting ? null : _submit,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: _isSubmitting
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: _isSubmitting ? FeedColors.border : null,
                borderRadius: BorderRadius.circular(12),
                boxShadow: _isSubmitting
                    ? null
                    : [
                        BoxShadow(
                          color: FeedColors.accent.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: _isSubmitting
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: FeedColors.textSecondary,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
