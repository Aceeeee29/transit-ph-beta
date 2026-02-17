import '../models/post.dart';
import '../models/comment.dart';
import '../models/feedback.dart' as feedback_model;
import 'moderation_service.dart';

class PostActionsService {
  static void reportPost(Post post, String reason, String userId) {
    // Set post to pending
    post.moderationStatus = ModerationStatus.pending;
    ModerationService.postsNotifier.value = List.from(
      ModerationService.postsNotifier.value,
    );

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

  static void addComment(
    String postId,
    Comment comment,
    Map<String, List<Comment>> postComments,
  ) {
    postComments[postId] ??= [];
    postComments[postId]!.add(comment);
  }

  static void addReaction(
    String postId,
    String emoji,
    String userId,
    Map<String, Map<String, List<String>>> reactions,
  ) {
    reactions[postId] ??= {};
    reactions[postId]![emoji] ??= [];
    if (!reactions[postId]![emoji]!.contains(userId)) {
      reactions[postId]![emoji]!.add(userId);
    }
  }

  static void removeReaction(
    String postId,
    String emoji,
    String userId,
    Map<String, Map<String, List<String>>> reactions,
  ) {
    if (reactions[postId]?[emoji]?.contains(userId) ?? false) {
      reactions[postId]![emoji]!.remove(userId);
      if (reactions[postId]![emoji]!.isEmpty) {
        reactions[postId]!.remove(emoji);
      }
    }
  }

  static void bookmarkPost(
    String postId,
    String userId,
    Map<String, List<String>> bookmarks,
  ) {
    bookmarks[userId] ??= [];
    if (!bookmarks[userId]!.contains(postId)) {
      bookmarks[userId]!.add(postId);
    }
  }

  static void unbookmarkPost(
    String postId,
    String userId,
    Map<String, List<String>> bookmarks,
  ) {
    bookmarks[userId]?.remove(postId);
  }

  static void followRoute(
    String routeId,
    String userId,
    Map<String, List<String>> followedRoutes,
  ) {
    followedRoutes[userId] ??= [];
    if (!followedRoutes[userId]!.contains(routeId)) {
      followedRoutes[userId]!.add(routeId);
    }
  }

  static void unfollowRoute(
    String routeId,
    String userId,
    Map<String, List<String>> followedRoutes,
  ) {
    followedRoutes[userId]?.remove(routeId);
  }
}
