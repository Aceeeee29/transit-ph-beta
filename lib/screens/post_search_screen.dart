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

  // ─── Color tokens (matches design system) ──────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  // ─── Category helpers ───────────────────────────────────────────────────────
  Color _categoryColor(PostCategory cat) => switch (cat) {
    PostCategory.safetyAlert => const Color(0xFFE05C6A),
    PostCategory.delayReport => const Color(0xFFE89A3C),
    PostCategory.live => const Color(0xFF3EC97A),
    PostCategory.recommendation => const Color(0xFF9B7FE8),
    PostCategory.routeUpdate => const Color(0xFF3EC9D6),
    _ => _accent,
  };

  String _categoryLabel(PostCategory cat) => switch (cat) {
    PostCategory.discussion => 'Discussion',
    PostCategory.live => 'Questions',
    PostCategory.underReview => 'Tips',
    PostCategory.routeUpdate => 'Route Update',
    PostCategory.delayReport => 'Delay Report',
    PostCategory.safetyAlert => 'Safety Alert',
    PostCategory.recommendation => 'Recommendation',
  };

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

  // ─── Section label helper ───────────────────────────────────────────────────
  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: _textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      // ─── AppBar ──────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _border),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new,
              size: 15,
              color: _textSecondary,
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.manage_search_rounded,
                color: _accent,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Search Posts',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: Column(
        children: [
          // ─── Search Bar (Omnibox) ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            color: _surface,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: _surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border, width: 1.5),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    autofocus: true,
                    style: const TextStyle(color: _textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search posts, hashtags, users...',
                      hintStyle: const TextStyle(
                        color: _textSecondary,
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: _accent,
                        size: 20,
                      ),
                      suffixIcon:
                          _searchController.text.isNotEmpty
                              ? GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  _onSearch('');
                                },
                                child: Container(
                                  margin: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _border,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: _textSecondary,
                                  ),
                                ),
                              )
                              : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 4,
                      ),
                    ),
                    onChanged: _onSearch,
                    onSubmitted: _onSearchSubmitted,
                    onTap: _onSearchFocus,
                  ),
                ),
                // Omnibox Suggestions
                if (_showOmnibox && _suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _suggestions.length,
                      separatorBuilder:
                          (_, __) => Divider(color: _border, height: 1),
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        final isHashtag = suggestion.startsWith('#');
                        final isRecent = _recentSearches.contains(suggestion);
                        return InkWell(
                          onTap: () => _onSuggestionTap(suggestion),
                          borderRadius: BorderRadius.vertical(
                            top:
                                index == 0
                                    ? const Radius.circular(14)
                                    : Radius.zero,
                            bottom:
                                index == _suggestions.length - 1
                                    ? const Radius.circular(14)
                                    : Radius.zero,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color:
                                        isHashtag
                                            ? const Color(0xFFF3EEFF)
                                            : isRecent
                                            ? _surfaceAlt
                                            : _accentSoft,
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Icon(
                                    isHashtag
                                        ? Icons.tag
                                        : isRecent
                                        ? Icons.history_rounded
                                        : Icons.search_rounded,
                                    size: 14,
                                    color:
                                        isHashtag
                                            ? const Color(0xFF9B7FE8)
                                            : isRecent
                                            ? _textSecondary
                                            : _accent,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    suggestion,
                                    style: const TextStyle(
                                      color: _textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.north_west,
                                  size: 13,
                                  color: _textSecondary,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // ─── Content ─────────────────────────────────────────────────
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
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 36,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No posts found',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try a different search term',
              style: TextStyle(fontSize: 14, color: _textSecondary),
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
          // ─── Recent Searches Section ────────────────────────────────
          if (_recentSearches.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionLabel('Recent Searches'),
                GestureDetector(
                  onTap: _onClearRecentSearches,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _surfaceAlt,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: _border),
                    ),
                    child: const Text(
                      'Clear All',
                      style: TextStyle(
                        fontSize: 11,
                        color: _textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _recentSearches.map((search) {
                    return GestureDetector(
                      onTap: () => _onRecentSearchTap(search),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: _border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.history_rounded,
                              size: 13,
                              color: _textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              search,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _onRemoveRecentSearch(search),
                              child: const Icon(
                                Icons.close,
                                size: 12,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // ─── Trending Hashtags Section ───────────────────────────────
          Row(
            children: [
              _sectionLabel('Trending Hashtags'),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3EEFF),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  '# Hot',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9B7FE8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Popular hashtags from community posts',
            style: TextStyle(fontSize: 13, color: _textSecondary),
          ),
          const SizedBox(height: 14),
          trendingHashtags.isEmpty
              ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.tag, size: 28, color: _textSecondary),
                    SizedBox(height: 8),
                    Text(
                      'No hashtags yet',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
              : Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    trendingHashtags.keys.take(10).map((hashtag) {
                      final count = trendingHashtags[hashtag]!;
                      return GestureDetector(
                        onTap: () => _onSuggestionTap('#$hashtag'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3EEFF),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: const Color(0xFF9B7FE8).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.tag,
                                size: 13,
                                color: Color(0xFF9B7FE8),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                hashtag,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF9B7FE8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF9B7FE8,
                                  ).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '$count',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF9B7FE8),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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

    final catColor = _categoryColor(post.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Card header ────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: post.anonymous ? _surfaceAlt : _accentSoft,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time,
                            size: 11,
                            color: _textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${post.timestamp.hour}:${post.timestamp.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Category badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: catColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: catColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    _categoryLabel(post.category),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: catColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ─── Post content ──────────────────────────────────────
            Text(
              post.content,
              style: const TextStyle(
                fontSize: 14,
                color: _textPrimary,
                height: 1.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),

            // ─── Images ───────────────────────────────────────────
            if (post.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: post.imageUrls.length,
                  itemBuilder:
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            post.imageUrls[index],
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (context, error, stackTrace) => Container(
                                  width: 90,
                                  height: 90,
                                  color: _surfaceAlt,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                    color: _textSecondary,
                                    size: 20,
                                  ),
                                ),
                          ),
                        ),
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
