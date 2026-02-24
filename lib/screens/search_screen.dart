import 'package:flutter/material.dart';
import '../models/route.dart' as route_model;
import '../services/search_service.dart';
import '../services/gamification_service.dart';
import '../widgets/notification_overlay.dart';
import 'route_map_screen.dart';

class SearchScreen extends StatefulWidget {
  final List<route_model.Route> routes;

  const SearchScreen({super.key, required this.routes});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<String> _recentSearches = [];
  List<route_model.Route> _filteredRoutes = [];
  List<String> _suggestions = [];
  bool _isSearching = false;
  bool _showOmnibox = false;
  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;

  // ─── Color tokens (matches design system) ──────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    final searches = await SearchService.getRecentSearches();
    setState(() {
      _recentSearches = searches;
    });
  }

  void _onSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _filteredRoutes = [];
        _suggestions = [];
        _showOmnibox = false;
      });
      return;
    }

    // Generate omnibox suggestions
    final searchTerm = query.trim().toLowerCase();
    final List<String> newSuggestions = [];

    // Add matching recent searches
    for (final search in _recentSearches) {
      if (search.toLowerCase().contains(searchTerm) &&
          !newSuggestions.contains(search)) {
        newSuggestions.add(search);
      }
    }

    // Add matching locations from routes
    for (final route in widget.routes) {
      if (route.endLocation.toLowerCase().contains(searchTerm) &&
          !newSuggestions.contains(route.endLocation)) {
        newSuggestions.add(route.endLocation);
      }
      if (route.startLocation.toLowerCase().contains(searchTerm) &&
          !newSuggestions.contains(route.startLocation)) {
        newSuggestions.add(route.startLocation);
      }
    }

    // Add matching route descriptions
    for (final route in widget.routes) {
      if (route.shortDescription.toLowerCase().contains(searchTerm)) {
        final suggestion = '${route.startLocation} to ${route.endLocation}';
        if (!newSuggestions.contains(suggestion)) {
          newSuggestions.add(suggestion);
        }
      }
    }

    setState(() {
      _isSearching = true;
      _suggestions = newSuggestions.take(5).toList();
      _showOmnibox = _suggestions.isNotEmpty;
      _filteredRoutes =
          widget.routes.where((route) {
            return route.endLocation.trim().toLowerCase().contains(
                  searchTerm,
                ) ||
                route.startLocation.trim().toLowerCase().contains(searchTerm) ||
                route.shortDescription.trim().toLowerCase().contains(
                  searchTerm,
                );
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
    // Delay hiding omnibox to allow tap on suggestion
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _showOmnibox = false;
        });
      }
    });
  }

  Future<void> _onSearchSubmitted(String query) async {
    if (query.trim().isNotEmpty) {
      await SearchService.addRecentSearch(query.trim());
      await _loadRecentSearches();

      // Award points for searching and check achievements
      final user = await GamificationService.loadUser();
      final unlockedItems = await GamificationService.incrementRoutesSearched(
        user,
      );

      // Show achievement notifications
      if (unlockedItems.isNotEmpty) {
        setState(() {
          _pendingNotifications = unlockedItems;
          _showNotificationOverlay = true;
        });
      }
    }
    _onSearch(query);
  }

  void _onNotificationsDismissed() {
    setState(() {
      _showNotificationOverlay = false;
      _pendingNotifications.clear();
    });
  }

  Future<void> _onRecentSearchTap(String query) async {
    _searchController.text = query;
    await SearchService.addRecentSearch(query);
    await _loadRecentSearches();
    _onSearch(query);
  }

  Future<void> _onClearRecentSearches() async {
    await SearchService.clearRecentSearches();
    setState(() {
      _recentSearches = [];
    });
  }

  Future<void> _onRemoveRecentSearch(String query) async {
    await SearchService.removeRecentSearch(query);
    await _loadRecentSearches();
  }

  /// Get top searches - routes sorted by popularity (views + upvotes - downvotes)
  List<route_model.Route> get _topSearches {
    final sortedRoutes = List<route_model.Route>.from(widget.routes);
    sortedRoutes.sort((a, b) {
      final scoreA = a.views + a.upvotes - a.downvotes;
      final scoreB = b.views + b.upvotes - b.downvotes;
      return scoreB.compareTo(scoreA);
    });
    return sortedRoutes.take(10).toList();
  }

  void _onRouteTap(route_model.Route route) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => RouteMapScreen(route: route)),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ─── Mode chip helpers (shared with HomeScreen) ────────────────────────────

  IconData _modeIconData(String mode) {
    switch (mode) {
      case 'Walk':
        return Icons.directions_walk;
      case 'Jeepney':
        return Icons.directions_bus;
      case 'Bus':
        return Icons.directions_bus_filled;
      case 'Train':
        return Icons.train;
      case 'Tricycle':
        return Icons.pedal_bike;
      case 'FX/Van':
        return Icons.directions_car;
      case 'Ferry':
        return Icons.directions_boat;
      default:
        return Icons.directions_walk;
    }
  }

  Widget _modeChip(String mode) {
    final Map<String, Color> modeColors = {
      'Walk': const Color(0xFF3EC97A),
      'Jeepney': _accent,
      'Bus': _danger,
      'Train': const Color(0xFF9B7FE8),
      'Tricycle': const Color(0xFFE89A3C),
      'FX/Van': const Color(0xFFD4A017),
      'Ferry': const Color(0xFF3EC9D6),
    };
    final color = modeColors[mode] ?? _textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_modeIconData(mode), size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            mode,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ─── Section label helper ──────────────────────────────────────────────────
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
    return Stack(
      children: [
        Scaffold(
          backgroundColor: _bg,
          // ─── AppBar ──────────────────────────────────────────────────────
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
                    Icons.search_rounded,
                    color: _accent,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Search Routes',
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
              // ─── Search Bar (Omnibox) ─────────────────────────────────
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
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search destinations...',
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
                            final isRecent = _recentSearches.contains(
                              suggestion,
                            );
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
                                            isRecent
                                                ? _surfaceAlt
                                                : _accentSoft,
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: Icon(
                                        isRecent
                                            ? Icons.history_rounded
                                            : Icons.location_on_outlined,
                                        size: 14,
                                        color:
                                            isRecent ? _textSecondary : _accent,
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

              // ─── Content ──────────────────────────────────────────────
              Expanded(
                child:
                    _isSearching
                        ? _buildSearchResults()
                        : _buildSearchSuggestions(),
              ),
            ],
          ),
        ),
        if (_showNotificationOverlay)
          NotificationOverlay(
            notifications: _pendingNotifications,
            onAllDismissed: _onNotificationsDismissed,
          ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_filteredRoutes.isEmpty) {
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
              'No routes found',
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
      itemCount: _filteredRoutes.length,
      itemBuilder: (context, index) {
        final route = _filteredRoutes[index];
        return _buildRouteCard(route);
      },
    );
  }

  Widget _buildSearchSuggestions() {
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

          // ─── Top Searches Section ────────────────────────────────────
          Row(
            children: [
              _sectionLabel('Top Searches'),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFECE8),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  '🔥 Trending',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Popular routes based on community activity',
            style: TextStyle(fontSize: 13, color: _textSecondary),
          ),
          const SizedBox(height: 14),
          ..._topSearches.map((route) => _buildRouteCard(route)),
        ],
      ),
    );
  }

  Widget _buildRouteCard(route_model.Route route) {
    final score = route.views + route.upvotes - route.downvotes;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _onRouteTap(route),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${route.startLocation} → ${route.endLocation}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Score badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _accentSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _accent.withOpacity(0.2)),
                    ),
                    child: Text(
                      '$score pts',
                      style: const TextStyle(
                        fontSize: 11,
                        color: _accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                route.shortDescription,
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                  color: _textSecondary,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              // Transport mode chips
              if (route.steps.isNotEmpty)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children:
                      route.steps.map((step) => _modeChip(step.mode)).toList(),
                ),
              const SizedBox(height: 10),
              // Stats row
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _statItem(
                      Icons.visibility_outlined,
                      '${route.views}',
                      _textSecondary,
                    ),
                    const SizedBox(width: 14),
                    _statItem(
                      Icons.thumb_up_outlined,
                      '${route.upvotes}',
                      const Color(0xFF3EC97A),
                    ),
                    const SizedBox(width: 14),
                    _statItem(
                      Icons.thumb_down_outlined,
                      '${route.downvotes}',
                      _danger,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
