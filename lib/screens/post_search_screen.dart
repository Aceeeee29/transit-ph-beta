import 'package:flutter/material.dart';
import '../models/post.dart';

class PostSearchScreen extends StatefulWidget {
  final List<Post> posts;

  const PostSearchScreen({super.key, required this.posts});

  @override
  State<PostSearchScreen> createState() => _PostSearchScreenState();
}

class _PostSearchScreenState extends State<PostSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<String> _recentSearches = [];
  List<Post> _filteredPosts = [];
  List<String> _suggestions = [];
  bool _isSearching = false;
  bool _showOmnibox = false;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
  }

  void _loadRecentSearches() {
    // For now, load from a simple list; in real app, use shared prefs
    setState(() {
      _recentSearches = []; // Initialize empty
    });
  }

  void _onSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _filteredPosts = [];
        _suggestions = [];
        _showOmnibox = false;
      });
      return;
    }

    final searchTerm = query.trim().toLowerCase();
    final List<String> newSuggestions = [];

    // Add matching recent searches
    for (final search in _recentSearches) {
      if (search.toLowerCase().contains(searchTerm) &&
          !newSuggestions.contains(search)) {
        newSuggestions.add(search);
      }
    }

    // Add matching hashtags
    final hashtags = _getTrendingHashtags();
    for (final hashtag in hashtags.keys) {
      if (hashtag.toLowerCase().contains(searchTerm) &&
          !newSuggestions.contains('#$hashtag')) {
        newSuggestions.add('#$hashtag');
      }
    }

    setState(() {
      _isSearching = true;
      _suggestions = newSuggestions.take(5).toList();
      _showOmnibox = _suggestions.isNotEmpty;
      _filteredPosts =
          widget.posts.where((post) {
            return post.content.toLowerCase().contains(searchTerm) ||
                post.userName?.toLowerCase().contains(searchTerm) == true ||
                post.userEmail?.toLowerCase().contains(searchTerm) == true;
          }).toList();
    });
  }

  void _onSuggestionTap(String suggestion) {
    _searchController.text = suggestion;
    _onSearchSubmitted(suggestion);
    setState(() {
      _showOmnibox = false;
    });
    _searchFocusNode.unfocus();
  }

  void _onSearchFocus() {
    if (_searchController.text.isNotEmpty && _suggestions.isNotEmpty) {
      setState(() {
        _showOmnibox = true;
      });
    }
  }

  void _onSearchUnfocus() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _showOmnibox = false;
        });
      }
    });
  }

  void _onSearchSubmitted(String query) {
    if (query.trim().isNotEmpty) {
      // Add to recent searches
      if (!_recentSearches.contains(query.trim())) {
        setState(() {
          _recentSearches.insert(0, query.trim());
          if (_recentSearches.length > 10) {
            _recentSearches = _recentSearches.take(10).toList();
          }
        });
      }
    }
    _onSearch(query);
  }

  void _onRecentSearchTap(String query) {
    _searchController.text = query;
    _onSearchSubmitted(query);
  }

  void _onClearRecentSearches() {
    setState(() {
      _recentSearches = [];
    });
  }

  void _onRemoveRecentSearch(String query) {
    setState(() {
      _recentSearches.remove(query);
    });
  }

  Map<String, int> _getTrendingHashtags() {
    final Map<String, int> hashtagCount = {};
    final RegExp hashtagRegex = RegExp(r'#(\w+)');
    for (final post in widget.posts) {
      final matches = hashtagRegex.allMatches(post.content);
      for (final match in matches) {
        final hashtag = match.group(1)!;
        hashtagCount[hashtag] = (hashtagCount[hashtag] ?? 0) + 1;
      }
    }
    // Sort by count descending
    final sorted = Map.fromEntries(
      hashtagCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    return sorted;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Posts'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search Bar (Omnibox)
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search posts...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon:
                        _searchController.text.isNotEmpty
                            ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _onSearch('');
                              },
                            )
                            : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: _onSearch,
                  onSubmitted: _onSearchSubmitted,
                  onTap: _onSearchFocus,
                ),
                // Omnibox Suggestions
                if (_showOmnibox && _suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          leading: const Icon(Icons.search, color: Colors.grey),
                          title: Text(suggestion),
                          onTap: () => _onSuggestionTap(suggestion),
                          dense: true,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Content
          Expanded(
            child:
                _isSearching
                    ? _buildSearchResults()
                    : _buildSearchSuggestions(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_filteredPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No posts found',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredPosts.length,
      itemBuilder: (context, index) {
        final post = _filteredPosts[index];
        return _buildPostCard(post);
      },
    );
  }

  Widget _buildSearchSuggestions() {
    final trendingHashtags = _getTrendingHashtags();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent Searches Section
          if (_recentSearches.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Searches',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: _onClearRecentSearches,
                  child: const Text('Clear All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _recentSearches.map((search) {
                    return ActionChip(
                      label: Text(search),
                      avatar: const Icon(Icons.history, size: 18),
                      onPressed: () => _onRecentSearchTap(search),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // Trending Hashtags Section
          const Text(
            'Trending Hashtags',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Popular hashtags from community posts',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                trendingHashtags.keys.take(10).map((hashtag) {
                  return ActionChip(
                    label: Text('#$hashtag'),
                    avatar: const Icon(Icons.tag, size: 18),
                    onPressed: () => _onSuggestionTap('#$hashtag'),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(Post post) {
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
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                Text(
                  '${post.timestamp.hour}:${post.timestamp.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                        ),
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
