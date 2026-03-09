import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post.dart';
import '../models/comment.dart';

class PostService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get all posts
  static Future<List<Post>> getAllPosts() async {
    try {
      final querySnapshot =
          await _firestore
              .collection('posts')
              .where('moderationStatus', isEqualTo: 'approved')
              .orderBy('timestamp', descending: true)
              .get();
      return querySnapshot.docs
          .map((doc) => Post.fromJson(doc.data()))
          .toList();
    } catch (e) {
      print('Error fetching posts: $e');
      return [];
    }
  }

  /// Get posts by user
  static Future<List<Post>> getPostsByUser(String userId) async {
    try {
      final querySnapshot =
          await _firestore
              .collection('posts')
              .where('userId', isEqualTo: userId)
              .get();
      return querySnapshot.docs
          .map((doc) => Post.fromJson(doc.data()))
          .toList();
    } catch (e) {
      print('Error fetching posts for user $userId: $e');
      return [];
    }
  }

  /// Get a specific post by ID
  static Future<Post?> getPostById(String postId) async {
    try {
      final docSnapshot =
          await _firestore.collection('posts').doc(postId).get();
      if (docSnapshot.exists) {
        return Post.fromJson(docSnapshot.data()!);
      }
      return null;
    } catch (e) {
      print('Error fetching post $postId: $e');
      return null;
    }
  }

  /// Save a post to Firestore
  static Future<void> savePost(Post post) async {
    try {
      final data = post.toJson()..remove('timestamp');
      data['timestamp'] = FieldValue.serverTimestamp();
      await _firestore.collection('posts').doc(post.id).set(data);
    } catch (e) {
      print('Error saving post ${post.id}: $e');
      rethrow;
    }
  }

  /// Update an existing post
  static Future<void> updatePost(Post post) async {
    try {
      final data = post.toJson()..remove('timestamp'); // preserve server Timestamp
      await _firestore.collection('posts').doc(post.id).update(data);
    } catch (e) {
      print('Error updating post ${post.id}: $e');
      rethrow;
    }
  }

  /// Delete a post
  static Future<void> deletePost(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).delete();
    } catch (e) {
      print('Error deleting post $postId: $e');
      rethrow;
    }
  }

  /// Like a post
  static Future<void> likePost(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'likeCount': FieldValue.increment(1),
      });
    } catch (e) {
      print('Error liking post $postId: $e');
      rethrow;
    }
  }

  /// Unlike a post
  static Future<void> unlikePost(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'likeCount': FieldValue.increment(-1),
      });
    } catch (e) {
      print('Error unliking post $postId: $e');
      rethrow;
    }
  }

  /// Toggle like on a post
  static Future<void> toggleLike(String postId, String userId) async {
    try {
      final postRef = _firestore.collection('posts').doc(postId);
      await _firestore.runTransaction((transaction) async {
        final postSnapshot = await transaction.get(postRef);
        if (!postSnapshot.exists) return;

        final data = postSnapshot.data()!;
        final likedBy = List<String>.from(data['likedBy'] ?? []);

        if (likedBy.contains(userId)) {
          // Unlike
          transaction.update(postRef, {
            'likedBy': FieldValue.arrayRemove([userId]),
            'likeCount': FieldValue.increment(-1),
          });
        } else {
          // Like
          transaction.update(postRef, {
            'likedBy': FieldValue.arrayUnion([userId]),
            'likeCount': FieldValue.increment(1),
          });
        }
      });
    } catch (e) {
      print('Error toggling like on post $postId: $e');
      rethrow;
    }
  }

  /// Add a comment to a post
  static Future<void> addComment(Comment comment) async {
    try {
      final data =
          comment.toJson()..addAll({'timestamp': FieldValue.serverTimestamp()});
      await _firestore
          .collection('posts')
          .doc(comment.postId)
          .collection('comments')
          .doc(comment.id)
          .set(data);
    } catch (e) {
      print('Error adding comment ${comment.id}: $e');
      rethrow;
    }
  }

  /// Get all comments for a post
  static Future<List<Comment>> getComments(String postId) async {
    try {
      final querySnapshot =
          await _firestore
              .collection('posts')
              .doc(postId)
              .collection('comments')
              .orderBy('timestamp')
              .get();
      final comments =
          querySnapshot.docs
              .map((doc) => Comment.fromJson(doc.data()))
              .toList();

      // Build the comment tree
      final Map<String, Comment> commentMap = {};
      final List<Comment> topLevelComments = [];

      for (final comment in comments) {
        commentMap[comment.id] = comment;
      }

      for (final comment in comments) {
        if (comment.parentId == null) {
          topLevelComments.add(comment);
        } else {
          final parent = commentMap[comment.parentId];
          if (parent != null) {
            commentMap[comment.parentId!] = parent.addReply(comment);
          }
        }
      }

      return topLevelComments.map((c) => commentMap[c.id] ?? c).toList();
    } catch (e) {
      print('Error fetching comments for post $postId: $e');
      return [];
    }
  }

  /// Add a reaction to a post
  static Future<void> addReaction(
    String postId,
    String emoji,
    String userId,
  ) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'reactions.$emoji': FieldValue.arrayUnion([userId]),
      });
    } catch (e) {
      print('Error adding reaction to post $postId: $e');
      rethrow;
    }
  }

  /// Remove a reaction from a post
  static Future<void> removeReaction(
    String postId,
    String emoji,
    String userId,
  ) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'reactions.$emoji': FieldValue.arrayRemove([userId]),
      });
    } catch (e) {
      print('Error removing reaction from post $postId: $e');
      rethrow;
    }
  }
}