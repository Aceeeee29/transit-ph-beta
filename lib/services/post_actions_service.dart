import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../models/feedback.dart' as feedback_model;
import 'post_service.dart';
import 'bookmark_service.dart';

class PostActionsService {
  static Future<void> reportPost(
    Post post,
    String reason,
    String userId,
  ) async {
    // Create report feedback without auto-changing post visibility.
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

    // Single write for the report entry.
    final firestore = FirebaseFirestore.instance;
    try {
      await firestore.collection('feedbacks').doc(feedbackId).set(
        feedback.toJson(),
      );
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

  static Future<void> deleteComment(
    String postId,
    String commentId, {
    bool isTopLevel = true,
  }) async {
    await PostService.deleteComment(postId, commentId, isTopLevel: isTopLevel);
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
