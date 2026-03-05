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
import 'ors_route_map_screen.dart';

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

  // Origin state
  final TextEditingController _originController = TextEditingController();
  bool _useCurrentLocation = true;
  bool _isDetectingLocation = false;

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

  /// Resolves the origin (GPS or typed address), geocodes destination,
  /// then fetches a route from ORS with Firestore caching.
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
      LatLng origin;
      String originName;

      if (_useCurrentLocation) {
        // ── GPS origin ───────────────────────────────────────────────────────
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
        origin = LatLng(position.latitude, position.longitude);
        originName =
            await LocationService.getAddressFromCoordinates(
              position.latitude,
              position.longitude,
            ) ??
            'Current Location';
      } else {
        // ── Custom typed origin ──────────────────────────────────────────────
        final originText = _originController.text.trim();
        if (originText.isEmpty) {
          setState(() {
            _isLoadingOrs = false;
            _orsError = true;
            _orsErrorMessage = 'Please enter a starting point.';
          });
          return;
        }
        final originLocations = await locationFromAddress(originText);
        if (originLocations.isEmpty) {
          setState(() {
            _isLoadingOrs = false;
            _orsError = true;
            _orsErrorMessage =
                'Could not find "$originText". Try a more specific address.';
          });
          return;
        }
        origin = LatLng(
          originLocations.first.latitude,
          originLocations.first.longitude,
        );
        originName = originText;
      }

      // ── Geocode destination ─────────────────────────────────────────────────
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
      final destination = LatLng(
        locations.first.latitude,
        locations.first.longitude,
      );

      // ── Fetch from ORS (with Firestore cache) ──────────────────────────────
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

  /// Detects GPS location and fills the origin text field.
  Future<void> _detectAndFillOrigin() async {
    setState(() => _isDetectingLocation = true);
    final position = await LocationService.getCurrentPosition();
    if (position != null) {
      final address =
          await LocationService.getAddressFromCoordinates(
            position.latitude,
            position.longitude,
          ) ??
          'Current Location';
      _originController.text = address;
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not detect location. Check permissions.'),
          ),
        );
      }
    }
    setState(() => _isDetectingLocation = false);
  }

  void _showSearchHelpSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder:
                (_, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Title
                      Row(
                        children: [
                          Icon(
                            Icons.help_outline,
                            color: Colors.blue.shade700,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Search & Route Tips',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Section 1: Recommended format ──────────────────────────────
                      _helpSectionTitle('✅ Recommended Format'),
                      const SizedBox(height: 8),
                      _helpCard(
                        color: Colors.green.shade50,
                        border: Colors.green.shade200,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Landmark or Street, City/Municipality',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _exampleRow(
                              '✓',
                              'SM Megamall, Mandaluyong',
                              Colors.green.shade700,
                            ),
                            _exampleRow(
                              '✓',
                              'Quezon City Hall, Quezon City',
                              Colors.green.shade700,
                            ),
                            _exampleRow(
                              '✓',
                              'NAIA Terminal 3, Pasay',
                              Colors.green.shade700,
                            ),
                            _exampleRow(
                              '✓',
                              'Ayala MRT Station, Makati',
                              Colors.green.shade700,
                            ),
                            _exampleRow(
                              '✓',
                              'Robinsons Place Manila, Ermita',
                              Colors.green.shade700,
                            ),
                            _exampleRow(
                              '✓',
                              'UST, Sampaloc, Manila',
                              Colors.green.shade700,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Section 2: What to avoid ───────────────────────────────────
                      _helpSectionTitle('❌ Inputs That May Fail'),
                      const SizedBox(height: 8),
                      _helpCard(
                        color: Colors.red.shade50,
                        border: Colors.red.shade200,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _exampleRow(
                              '✗',
                              '"Mall" — too vague',
                              Colors.red.shade700,
                            ),
                            _exampleRow(
                              '✗',
                              '"Cubao" — no city context',
                              Colors.red.shade700,
                            ),
                            _exampleRow(
                              '✗',
                              '"Home" — not a real address',
                              Colors.red.shade700,
                            ),
                            _exampleRow(
                              '✗',
                              '"EDSA" — a road, not a point',
                              Colors.red.shade700,
                            ),
                            _exampleRow(
                              '✗',
                              '"School" — too generic',
                              Colors.red.shade700,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tip: If a search fails, try adding the city name after a comma.',
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Section 3: Community vs Generated ─────────────────────────
                      _helpSectionTitle(
                        '🗺️ Community Routes vs Generated Routes',
                      ),
                      const SizedBox(height: 8),
                      _helpCard(
                        color: Colors.blue.shade50,
                        border: Colors.blue.shade200,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _infoRow(
                              Icons.people_alt_outlined,
                              'Community Routes',
                              'Contributed by real commuters. Includes accurate jeepney codes, stops, and fares.',
                              Colors.blue.shade700,
                            ),
                            const SizedBox(height: 10),
                            _infoRow(
                              Icons.map_outlined,
                              'Generated Routes (ORS)',
                              'Auto-generated using OpenRouteService. Transit modes and fares are estimated — verify locally.',
                              Colors.orange.shade700,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Section 4: Starting point tips ─────────────────────────────
                      _helpSectionTitle('📍 Starting Point Tips'),
                      const SizedBox(height: 8),
                      _helpCard(
                        color: Colors.purple.shade50,
                        border: Colors.purple.shade200,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _infoRow(
                              Icons.my_location,
                              'My Location (GPS)',
                              'Uses your current GPS position. Make sure location permission is granted.',
                              Colors.purple.shade700,
                            ),
                            const SizedBox(height: 10),
                            _infoRow(
                              Icons.edit_location_alt_outlined,
                              'Enter Address',
                              'Type any landmark or address as your starting point. Use the same format as the destination.',
                              Colors.purple.shade700,
                            ),
                            const SizedBox(height: 10),
                            _infoRow(
                              Icons.gps_fixed,
                              'GPS Fill button',
                              'Inside "Enter Address" mode, tap the GPS icon to auto-fill your current location into the field — then edit it if needed.',
                              Colors.purple.shade700,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Section 5: Fare disclaimer ─────────────────────────────────
                      _helpSectionTitle('💰 About Estimated Fares'),
                      const SizedBox(height: 8),
                      _helpCard(
                        color: Colors.amber.shade50,
                        border: Colors.amber.shade300,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Fares shown for generated routes are estimates based on LTFRB 2025–2026 rates and the calculated road distance.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.amber.shade900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _exampleRow(
                              '•',
                              'Jeepney: ₱13 base + ₱1.80/km',
                              Colors.amber.shade900,
                            ),
                            _exampleRow(
                              '•',
                              'Bus: ₱13–15 base + ₱1.85–2.65/km',
                              Colors.amber.shade900,
                            ),
                            _exampleRow(
                              '•',
                              'FX/Van: ₱35 base + ₱4.00/km',
                              Colors.amber.shade900,
                            ),
                            _exampleRow(
                              '•',
                              'Tricycle: ₱15 base + ₱5.00/km',
                              Colors.amber.shade900,
                            ),
                            _exampleRow(
                              '•',
                              'Train: ₱20 base',
                              Colors.amber.shade900,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'A ±15% range is shown to account for real-world variance. Always confirm with the driver or station.',
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: Colors.amber.shade900,
                              ),
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

  Widget _helpSectionTitle(String title) => Text(
    title,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
  );

  Widget _helpCard({
    required Color color,
    required Color border,
    required Widget child,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: border),
    ),
    child: child,
  );

  Widget _exampleRow(String prefix, String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          prefix,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, color: color)),
        ),
      ],
    ),
  );

  Widget _infoRow(IconData icon, String title, String body, Color color) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              body,
              style: TextStyle(fontSize: 12, color: color.withOpacity(0.85)),
            ),
          ],
        ),
      ),
    ],
  );

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _originController.dispose();
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
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: 'Search tips',
                onPressed: _showSearchHelpSheet,
              ),
            ],
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
                    // Distance + Duration + Fare chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _infoChip(
                          Icons.straighten,
                          _orsResult!.distanceLabel,
                          Colors.green,
                        ),
                        _infoChip(
                          Icons.timer_outlined,
                          _orsResult!.durationLabel,
                          Colors.orange,
                        ),
                        _infoChip(
                          Icons.payments_outlined,
                          _totalFareRange(),
                          Colors.green.shade700,
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
                                  _stepModeIcon(step.suggestedMode),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _stepModeColor(
                                              step.suggestedMode,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            step.suggestedMode,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          step.instruction,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
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
            const SizedBox(height: 16),
            // ── View on Map button ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => OrsRouteMapScreen(
                            result: _orsResult!,
                            destinationName: _searchController.text.trim(),
                          ),
                    ),
                  );
                },
                icon: const Icon(Icons.map, color: Colors.white),
                label: const Text(
                  'View on Map',
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
          ] else ...[
            // ── Initial empty state ────────────────────────────────────────
            const SizedBox(height: 32),
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No community routes found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Generate a route using OpenRouteService instead.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),

            // ── Origin selector ────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.blue.shade100),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Starting point',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Toggle row
                  Row(
                    children: [
                      GestureDetector(
                        onTap:
                            () => setState(() {
                              _useCurrentLocation = true;
                              _originController.clear();
                            }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color:
                                _useCurrentLocation
                                    ? Colors.blue.shade700
                                    : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  _useCurrentLocation
                                      ? Colors.blue.shade700
                                      : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.my_location,
                                size: 15,
                                color:
                                    _useCurrentLocation
                                        ? Colors.white
                                        : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'My location',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      _useCurrentLocation
                                          ? Colors.white
                                          : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap:
                            () => setState(() {
                              _useCurrentLocation = false;
                            }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color:
                                !_useCurrentLocation
                                    ? Colors.blue.shade700
                                    : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  !_useCurrentLocation
                                      ? Colors.blue.shade700
                                      : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.edit_location_alt_outlined,
                                size: 15,
                                color:
                                    !_useCurrentLocation
                                        ? Colors.white
                                        : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Enter address',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      !_useCurrentLocation
                                          ? Colors.white
                                          : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Custom address field (animated)
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 220),
                    crossFadeState:
                        _useCurrentLocation
                            ? CrossFadeState.showFirst
                            : CrossFadeState.showSecond,
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _originController,
                              decoration: InputDecoration(
                                hintText:
                                    'e.g. Quezon City Hall, EDSA Cubao...',
                                hintStyle: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade400,
                                ),
                                prefixIcon: Icon(
                                  Icons.location_on_outlined,
                                  color: Colors.blue.shade600,
                                  size: 20,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              ),
                              textInputAction: TextInputAction.done,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // GPS fill button
                          IconButton.filled(
                            onPressed:
                                _isDetectingLocation
                                    ? null
                                    : _detectAndFillOrigin,
                            icon:
                                _isDetectingLocation
                                    ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                    : const Icon(Icons.my_location, size: 18),
                            tooltip: 'Use GPS location',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.blue.shade600,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

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

  String _totalFareRange() {
    if (_orsResult == null) return '₱0';
    final total = _orsResult!.steps.fold(
      0.0,
      (sum, s) => sum + s.estimatedFare,
    );
    if (total == 0) return 'Free';
    final low = (total * 0.9).round();
    final high = (total * 1.15).round();
    return '₱$low–$high';
  }

  Widget _stepModeIcon(String mode) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: _stepModeColor(mode).withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(color: _stepModeColor(mode), width: 1.2),
      ),
      child: Icon(
        _stepModeIconData(mode),
        size: 14,
        color: _stepModeColor(mode),
      ),
    );
  }

  IconData _stepModeIconData(String mode) {
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
        return Icons.two_wheeler;
      case 'FX/Van':
        return Icons.airport_shuttle;
      case 'Ferry':
        return Icons.directions_boat;
      default:
        return Icons.directions_bus;
    }
  }

  Color _stepModeColor(String mode) {
    switch (mode) {
      case 'Walk':
        return Colors.green.shade600;
      case 'Jeepney':
        return Colors.blue.shade600;
      case 'Bus':
        return Colors.red.shade600;
      case 'Train':
        return Colors.purple.shade600;
      case 'Tricycle':
        return Colors.orange.shade600;
      case 'FX/Van':
        return Colors.amber.shade700;
      case 'Ferry':
        return Colors.lightBlue.shade600;
      default:
        return Colors.blue.shade600;
    }
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
  