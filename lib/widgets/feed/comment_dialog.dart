import 'package:flutter/material.dart';
import '../../models/comment.dart';
import '../../models/notification.dart';
import '../../models/post.dart';
import '../../services/notifications_service.dart';
import '../../services/post_actions_service.dart';
import 'feed_colors.dart';
import 'feed_dialog_widgets.dart';

/// Dialog for posting a new comment or replying to an existing comment.
class FeedCommentDialog extends StatefulWidget {
  final String postId;
  final String currentUserId;
  final String currentUserName;
  final List<Post> posts;
  final Comment? parentComment;
  final Future<void> Function() onCommentPosted;

  const FeedCommentDialog({
    super.key,
    required this.postId,
    required this.currentUserId,
    required this.currentUserName,
    required this.posts,
    required this.onCommentPosted,
    this.parentComment,
  });

  @override
  State<FeedCommentDialog> createState() => _FeedCommentDialogState();
}

class _FeedCommentDialogState extends State<FeedCommentDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.isEmpty) {
      Navigator.pop(context);
      
      return;
    }
    try {
      final comment = Comment(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        postId: widget.postId,
        userId: widget.currentUserId,
        userName: widget.currentUserName,
        content: _controller.text,
        parentId: widget.parentComment?.id,
        timestamp: DateTime.now(),
      );
      await PostActionsService.addComment(comment);
      await widget.onCommentPosted();
      final post = widget.posts.firstWhere((p) => p.id == widget.postId);
      if (post.userId != null && post.userId != widget.currentUserId) {
        NotificationsService.addNotification(
          NotificationModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            userId: post.userId!,
            type: widget.parentComment != null ? 'reply' : 'comment',
            postId: widget.postId,
            fromUserName: widget.currentUserName,
            timestamp: DateTime.now(),
            message:
                widget.parentComment != null
                    ? '${widget.currentUserName} replied to a comment.'
                    : '${widget.currentUserName} commented on your post.',
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to post comment. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: FeedColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: FeedColors.border),
          boxShadow: [
            BoxShadow(
              color: FeedColors.accent.withOpacity(0.08),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FeedDialogHeader(
              icon: Icons.comment_outlined,
              title:
                  widget.parentComment != null
                      ? 'Reply to ${widget.parentComment!.userName}'
                      : 'Add Comment',
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: FeedColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: FeedColors.border),
                ),
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(
                    color: FeedColors.textPrimary,
                    fontSize: 14,
                  ),
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Write your comment...',
                    hintStyle: TextStyle(
                      color: FeedColors.textSecondary,
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
                    child: FeedDialogCancelButton(
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FeedDialogPrimaryButton(
                      label: 'Post Comment',
                      onTap: _submit,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
