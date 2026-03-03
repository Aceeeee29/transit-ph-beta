import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import '../models/route.dart' as route_model;
import '../models/ors_route_result.dart';
import '../services/search_service.dart';
import '../services/gamification_service.dart';
import '../services/routing_service.dart';
import '../services/location_service.dart';
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

  // ORS fallback state
  OrsRouteResult? _orsResult;
  bool _isLoadingOrs = false;
  bool _orsError = false;
  String _orsErrorMessage = '';
  String _lastOrsQuery = '';

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
      // Reset ORS state whenever the query changes
      if (query.trim() != _lastOrsQuery) {
        _orsResult = null;
        _orsError = false;
        _orsErrorMessage = '';
      }
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

  /// Geocodes the destination query to coordinates, then fetches a route
  /// from ORS using the user's current GPS position as the origin.
  Future<void> _fetchOrsRoute() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoadingOrs = true;
      _orsError = false;
      _orsErrorMessage = '';
      _orsResult = null;
      _lastOrsQuery = query;
    });

    try {
      // 1. Get user's current location
      final position = await LocationService.getCurrentPosition();
      if (position == null) {
        setState(() {
          _isLoadingOrs = false;
          _orsError = true;
          _orsErrorMessage =
              'Could not get your current location. Check location permissions.';
        });
        return;
      }
      final origin = LatLng(position.latitude, position.longitude);
      final originName =
          await LocationService.getAddressFromCoordinates(
            position.latitude,
            position.longitude,
          ) ??
          'Current Location';

      // 2. Geocode the destination text to coordinates
      final locations = await locationFromAddress(query);
      if (locations.isEmpty) {
        setState(() {
          _isLoadingOrs = false;
          _orsError = true;
          _orsErrorMessage =
              'Could not find coordinates for "$query". Try a more specific name.';
        });
        return;
      }
      final dest = locations.first;
      final destination = LatLng(dest.latitude, dest.longitude);

      // 3. Fetch from ORS (with Firestore cache)
      final result = await RoutingService.getRoute(
        originName: originName,
        origin: origin,
        destinationName: query,
        destination: destination,
        mode: 'Jeepney',
      );

      if (result == null) {
        setState(() {
          _isLoadingOrs = false;
          _orsError = true;
          _orsErrorMessage =
              'Could not generate a route. Check your ORS API key or try again.';
        });
        return;
      }

      setState(() {
        _isLoadingOrs = false;
        _orsResult = result;
      });
    } catch (e) {
      setState(() {
        _isLoadingOrs = false;
        _orsError = true;
        _orsErrorMessage = 'Unexpected error: $e';
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Search Routes'),
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
                        hintText: 'Search destinations...',
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
                              leading: const Icon(
                                Icons.search,
                                color: Colors.grey,
                              ),
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
    // ── Community routes found ───────────────────────────────────────────────
    if (_filteredRoutes.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredRoutes.length,
        itemBuilder:
            (context, index) => _buildRouteCard(_filteredRoutes[index]),
      );
    }

    // ── No community routes: ORS fallback ────────────────────────────────────
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_isLoadingOrs) ...[
            const SizedBox(height: 60),
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'Generating route from OpenRouteService…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
          ] else if (_orsResult != null) ...[
            // ── Disclaimer banner ──────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Auto-generated route via OpenRouteService — '
                      'not yet verified by the community. '
                      'Road names and distances are estimated.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Route summary card ─────────────────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.blue.shade200, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Icon(
                          Icons.route,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _searchController.text.trim(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Distance + Duration chips
                    Row(
                      children: [
                        _infoChip(
                          Icons.straighten,
                          _orsResult!.distanceLabel,
                          Colors.green,
                        ),
                        const SizedBox(width: 8),
                        _infoChip(
                          Icons.timer_outlined,
                          _orsResult!.durationLabel,
                          Colors.orange,
                        ),
                      ],
                    ),
                    if (_orsResult!.steps.isNotEmpty) ...[
                      const Divider(height: 24),
                      const Text(
                        'Turn-by-turn directions',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Show up to 6 steps to keep the card compact
                      ..._orsResult!.steps
                          .take(6)
                          .map(
                            (step) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.arrow_right,
                                    color: Colors.grey,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      step.instruction,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      if (_orsResult!.steps.length > 6)
                        Text(
                          '+ ${_orsResult!.steps.length - 6} more steps',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Route data cached locally — next search is instant.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ] else ...[
            // ── Initial empty state ────────────────────────────────────────
            const SizedBox(height: 48),
            Icon(Icons.search_off, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No community routes found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This route hasn\'t been contributed yet.\nGenerate a route from OpenRouteService instead.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 28),
            if (_orsError)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _orsErrorMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoadingOrs ? null : _fetchOrsRoute,
                icon: const Icon(Icons.map_outlined, color: Colors.white),
                label: const Text(
                  'Generate Route',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSuggestions() {
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

          // Top Searches Section
          const Text(
            'Top Searches',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Popular routes based on community activity',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          ..._topSearches.map((route) => _buildRouteCard(route)),
        ],
      ),
    );
  }

  Widget _buildRouteCard(route_model.Route route) {
    final score = route.views + route.upvotes - route.downvotes;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _onRouteTap(route),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${route.startLocation} to ${route.endLocation}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$score pts',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
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
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.visibility, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${route.views}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.thumb_up, size: 16, color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${route.upvotes}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.thumb_down, size: 16, color: Colors.red.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${route.downvotes}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
