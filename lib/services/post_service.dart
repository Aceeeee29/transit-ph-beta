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
      final now = DateTime.now();
      return querySnapshot.docs
          .map((doc) => Post.fromJson(doc.data()))
          .where((post) =>
              post.expiresAt == null || post.expiresAt!.isAfter(now))
          .toList();
    } catch (_) {
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
    } catch (_) {
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
    } catch (_) {
      return null;
    }
  }

  /// Save a post to Firestore
  static Future<void> savePost(Post post) async {
    try {
      final data = post.toJson()..remove('timestamp');
      data['timestamp'] = FieldValue.serverTimestamp();
      data['expiresAt'] = Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 3)),
      );
      await _firestore.collection('posts').doc(post.id).set(data);
    } catch (_) {
      rethrow;
    }
  }

  /// Update an existing post
  static Future<void> updatePost(Post post) async {
    try {
      final data = post.toJson()..remove('timestamp'); // preserve server Timestamp
      await _firestore.collection('posts').doc(post.id).update(data);
    } catch (_) {
      rethrow;
    }
  }

  /// Delete a post and all its sub-collection comments
  static Future<void> deletePost(String postId) async {
    try {
      final commentsSnapshot = await _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .get();
      final batch = _firestore.batch();
      for (final doc in commentsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_firestore.collection('posts').doc(postId));
      await batch.commit();
    } catch (_) {
      rethrow;
    }
  }

  /// Delete all posts whose expiresAt has passed
  static Future<void> deleteExpiredPosts() async {
    try {
      final now = Timestamp.now();
      final expired = await _firestore
          .collection('posts')
          .where('expiresAt', isLessThan: now)
          .get();
      for (final doc in expired.docs) {
        await deletePost(doc.id);
      }
    } catch (_) {
    }
  }

  /// Toggle an upvote/downvote on a post.
  /// Returns true for upvote, false for downvote, null for no vote.
  static Future<bool?> toggleVote(
    String postId,
    String userId, {
    required bool isUpvote,
  }) async {
    try {
      final postRef = _firestore.collection('posts').doc(postId);
      return await _firestore.runTransaction<bool?>((transaction) async {
        final postSnapshot = await transaction.get(postRef);
        if (!postSnapshot.exists) return null;

        final data = postSnapshot.data()!;
        final upvotedBy = List<String>.from(
          data['upvotedBy'] ?? data['likedBy'] ?? [],
        );
        final downvotedBy = List<String>.from(data['downvotedBy'] ?? []);

        final hasUpvoted = upvotedBy.contains(userId);
        final hasDownvoted = downvotedBy.contains(userId);

        final updates = <String, dynamic>{
          'upvotedBy': upvotedBy,
          'downvotedBy': downvotedBy,
          'upvoteCount': (data['upvoteCount'] ?? data['likeCount'] ?? 0),
          'downvoteCount': (data['downvoteCount'] ?? 0),
        };

        if (isUpvote) {
          if (hasUpvoted) {
            updates['upvotedBy'] = List<String>.from(upvotedBy)
              ..remove(userId);
            updates['upvoteCount'] = (updates['upvoteCount'] as int) - 1;
            transaction.update(postRef, updates);
            return null;
          }

          final nextUpvotedBy = List<String>.from(upvotedBy)..add(userId);
          updates['upvotedBy'] = nextUpvotedBy;
          updates['upvoteCount'] = (updates['upvoteCount'] as int) + 1;

          if (hasDownvoted) {
            updates['downvotedBy'] = List<String>.from(downvotedBy)
              ..remove(userId);
            updates['downvoteCount'] = (updates['downvoteCount'] as int) - 1;
          }

          transaction.update(postRef, updates);
          return true;
        }

        if (hasDownvoted) {
          updates['downvotedBy'] = List<String>.from(downvotedBy)
            ..remove(userId);
          updates['downvoteCount'] = (updates['downvoteCount'] as int) - 1;
          transaction.update(postRef, updates);
          return null;
        }

        final nextDownvotedBy = List<String>.from(downvotedBy)..add(userId);
        updates['downvotedBy'] = nextDownvotedBy;
        updates['downvoteCount'] = (updates['downvoteCount'] as int) + 1;

        if (hasUpvoted) {
          updates['upvotedBy'] = List<String>.from(upvotedBy)..remove(userId);
          updates['upvoteCount'] = (updates['upvoteCount'] as int) - 1;
        }

        transaction.update(postRef, updates);
        return false;
      });
    } catch (_) {
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
    } catch (_) {
      rethrow;
    }
  }

  /// Delete a comment by ID, and if it's a top-level comment also delete its replies
  static Future<void> deleteComment(String postId, String commentId, {bool isTopLevel = true}) async {
    try {
      final commentsRef = _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments');

      if (isTopLevel) {
        // Delete all replies first
        final replies = await commentsRef
            .where('parentId', isEqualTo: commentId)
            .get();
        final batch = _firestore.batch();
        for (final doc in replies.docs) {
          batch.delete(doc.reference);
        }
        batch.delete(commentsRef.doc(commentId));
        await batch.commit();
      } else {
        await commentsRef.doc(commentId).delete();
      }
    } catch (_) {
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
    } catch (_) {
      return [];
    }
  }

}