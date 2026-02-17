import 'package:flutter/material.dart';
import '../models/post.dart';
import '../models/user.dart';
import '../models/feedback.dart' as feedback_model;
import '../services/moderation_service.dart';

class ModeratorScreen extends StatefulWidget {
  const ModeratorScreen({super.key});

  @override
  State<ModeratorScreen> createState() => _ModeratorScreenState();
}

class _ModeratorScreenState extends State<ModeratorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final ValueNotifier<List<Post>> _postsNotifier;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _postsNotifier = ModerationService.postsNotifier;
    _postsNotifier.addListener(_onPostsChanged);
  }

  @override
  void dispose() {
    _postsNotifier.removeListener(_onPostsChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onPostsChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderator Panel'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Reported Posts'),
            Tab(text: 'Users'),
            Tab(text: 'Feedbacks'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingPostsTab(),
          _buildUsersTab(),
          _buildFeedbacksTab(),
        ],
      ),
    );
  }

  Widget _buildPendingPostsTab() {
    final pendingPosts =
        _postsNotifier.value
            .where((p) => p.moderationStatus == ModerationStatus.pending)
            .toList();
    return ListView.builder(
      itemCount: pendingPosts.length,
      itemBuilder: (context, index) {
        final post = pendingPosts[index];
        final reportReasons =
            ModerationService.getFeedbacks()
                .where(
                  (f) =>
                      f.type == feedback_model.FeedbackType.report &&
                      f.targetId == post.id,
                )
                .map((f) => f.content)
                .toList();
        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post.content, style: const TextStyle(fontSize: 16)),
                if (post.imageUrls.isNotEmpty) const SizedBox(height: 8),
                if (post.imageUrls.isNotEmpty)
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: post.imageUrls.length,
                      itemBuilder:
                          (context, index) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Image.network(
                              post.imageUrls[index],
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (context, error, stackTrace) =>
                                      const Icon(Icons.error),
                            ),
                          ),
                    ),
                  ),
                if (post.videoUrl != null) const SizedBox(height: 8),
                if (post.videoUrl != null)
                  Container(
                    height: 100,
                    color: Colors.black,
                    child: const Center(
                      child: Text(
                        'Video',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                if (post.taggedLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Location: ${post.taggedLocation!.name}',
                      style: const TextStyle(fontSize: 14, color: Colors.blue),
                    ),
                  ),
                if (post.taggedUsers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Tagged: ${post.taggedUsers.join(', ')}',
                      style: const TextStyle(fontSize: 14, color: Colors.green),
                    ),
                  ),
                const SizedBox(height: 8),
                Text('By: ${post.userName ?? post.userEmail ?? 'Anonymous'}'),
                Text(
                  'Category: ${switch (post.category) {
                    PostCategory.discussion => 'Discussion',
                    PostCategory.live => 'Questions',
                    PostCategory.underReview => 'Tips',
                    PostCategory.routeUpdate => 'Route Update',
                    PostCategory.delayReport => 'Delay Report',
                    PostCategory.safetyAlert => 'Safety Alert',
                    PostCategory.recommendation => 'Recommendation',
                  }}',
                ),
                if (reportReasons.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Reported for: ${reportReasons.join(', ')}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        ModerationService.rejectPost(post.id);
                        setState(() {});
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('Remove'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        ModerationService.approvePost(post.id);
                        setState(() {});
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUsersTab() {
    final users = ModerationService.getUsers();
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: const TextStyle(fontSize: 16)),
                Text(user.email),
                Text('Role: ${user.role.name}'),
                Text('Banned: ${user.isBanned}'),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!user.isBanned)
                      ElevatedButton(
                        onPressed: () {
                          ModerationService.banUser(user.email);
                          setState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('Ban'),
                      )
                    else
                      ElevatedButton(
                        onPressed: () {
                          ModerationService.unbanUser(user.email);
                          setState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: const Text('Unban'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeedbacksTab() {
    final feedbacks =
        ModerationService.getFeedbacks()
            .where((f) => f.type != feedback_model.FeedbackType.report)
            .toList();
    return ListView.builder(
      itemCount: feedbacks.length,
      itemBuilder: (context, index) {
        final feedback = feedbacks[index];
        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Type: ${feedback.type.name}'),
                Text(feedback.content),
                Text('From: ${feedback.userId}'),
                Text('Time: ${feedback.timestamp}'),
              ],
            ),
          ),
        );
      },
    );
  }
}
