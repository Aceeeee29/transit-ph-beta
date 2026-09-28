import 'package:flutter/material.dart';
import '../../models/comment.dart';
import '../../services/app_language_service.dart';
import 'feed_colors.dart';

/// Renders a single comment and its nested replies recursively.
class CommentItem extends StatefulWidget {
  final Comment comment;
  final int depth;
  final void Function(Comment) onReply;
  final String currentUserId;
  final void Function(Comment comment, bool isTopLevel)? onDelete;

  const CommentItem({
    super.key,
    required this.comment,
    required this.onReply,
    required this.currentUserId,
    this.onDelete,
    this.depth = 0,
  });

  @override
  State<CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<CommentItem> {
  Comment get comment => widget.comment;
  int get depth => widget.depth;
  String get currentUserId => widget.currentUserId;

  String? _translated;
  bool _showTranslated = false;
  bool _isTranslating = false;

  Future<void> _toggleTranslation() async {
    if (_showTranslated) {
      setState(() => _showTranslated = false);
      return;
    }
    if (_translated != null) {
      setState(() => _showTranslated = true);
      return;
    }
    setState(() => _isTranslating = true);
    final result = await AppLanguageService.translate(comment.content);
    if (!mounted) return;
    setState(() {
      _translated = result;
      _showTranslated = result != comment.content;
      _isTranslating = false;
    });
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final isReply = depth > 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: FeedColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Text(
              'Delete ${isReply ? 'reply' : 'comment'}?',
              style: const TextStyle(
                color: FeedColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              isReply
                  ? 'This reply will be permanently deleted.'
                  : 'This comment and all its replies will be permanently deleted.',
              style: const TextStyle(
                color: FeedColors.textSecondary,
                fontSize: 13,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: FeedColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      widget.onDelete?.call(comment, depth == 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0, top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: depth == 0 ? FeedColors.surfaceAlt : FeedColors.accentSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: FeedColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: FeedColors.accentSoft,
                  child: Text(
                    comment.userName.isNotEmpty
                        ? comment.userName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: FeedColors.accent,
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
                          color: FeedColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (_showTranslated && _translated != null)
                            ? _translated!
                            : comment.content,
                        style: const TextStyle(
                          fontSize: 13,
                          color: FeedColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      if (!AppLanguageService.isEnglish) ...[
                        const SizedBox(height: 3),
                        GestureDetector(
                          onTap: _isTranslating ? null : _toggleTranslation,
                          child:
                              _isTranslating
                                  ? const SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: FeedColors.accent,
                                    ),
                                  )
                                  : Text(
                                    _showTranslated
                                        ? 'See original'
                                        : 'Translate to ${AppLanguageService.currentLanguageLabel}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: FeedColors.accent,
                                    ),
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => widget.onReply(comment),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: FeedColors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: FeedColors.border),
                    ),
                    child: const Icon(
                      Icons.reply_rounded,
                      size: 13,
                      color: FeedColors.textSecondary,
                    ),
                  ),
                ),
                if (comment.userId == currentUserId) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _confirmDelete(context),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: FeedColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: FeedColors.border),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        size: 13,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (comment.replies.isNotEmpty)
            ...comment.replies.map(
              (reply) => CommentItem(
                comment: reply,
                depth: depth + 1,
                onReply: widget.onReply,
                currentUserId: currentUserId,
                onDelete: widget.onDelete,
              ),
            ),
        ],
      ),
    );
  }
}
