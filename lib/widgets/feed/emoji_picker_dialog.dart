import 'package:flutter/material.dart';
import '../../services/post_actions_service.dart';
import 'feed_colors.dart';
import 'feed_dialog_widgets.dart';

/// Dialog that shows emoji reaction options for a post.
class EmojiPickerDialog extends StatelessWidget {
  static const _emojis = ['👍', '❤️', '😂', '😮', '😢', '😡'];

  final String postId;
  final String currentUserId;
  final Map<String, List<String>> reactions; // emoji -> list of user IDs
  final void Function(String emoji, bool removed) onReactionToggled;

  const EmojiPickerDialog({
    super.key,
    required this.postId,
    required this.currentUserId,
    required this.reactions,
    required this.onReactionToggled,
  });

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
            const FeedDialogHeader(
              icon: Icons.emoji_emotions_outlined,
              title: 'React',
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children:
                    _emojis.map((emoji) {
                      final isActive =
                          reactions[emoji]?.contains(currentUserId) ?? false;
                      return GestureDetector(
                        onTap: () async {
                          final removed =
                              reactions[emoji]?.contains(currentUserId) ??
                              false;
                          if (removed) {
                            await PostActionsService.removeReaction(
                              postId,
                              emoji,
                              currentUserId,
                            );
                          } else {
                            await PostActionsService.addReaction(
                              postId,
                              emoji,
                              currentUserId,
                            );
                          }
                          onReactionToggled(emoji, removed);
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color:
                                isActive
                                    ? FeedColors.accentSoft
                                    : FeedColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color:
                                  isActive
                                      ? FeedColors.accent
                                      : FeedColors.border,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      );
                    }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FeedDialogCancelButton(
                onTap: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
