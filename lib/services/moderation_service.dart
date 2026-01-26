import 'package:flutter/material.dart';
import '../models/post.dart';
import '../models/user.dart';
import '../models/feedback.dart' as feedback_model;

class ModerationService {
  // In a real app, these would be fetched from a backend
  static ValueNotifier<List<Post>> postsNotifier = ValueNotifier([]);
  static List<User> users = [];
  static List<feedback_model.Feedback> feedbacks = [];

  // Post moderation
  static void approvePost(String postId) {
    final post = postsNotifier.value.firstWhere((p) => p.id == postId);
    post.moderationStatus = ModerationStatus.approved;
    postsNotifier.value = List.from(postsNotifier.value); // Trigger notification
    print('Approved post $postId');
  }

  static void rejectPost(String postId) {
    final post = postsNotifier.value.firstWhere((p) => p.id == postId);
    post.moderationStatus = ModerationStatus.rejected;
    postsNotifier.value = List.from(postsNotifier.value); // Trigger notification
    print('Rejected post $postId');
  }

  // User moderation
  static void banUser(String userId) {
    final user = users.firstWhere((u) => u.email == userId); // assuming email as id
    user.isBanned = true;
    print('Banned user $userId');
  }

  static void unbanUser(String userId) {
    final user = users.firstWhere((u) => u.email == userId);
    user.isBanned = false;
    print('Unbanned user $userId');
  }

  // Feedback management
  static List<feedback_model.Feedback> getFeedbacks() {
    return feedbacks;
  }

  static void addFeedback(feedback_model.Feedback feedback) {
    feedbacks.add(feedback);
  }

  // Get pending posts
  static List<Post> getPendingPosts() {
    return postsNotifier.value.where((p) => p.moderationStatus == ModerationStatus.pending).toList();
  }

  // Get all users
  static List<User> getUsers() {
    return users;
  }

  // Get post by id
  static Post? getPost(String id) {
    try {
      return postsNotifier.value.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}
