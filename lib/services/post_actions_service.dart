import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../models/feedback.dart' as feedback_model;
import 'moderation_service.dart';
import 'post_service.dart';
import 'bookmark_service.dart';

class PostActionsService {
  static Future<void> reportPost(
    Post post,
    String reason,
    String userId,
  ) async {
    // Update post status in DB atomically with feedback creation
    final feedbackId = DateTime.now().millisecondsSinceEpoch.toString();
    final feedback = feedback_model.Feedback(
      id: feedbackId,
      userId: userId,
      type: feedback_model.FeedbackType.report,
      content: reason,
      targetId: post.id,
      targetType: feedback_model.FeedbackTargetType.post,
      timestamp: DateTime.now(),
    );

    // Use batch write for atomic operation
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    batch.update(firestore.collection('posts').doc(post.id), {
      'moderationStatus': ModerationStatus.pending.name,
    });
    batch.set(
      firestore.collection('feedbacks').doc(feedbackId),
      feedback.toJson(),
    );

    try {
      await batch.commit();
      // Update local notifiers
      post.moderationStatus = ModerationStatus.pending;
      ModerationService.postsNotifier.value = List.from(
        ModerationService.postsNotifier.value,
      );
      ModerationService.addFeedback(feedback);
    } catch (e) {
      print('Error reporting post: $e');
    }
  }

  static Future<void> likePost(String postId, String userId) async {
    await PostService.toggleLike(postId, userId);
  }

  static Future<void> addComment(Comment comment) async {
    await PostService.addComment(comment);
  }

  static Future<void> addReaction(
    String postId,
    String emoji,
    String userId,
  ) async {
    await PostService.addReaction(postId, emoji, userId);
  }

  static Future<void> removeReaction(
    String postId,
    String emoji,
    String userId,
  ) async {
    await PostService.removeReaction(postId, emoji, userId);
  }

  static Future<void> bookmarkPost(String postId, String userId) async {
    await BookmarkService.addPostBookmark(postId);
  }

  static Future<void> followRoute(String routeId, String userId) async {
    await BookmarkService.addBookmark(routeId);
  }
}
