import '../models/post.dart';
import '../models/feedback.dart' as feedback_model;
import 'moderation_service.dart';

class PostActionsService {
  static void reportPost(Post post, String reason, String userId) {
    // Set post to pending
    post.moderationStatus = ModerationStatus.pending;
    ModerationService.postsNotifier.value = List.from(ModerationService.postsNotifier.value);

    // Add feedback with reason
    final feedback = feedback_model.Feedback(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: userId,
      type: feedback_model.FeedbackType.report,
      content: reason,
      targetId: post.id,
      timestamp: DateTime.now(),
    );
    ModerationService.addFeedback(feedback);
  }

  static void likePost(String postId, Map<String, bool> likedPosts) {
    likedPosts[postId] = !(likedPosts[postId] ?? false);
  }

  static void addComment(String postId, String comment, Map<String, List<String>> postComments) {
    postComments[postId] ??= [];
    postComments[postId]!.add(comment);
  }
}
