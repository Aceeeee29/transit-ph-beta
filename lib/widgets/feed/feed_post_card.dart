import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:video_player/video_player.dart';
import '../../models/post.dart';
import '../../security/security_manager.dart';
import 'feed_action_button.dart';
import 'feed_colors.dart';
import 'post_category_helpers.dart';

/// Displays a single community post with its action bar, media, and comments.
class FeedPostCard extends StatefulWidget {
  final Post post;
  final bool isUpvoted;
  final bool isDownvoted;
  final int upvoteCount;
  final int downvoteCount;
  final bool isBookmarked;
  final String currentUserId;
  final String currentUserName;
  final VoidCallback onUpvoteTapped;
  final VoidCallback onDownvoteTapped;
  final VoidCallback onCommentTapped;
  final VoidCallback onBookmarkTapped;
  final VoidCallback onReportTapped;
  final VoidCallback? onDeleteTapped;

  const FeedPostCard({
    super.key,
    required this.post,
    required this.isUpvoted,
    required this.isDownvoted,
    required this.upvoteCount,
    required this.downvoteCount,
    required this.isBookmarked,
    required this.currentUserId,
    required this.currentUserName,
    required this.onUpvoteTapped,
    required this.onDownvoteTapped,
    required this.onCommentTapped,
    required this.onBookmarkTapped,
    required this.onReportTapped,
    this.onDeleteTapped,
  });

  @override
  State<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<FeedPostCard> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.post.videoUrl != null) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.post.videoUrl!),
      )..initialize().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final catColor = postCategoryColor(post.category);
    final authorName = post.userName?.trim();
    final displayName = post.anonymous
      ? 'Anonymous'
      : (authorName != null && authorName.isNotEmpty
        ? authorName
        : 'User');
    final initials =
        post.anonymous
            ? 'A'
        : (authorName != null && authorName.isNotEmpty
          ? authorName[0].toUpperCase()
          : 'U');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: FeedColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FeedColors.border),
        boxShadow: [
          BoxShadow(
            color: FeedColors.accent.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PostHeader(
              post: post,
              displayName: displayName,
              initials: initials,
              catColor: catColor,
              isOwnPost: widget.currentUserId.isNotEmpty &&
                  widget.currentUserId == post.userId,
              onDeleteTapped: widget.onDeleteTapped,
            ),
            const SizedBox(height: 12),
            _PostContent(post: post, videoController: _videoController),
            const SizedBox(height: 12),
            Divider(color: FeedColors.border, height: 1),
            const SizedBox(height: 8),
            _buildActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Row(
      children: [
        FeedActionButton(
          icon:
              widget.isUpvoted
                  ? Icons.thumb_up
                  : Icons.thumb_up_alt_outlined,
          color:
              widget.isUpvoted ? FeedColors.accent : FeedColors.textSecondary,
          active: widget.isUpvoted,
          label: '${widget.upvoteCount}',
          onTap: widget.onUpvoteTapped,
        ),
        const SizedBox(width: 6),
        FeedActionButton(
          icon:
              widget.isDownvoted
                  ? Icons.thumb_down
                  : Icons.thumb_down_alt_outlined,
          color:
              widget.isDownvoted
                  ? FeedColors.danger
                  : FeedColors.textSecondary,
          active: widget.isDownvoted,
          label: '${widget.downvoteCount}',
          onTap: widget.onDownvoteTapped,
        ),
        const SizedBox(width: 6),
        FeedActionButton(
          icon: Icons.comment_outlined,
          color: FeedColors.textSecondary,
          onTap: widget.onCommentTapped,
        ),
        const SizedBox(width: 6),
        FeedActionButton(
          icon:
              widget.isBookmarked ? Icons.bookmark : Icons.bookmark_border,
          color:
              widget.isBookmarked
                  ? FeedColors.accent
                  : FeedColors.textSecondary,
          active: widget.isBookmarked,
          onTap: widget.onBookmarkTapped,
        ),
        const Spacer(),
        FeedActionButton(
          icon: Icons.flag_outlined,
          color: FeedColors.danger,
          onTap: widget.onReportTapped,
        ),
      ],
    );
  }

}

// ─── Private sub-widgets ──────────────────────────────────────────────────────

class _PostHeader extends StatelessWidget {
  final Post post;
  final String displayName;
  final String initials;
  final Color catColor;
  final bool isOwnPost;
  final VoidCallback? onDeleteTapped;

  const _PostHeader({
    required this.post,
    required this.displayName,
    required this.initials,
    required this.catColor,
    required this.isOwnPost,
    this.onDeleteTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor:
              post.anonymous ? FeedColors.surfaceAlt : FeedColors.accentSoft,
          child: Text(
            initials,
            style: const TextStyle(
              color: FeedColors.accent,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: FeedColors.textPrimary,
                ),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.access_time,
                    size: 11,
                    color: FeedColors.textSecondary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${post.timestamp.hour}:'
                    '${post.timestamp.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: FeedColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _CategoryBadge(catColor: catColor, category: post.category),
        if (isOwnPost && onDeleteTapped != null) ...[
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert,
              size: 18,
              color: FeedColors.textSecondary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              if (value == 'delete') onDeleteTapped!();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Delete Post',
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PostContent extends StatelessWidget {
  final Post post;
  final VideoPlayerController? videoController;

  const _PostContent({required this.post, required this.videoController});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Linkify(
          onOpen: (link) async => SecurityManager.openLink(context, link.url),
          text: post.content,
          style: const TextStyle(
            fontSize: 15,
            color: FeedColors.textPrimary,
            height: 1.5,
          ),
          linkStyle: const TextStyle(
            color: FeedColors.accent,
            decoration: TextDecoration.underline,
          ),
        ),
        if (post.imageUrls.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PostImageStrip(urls: post.imageUrls),
        ],
        if (post.videoUrl != null && videoController != null) ...[
          const SizedBox(height: 12),
          _VideoPlayer(controller: videoController!),
        ],
        if (post.taggedLocation != null) ...[
          const SizedBox(height: 10),
          _LocationBadge(name: post.taggedLocation!.name),
        ],
      ],
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final Color catColor;
  final PostCategory category;

  const _CategoryBadge({required this.catColor, required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: catColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: catColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(postCategoryIcon(category), size: 12, color: catColor),
          const SizedBox(width: 4),
          Text(
            postCategoryLabel(category),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: catColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostImageStrip extends StatelessWidget {
  final List<String> urls;

  const _PostImageStrip({required this.urls});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: urls.length,
          itemBuilder:
              (_, index) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    urls[index],
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        width: 200,
                        height: 200,
                        color: FeedColors.surfaceAlt,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: FeedColors.accent,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    },
                    errorBuilder:
                        (_, __, ___) => Container(
                          width: 200,
                          height: 200,
                          color: FeedColors.surfaceAlt,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: FeedColors.textSecondary,
                          ),
                        ),
                  ),
                ),
              ),
        ),
      ),
    );
  }
}

class _VideoPlayer extends StatelessWidget {
  final VideoPlayerController controller;

  const _VideoPlayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: FeedColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            color: FeedColors.accent,
            strokeWidth: 2,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _LocationBadge extends StatelessWidget {
  final String name;

  const _LocationBadge({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: FeedColors.accentSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FeedColors.accent.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_on_outlined,
            size: 13,
            color: FeedColors.accent,
          ),
          const SizedBox(width: 5),
          Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              color: FeedColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
