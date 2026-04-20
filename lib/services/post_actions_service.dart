import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../models/feedback.dart' as feedback_model;
import 'post_service.dart';

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
    } catch (_) {
    }
  }

  static Future<bool?> votePost(
    String postId,
    String userId, {
    required bool isUpvote,
  }) async {
    return PostService.toggleVote(postId, userId, isUpvote: isUpvote);
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

  static Future<bool?> upvotePost(String postId, String userId) {
    return votePost(postId, userId, isUpvote: true);
  }

  static Future<bool?> downvotePost(String postId, String userId) {
    return votePost(postId, userId, isUpvote: false);
  }
}
