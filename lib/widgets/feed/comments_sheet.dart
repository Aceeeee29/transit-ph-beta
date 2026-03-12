import 'package:flutter/material.dart';
import '../../models/comment.dart';
import '../../models/notification.dart';
import '../../models/post.dart';
import '../../services/notifications_service.dart';
import '../../services/post_actions_service.dart';
import 'comment_item.dart';
import 'feed_colors.dart';

/// Full comments bottom-sheet: shows existing comments and lets the user
/// post new ones. New comments appear immediately (optimistic update) so
/// the user never has to re-open the sheet to see their own reply.
class CommentsSheet extends StatefulWidget {
  final String postId;
  final Post post;
  final List<Comment> initialComments;
  final String currentUserId;
  final String currentUserName;
  final Future<void> Function() onCommentPosted;

  const CommentsSheet({
    super.key,
    required this.postId,
    required this.post,
    required this.initialComments,
    required this.currentUserId,
    required this.currentUserName,
    required this.onCommentPosted,
  });

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _controller = TextEditingController();
  final _inputFocusNode = FocusNode();
  ScrollController? _listScrollController;
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
    super.dispose();
  }

  // ─── Optimistic submit ────────────────────────────────────────────────────

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

    // ── Optimistic update: show immediately ──────────────────────────────
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

    // Scroll to show the new comment
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_listScrollController?.hasClients ?? false) {
        _listScrollController!.animateTo(
          _listScrollController!.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // ── Persist in background ────────────────────────────────────────────
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
          const SnackBar(content: Text('Failed to sync comment. Please check your connection.')),
        );
      }
    }
  }

  void _startReply(Comment comment) {
    setState(() => _replyingTo = comment);
    _inputFocusNode.requestFocus();
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  Future<void> _deleteComment(Comment comment, bool isTopLevel) async {
    setState(() {
      if (isTopLevel) {
        _comments.removeWhere((c) => c.id == comment.id);
      } else {
        final parentIdx = _comments.indexWhere((c) => c.id == comment.parentId);
        if (parentIdx != -1) {
          _comments[parentIdx] = _comments[parentIdx].removeReply(comment.id);
        }
      }
    });

    try {
      await PostActionsService.deleteComment(
        widget.postId,
        comment.id,
        isTopLevel: isTopLevel,
      );
      await widget.onCommentPosted();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete comment. Please try again.')),
        );
      }
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        _listScrollController = scrollController;
        return Container(
          decoration: const BoxDecoration(
            color: FeedColors.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _buildHandle(),
              _buildHeader(),
              const Divider(color: FeedColors.border, height: 1),
              Expanded(child: _buildCommentsList(scrollController)),
              if (_replyingTo != null) _buildReplyBanner(),
              _buildInput(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: FeedColors.border,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: FeedColors.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.comment_outlined,
              color: FeedColors.accent,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Comments${_comments.isNotEmpty ? ' (${_comments.length})' : ''}',
            style: const TextStyle(
              color: FeedColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: FeedColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: FeedColors.border),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: FeedColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsList(ScrollController scrollController) {
    if (_comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: FeedColors.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 28,
                color: FeedColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No comments yet',
              style: TextStyle(
                color: FeedColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Be the first to comment!',
              style: TextStyle(
                color: FeedColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _comments.length,
      itemBuilder: (_, i) => CommentItem(
        comment: _comments[i],
        depth: 0,
        onReply: _startReply,
        currentUserId: widget.currentUserId,
        onDelete: _deleteComment,
      ),
    );
  }

  Widget _buildReplyBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: FeedColors.accentSoft,
      child: Row(
        children: [
          const Icon(
            Icons.reply_rounded,
            size: 14,
            color: FeedColors.accent,
          ),
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
      decoration: BoxDecoration(
        color: FeedColors.surface,
        border: const Border(
          top: BorderSide(color: FeedColors.border),
        ),
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
