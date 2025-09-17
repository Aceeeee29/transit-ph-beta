import 'package:flutter/material.dart';
import '../models/post.dart';

class FeedScreen extends StatefulWidget {
  final List<Post> posts;
  final Function(Post) onPostCreated;

  const FeedScreen({
    super.key,
    required this.posts,
    required this.onPostCreated,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabControllerNew;
  int _selectedIndex = 0;

  Map<String, bool> likedPosts = {};
  Map<String, List<String>> postComments = {};

  @override
  void initState() {
    super.initState();
    _tabControllerNew = TabController(length: 4, vsync: this);
    _tabControllerNew!.addListener(() {
      setState(() {
        _selectedIndex = _tabControllerNew!.index;
      });
    });
  }

  @override
  void dispose() {
    _tabControllerNew?.dispose();
    super.dispose();
  }

  Widget buildPostItem(Post post) {
    String displayName =
        post.anonymous
            ? 'Anonymous'
            : (post.userName ?? post.userEmail ?? 'User');
    String initials =
        post.anonymous
            ? 'A'
            : (post.userName != null && post.userName!.isNotEmpty
                ? post.userName![0].toUpperCase()
                : (post.userEmail != null && post.userEmail!.isNotEmpty
                    ? post.userEmail![0].toUpperCase()
                    : 'U'));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.blue.shade100,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${post.timestamp.hour}:${post.timestamp.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        post.category == PostCategory.live
                            ? Colors.green.shade100
                            : post.category == PostCategory.discussion
                            ? Colors.blue.shade100
                            : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    post.category == PostCategory.live
                        ? 'Questions'
                        : post.category == PostCategory.discussion
                        ? 'Discussion'
                        : 'Tips',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(post.content, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      likedPosts[post.id] = !(likedPosts[post.id] ?? false);
                    });
                  },
                  icon: Icon(
                    (likedPosts[post.id] ?? false)
                        ? Icons.thumb_up
                        : Icons.thumb_up_alt_outlined,
                    size: 20,
                    color: (likedPosts[post.id] ?? false) ? Colors.blue : null,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    _showCommentDialog(post.id);
                  },
                  icon: const Icon(Icons.comment_outlined, size: 20),
                ),
              ],
            ),
            if (postComments[post.id]?.isNotEmpty ?? false)
              ...postComments[post.id]!.map(
                (comment) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Comment: $comment',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showCreatePostDialog() {
    showDialog(
      context: context,
      builder:
          (context) => CreatePostDialog(onPostCreated: widget.onPostCreated),
    );
  }

  void _showCommentDialog(String postId) {
    TextEditingController commentController = TextEditingController();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Comment'),
            content: TextField(
              controller: commentController,
              decoration: const InputDecoration(hintText: 'Enter your comment'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (commentController.text.isNotEmpty) {
                    setState(() {
                      postComments[postId] ??= [];
                      postComments[postId]!.add(commentController.text);
                    });
                  }
                  Navigator.pop(context);
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }

  List<Post> get filteredPosts {
    switch (_selectedIndex) {
      case 1:
        return widget.posts
            .where((p) => p.category == PostCategory.discussion)
            .toList();
      case 2:
        return widget.posts
            .where((p) => p.category == PostCategory.live)
            .toList();
      case 3:
        return widget.posts
            .where((p) => p.category == PostCategory.underReview)
            .toList();
      default:
        return widget.posts;
    }
  }

  Widget buildSummaryCard(String label, int count, IconData icon, Color color) {
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                count.toString(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int discussionsCount =
        widget.posts.where((p) => p.category == PostCategory.discussion).length;
    int questionsCount =
        widget.posts
            .where((p) => p.type == PostType.poll)
            .length; // Assuming polls as questions
    int tipsCount =
        widget.posts
            .where((p) => p.category == PostCategory.live)
            .length; // Assuming live as tips

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreatePostDialog,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Community',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ask questions, share tips, help others',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                buildSummaryCard(
                  'Discussions',
                  discussionsCount,
                  Icons.chat_bubble_outline,
                  Colors.blue,
                ),
                const SizedBox(width: 8),
                buildSummaryCard(
                  'Questions',
                  questionsCount,
                  Icons.help_outline,
                  Colors.green,
                ),
                const SizedBox(width: 8),
                buildSummaryCard(
                  'Tips Shared',
                  tipsCount,
                  Icons.trending_up,
                  Colors.purple,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabControllerNew,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue,
              indicatorWeight: 3,
              tabs: const [
                Tab(text: 'All'),
                Tab(text: 'Discussions'),
                Tab(text: 'Questions'),
                Tab(text: 'Tips'),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children:
                    filteredPosts.map((post) => buildPostItem(post)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreatePostDialog extends StatefulWidget {
  final Function(Post) onPostCreated;

  const CreatePostDialog({super.key, required this.onPostCreated});

  @override
  State<CreatePostDialog> createState() => _CreatePostDialogState();
}

class _CreatePostDialogState extends State<CreatePostDialog> {
  final TextEditingController _contentController = TextEditingController();
  PostCategory _selectedCategory = PostCategory.discussion;
  bool _anonymous = false;

  void _createPost() {
    if (_contentController.text.isEmpty) return;

    final post = Post(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userName: _anonymous ? null : 'Current User', // Replace with actual user
      userEmail:
          _anonymous ? null : 'user@example.com', // Replace with actual user
      anonymous: _anonymous,
      content: _contentController.text,
      type: PostType.text,
      category: _selectedCategory,
      timestamp: DateTime.now(),
    );

    widget.onPostCreated(post);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Post'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _contentController,
              decoration: const InputDecoration(
                hintText: 'What\'s on your mind?',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButton<PostCategory>(
              value: _selectedCategory,
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value!;
                });
              },
              items:
                  PostCategory.values.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Text(
                        category == PostCategory.discussion
                            ? 'Discussions'
                            : category == PostCategory.live
                            ? 'Questions'
                            : 'Tips',
                      ),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Anonymous'),
                Switch(
                  value: _anonymous,
                  onChanged: (value) {
                    setState(() {
                      _anonymous = value;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _createPost, child: const Text('Post')),
      ],
    );
  }
}
