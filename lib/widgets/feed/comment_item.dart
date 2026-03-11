import 'package:flutter/material.dart';
import '../../models/comment.dart';
import 'feed_colors.dart';

/// Renders a single comment and its nested replies recursively.
class CommentItem extends StatelessWidget {
  final Comment comment;
  final int depth;
  final void Function(Comment) onReply;

  const CommentItem({
    super.key,
    required this.comment,
    required this.onReply,
    this.depth = 0,
  });

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
              color:
                  depth == 0 ? FeedColors.surfaceAlt : FeedColors.accentSoft,
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
                        comment.content,
                        style: const TextStyle(
                          fontSize: 13,
                          color: FeedColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => onReply(comment),
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
              ],
            ),
          ),
          if (comment.replies.isNotEmpty)
            ...comment.replies.map(
              (reply) =>
                  CommentItem(comment: reply, depth: depth + 1, onReply: onReply),
            ),
        ],
      ),
    );
  }
}
