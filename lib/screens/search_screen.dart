import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import '../models/route.dart' as route_model;
import '../models/ors_route_result.dart';
import '../repositories/route_cache_repository.dart';
import '../services/search_service.dart';
import '../services/gamification_service.dart';
import '../services/routing_service.dart';
import '../services/location_service.dart';
import '../services/route_metrics_service.dart';
import '../services/route_service.dart';
import '../services/supabase_route_service.dart';

import '../widgets/notification_overlay.dart';
import '../widgets/search/route_generation_notice_dialog.dart';
import '../widgets/search/search_help_sheet.dart';
import '../widgets/search/search_route_card.dart';
import 'downloaded_routes_screen.dart';
import 'route_map_screen.dart';
import 'ors_route_map_screen.dart';
part 'search_screen_sections.dart';
part 'search_screen_route_generation_sections.dart';
part 'search_screen_discovery_sections.dart';

enum ContributedRouteSortMode { balanced, budget, fastest }

class SearchScreen extends StatefulWidget {
  final List<route_model.Route> routes;
  final Future<void> Function()? onRefresh;

  const SearchScreen({super.key, required this.routes, this.onRefresh});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _originController = TextEditingController();

  List<String> _recentSearches = [];
  List<route_model.Route> _routes = [];
  List<route_model.Route> _filteredRoutes = [];
  List<String> _suggestions = [];
  bool _isSearching = false;
  bool _showOmnibox = false;
  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;
  ContributedRouteSortMode _contributedSortMode =
      ContributedRouteSortMode.balanced;

  static const Set<String> _otherSuggestionTags = {
    'Tourist',
    'Budget',
    'Fast',
    'Accessible',
  };

  // ─── Color tokens ─────────────────────────────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  // ─── Route state ──────────────────────────────────────────────────────────
  OrsRouteResult? _orsResult;
  bool _isLoadingOrs = false;
  bool _orsError = false;
  String _orsErrorMessage = '';
  String _lastOrsQuery = '';
  List<DijkstraRouteAlternative> _routeAlternatives = [];
  Map<int, OrsRouteResult> _fallbackAlternativeRoutes = <int, OrsRouteResult>{};
  Map<int, String> _alternativeLabels = <int, String>{};
  int _selectedAlternativeIndex = 0;
  LatLng? _lastOriginForAlternatives;
  LatLng? _lastDestinationForAlternatives;
  String? _lastGeneratedOriginName;
  String? _lastGeneratedDestinationName;

  // ─── Origin state ─────────────────────────────────────────────────────────
  bool _useCurrentLocation = true;
  bool _isDetectingLocation = false;

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _routes = List<route_model.Route>.from(widget.routes);
    _loadRecentSearches();
    _refreshRoutes();
  }

  Future<void> _refreshRoutes() async {
    try {
      final latest = await RouteService.getAllRoutes();
      if (!mounted) return;
      setState(() {
        _routes = latest;
      });
    } catch (_) {
      // Keep existing in-memory routes if refresh fails.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _originController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final searches = await SearchService.getRecentSearches();
    setState(() => _recentSearches = searches);
  }

  // ─── Philippines-biased geocoding ─────────────────────────────────────────

  Future<LatLng?> _geocodePhilippines(String query) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '5',
        'countrycodes': 'ph',
        'viewbox': '116.0,4.5,127.0,21.5',
        'bounded': '0',
        'accept-language': 'en',
      });

      final response = await http
          .get(
            uri,
            headers: {'User-Agent': 'TransitPH/1.0 (transit-routing-app)'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final results = jsonDecode(response.body) as List;
        if (results.isNotEmpty) {
          Map<String, dynamic>? best;
          for (final r in results.cast<Map<String, dynamic>>()) {
            final lat = double.tryParse(r['lat'] as String? ?? '') ?? 0;
            final lng = double.tryParse(r['lon'] as String? ?? '') ?? 0;
            if (lat >= 4.5 && lat <= 21.5 && lng >= 116.0 && lng <= 127.0) {
              best = r;
              break;
            }
          }
          best ??= results.first as Map<String, dynamic>;
          final lat = double.parse(best['lat'] as String);
          final lng = double.parse(best['lon'] as String);
          return LatLng(lat, lng);
        }
      }
    } catch (e) {
      debugPrint('[Geocoding] Nominatim error for "$query": $e');
    }

    try {
      final locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        final phLocations =
            locations
                .where(
                  (l) =>
                      l.latitude >= 4.5 &&
                      l.latitude <= 21.5 &&
                      l.longitude >= 116.0 &&
                      l.longitude <= 127.0,
                )
                .toList();
        final loc =
            phLocations.isNotEmpty ? phLocations.first : locations.first;
        return LatLng(loc.latitude, loc.longitude);
      }
    } catch (e) {
      debugPrint('[Geocoding] Fallback error for "$query": $e');
    }

    return null;
  }

  // ─── Search logic ─────────────────────────────────────────────────────────

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

    final searchTerm = query.trim().toLowerCase();
    final newSuggestions = <String>[];

    for (final s in _recentSearches) {
      if (s.toLowerCase().contains(searchTerm) && !newSuggestions.contains(s)) {
        newSuggestions.add(s);
      }
    }
    for (final route in _routes) {
      if (route.endLocation.toLowerCase().contains(searchTerm) &&
          !newSuggestions.contains(route.endLocation)) {
        newSuggestions.add(route.endLocation);
      }
      if (route.startLocation.toLowerCase().contains(searchTerm) &&
          !newSuggestions.contains(route.startLocation)) {
        newSuggestions.add(route.startLocation);
      }
    }
    for (final route in _routes) {
      if (route.shortDescription.toLowerCase().contains(searchTerm)) {
        final suggestion = '${route.startLocation} to ${route.endLocation}';
        if (!newSuggestions.contains(suggestion)) {
          newSuggestions.add(suggestion);
        }
      }
      for (final tag in route.audienceTags) {
        if (_otherSuggestionTags.contains(tag) &&
            tag.toLowerCase().contains(searchTerm) &&
            !newSuggestions.contains(tag)) {
          newSuggestions.add(tag);
        }
      }
    }

    newSuggestions.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    setState(() {
      _isSearching = true;
      _suggestions = newSuggestions.take(5).toList();
      _showOmnibox = _suggestions.isNotEmpty;
      // Only show approved routes in search results
      _filteredRoutes =
          _routes.where((r) {
              return r.isApproved &&
                  (r.endLocation.trim().toLowerCase().contains(searchTerm) ||
                      r.startLocation.trim().toLowerCase().contains(
                        searchTerm,
                      ) ||
                      r.shortDescription.trim().toLowerCase().contains(
                        searchTerm,
                      ) ||
                      r.audienceTags.any(
                        (t) => t.toLowerCase().contains(searchTerm),
                      ));
            }).toList()
            ..sort((a, b) {
              final scoreB =
                  _communityReliabilityScore(b) + _suggestionTagScore(b);
              final scoreA =
                  _communityReliabilityScore(a) + _suggestionTagScore(a);
              return scoreB.compareTo(scoreA);
            });
      if (query.trim() != _lastOrsQuery) {
        _orsResult = null;
        _orsError = false;
        _orsErrorMessage = '';
        _routeAlternatives = [];
        _fallbackAlternativeRoutes = <int, OrsRouteResult>{};
        _alternativeLabels = <int, String>{};
        _selectedAlternativeIndex = 0;
        _lastOriginForAlternatives = null;
        _lastDestinationForAlternatives = null;
      }
    });
  }

  void _onSuggestionTap(String suggestion) {
    _searchController.text = suggestion;
    _onSearchSubmitted(suggestion);
    setState(() => _showOmnibox = false);
    _searchFocusNode.unfocus();
  }

  void _onSearchFocus() {
    if (_searchController.text.isNotEmpty && _suggestions.isNotEmpty) {
      setState(() => _showOmnibox = true);
    }
  }

  Future<void> _onSearchSubmitted(String query) async {
    await _refreshRoutes();
    if (query.trim().isNotEmpty) {
      await SearchService.addRecentSearch(query.trim());
      await _loadRecentSearches();
      final user = await GamificationService.loadUser();
      final unlockedItems = await GamificationService.incrementRoutesSearched(
        user,
      );
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
    setState(() => _recentSearches = []);
  }

  Future<void> _onRemoveRecentSearch(String query) async {
    await SearchService.removeRecentSearch(query);
    await _loadRecentSearches();
  }

  void _onRouteTap(route_model.Route route) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RouteMapScreen(route: route)));
  }

  List<route_model.Route> get _topSearches {
    // Only show approved routes in top searches
    final sorted = _routes.where((r) => r.isApproved).toList();
    sorted.sort((a, b) {
      final scoreA = _communityReliabilityScore(a) + _suggestionTagScore(a);
      final scoreB = _communityReliabilityScore(b) + _suggestionTagScore(b);
      return scoreB.compareTo(scoreA);
    });
    return sorted.take(10).toList();
  }

  int _suggestionTagScore(route_model.Route route) {
    if (route.audienceTags.isEmpty) return 0;
    final matches =
        route.audienceTags
            .where((t) => _otherSuggestionTags.contains(t))
            .length;
    return matches * 10;
  }

  int _communityReliabilityScore(route_model.Route route) {
    final engagement = route.views + route.upvotes - route.downvotes;
    final hasRouteSchedule =
        (route.schedule?.trim().isNotEmpty ?? false) ? 25 : 0;

    final transportSteps = route.steps.where((s) => s.mode != 'Walk').toList();
    final hasAnyTransportStep = transportSteps.isNotEmpty;

    final scheduleComplete =
        hasAnyTransportStep &&
        transportSteps.every(
          (s) =>
              s.is24_7 ||
              ((s.startTime?.trim().isNotEmpty ?? false) &&
                  (s.endTime?.trim().isNotEmpty ?? false)),
        );
    final fareComplete =
        hasAnyTransportStep &&
        transportSteps.every((s) => s.actualFare != null && s.actualFare! >= 0);

    return engagement +
        hasRouteSchedule +
        (scheduleComplete ? 40 : 0) +
        (fareComplete ? 35 : 0) +
        (route.isApproved ? 1000 : 0);
  }

  double? _extractFirstNumber(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  double _routeEstimatedFare(route_model.Route route) {
    final fromPrice = _extractFirstNumber(route.price);
    if (fromPrice != null) return fromPrice;

    final transportSteps = route.steps.where((s) => s.mode != 'Walk').toList();
    if (transportSteps.isEmpty) return 0;

    final totalDistanceKm =
        route.distanceMeters != null && route.distanceMeters! > 0
            ? route.distanceMeters! / 1000
            : (RouteMetricsService.parseDistanceToKm(route.distance) ?? 5.0);
    final perStepDistance = totalDistanceKm / transportSteps.length;

    var total = 0.0;
    for (final step in transportSteps) {
      total +=
          step.actualFare ??
          RouteMetricsService.calculateFareForMode(step.mode, perStepDistance);
    }
    return total;
  }

  int _routeEstimatedMinutes(route_model.Route route) {
    final parsedEta = int.tryParse(
      (route.eta ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
    );
    if (parsedEta != null && parsedEta > 0) return parsedEta;

    final distanceKm =
        route.distanceMeters != null && route.distanceMeters! > 0
            ? route.distanceMeters! / 1000
            : (RouteMetricsService.parseDistanceToKm(route.distance) ?? 5.0);

    final hasTrain = route.steps.any((s) => s.mode == 'Train');
    final speed = hasTrain ? 28.0 : 20.0;
    final minutes = ((distanceKm / speed) * 60).ceil();
    final transferPenalty =
        (route.steps.where((s) => s.mode != 'Walk').length - 1) * 4;
    return (minutes + transferPenalty).clamp(8, 180);
  }

  List<route_model.Route> _sortContributedRoutes(
    List<route_model.Route> routes,
    ContributedRouteSortMode mode,
  ) {
    final sorted = List<route_model.Route>.from(routes);
    sorted.sort((a, b) {
      switch (mode) {
        case ContributedRouteSortMode.budget:
          final fareCmp = _routeEstimatedFare(
            a,
          ).compareTo(_routeEstimatedFare(b));
          if (fareCmp != 0) return fareCmp;
          return _routeEstimatedMinutes(a).compareTo(_routeEstimatedMinutes(b));
        case ContributedRouteSortMode.fastest:
          final timeCmp = _routeEstimatedMinutes(
            a,
          ).compareTo(_routeEstimatedMinutes(b));
          if (timeCmp != 0) return timeCmp;
          return _routeEstimatedFare(a).compareTo(_routeEstimatedFare(b));
        case ContributedRouteSortMode.balanced:
          final aScore =
              _routeEstimatedFare(a) * 0.6 + _routeEstimatedMinutes(a) * 0.4;
          final bScore =
              _routeEstimatedFare(b) * 0.6 + _routeEstimatedMinutes(b) * 0.4;
          final cmp = aScore.compareTo(bScore);
          if (cmp != 0) return cmp;
          return _communityReliabilityScore(
            b,
          ).compareTo(_communityReliabilityScore(a));
      }
    });
    return sorted;
  }

  String _alternativeRouteSignature(DijkstraRouteAlternative alt) {
    return alt.result.plan.legs
        .map((leg) => '${leg.routeId}:${leg.tripId}:${leg.boardStopId}:${leg.alightStopId}')
        .join('>');
  }

  DijkstraRouteAlternative? _pickAlternativeFromPool(
    List<DijkstraRouteAlternative> pool,
    Set<String> selectedSignatures,
    List<DijkstraRouteAlternative> merged,
  ) {
    for (final alt in pool) {
      final sig = _alternativeRouteSignature(alt);
      if (!selectedSignatures.contains(sig)) return alt;
    }
    for (final alt in merged) {
      final sig = _alternativeRouteSignature(alt);
      if (!selectedSignatures.contains(sig)) return alt;
    }
    return null;
  }

  DijkstraRouteAlternative? _pickStrictAlternativeFromPool(
    List<DijkstraRouteAlternative> pool,
    Set<String> selectedSignatures,
  ) {
    for (final alt in pool) {
      final sig = _alternativeRouteSignature(alt);
      if (!selectedSignatures.contains(sig)) return alt;
    }
    return null;
  }

  bool _alternativeHasTrain(DijkstraRouteAlternative alt) {
    for (final leg in alt.result.plan.legs) {
      final routeType = leg.routeType;
      final isTrainType =
          routeType == 0 ||
          routeType == 1 ||
          routeType == 2 ||
          routeType == 12 ||
          ((routeType ?? -1) >= 100 && (routeType ?? -1) <= 117) ||
          ((routeType ?? -1) >= 400 && (routeType ?? -1) <= 405) ||
          ((routeType ?? -1) >= 900 && (routeType ?? -1) <= 906);
      if (isTrainType) return true;

      final name = '${leg.routeShortName ?? ''} ${leg.routeLongName ?? ''}'.toLowerCase();
      if (name.contains('mrt') ||
          name.contains('lrt') ||
          name.contains('pnr') ||
          name.contains('rail') ||
          name.contains('train')) {
        return true;
      }
    }
    return false;
  }

  bool _alternativeHasCarousel(DijkstraRouteAlternative alt) {
    for (final leg in alt.result.plan.legs) {
      final name =
          '${leg.routeShortName ?? ''} ${leg.routeLongName ?? ''}'.toLowerCase();
      if (name.contains('edsa') && name.contains('carousel')) {
        return true;
      }
      if (name.contains('carousel busway')) {
        return true;
      }
    }
    return false;
  }

  List<route_model.Route> _topThreeModePicks(List<route_model.Route> routes) {
    if (routes.isEmpty) return const <route_model.Route>[];

    final budgetTop =
        _sortContributedRoutes(routes, ContributedRouteSortMode.budget).first;
    final fastestTop =
        _sortContributedRoutes(routes, ContributedRouteSortMode.fastest).first;
    final balancedTop =
        _sortContributedRoutes(routes, ContributedRouteSortMode.balanced).first;

    final picks = <route_model.Route>[];
    final seen = <String>{};
    for (final r in [balancedTop, budgetTop, fastestTop]) {
      if (seen.add(r.id)) picks.add(r);
    }

    if (picks.length < 3) {
      final byBalanced = _sortContributedRoutes(
        routes,
        ContributedRouteSortMode.balanced,
      );
      for (final r in byBalanced) {
        if (seen.add(r.id)) picks.add(r);
        if (picks.length == 3) break;
      }
    }

    return picks;
  }

  // ─── Route generation ─────────────────────────────────────────────────────

  Future<void> _fetchOrsRoute() async {
    await this._fetchOrsRouteSection();
  }

  Future<void> _onGenerateRoutePressed() async {
    if (_isLoadingOrs) return;

    final proceed = await RouteGenerationNoticeDialog.shouldProceed(context);
    if (!mounted || !proceed) return;

    await _fetchOrsRoute();
  }

  Future<void> _selectAlternative(int index) async {
    if (_isLoadingOrs) return;
    if (index < 0 || index >= _routeAlternatives.length) return;
    if (_lastOriginForAlternatives == null ||
        _lastDestinationForAlternatives == null) {
      return;
    }

    final fallbackRoute = _fallbackAlternativeRoutes[index];
    if (fallbackRoute != null) {
      setState(() {
        _orsResult = fallbackRoute;
        _selectedAlternativeIndex = index;
      });
      return;
    }

    setState(() {
      _isLoadingOrs = true;
      _orsError = false;
      _orsErrorMessage = '';
    });

    try {
      final next = await RoutingService.buildRouteFromDijkstraAlternative(
        origin: _lastOriginForAlternatives!,
        destination: _lastDestinationForAlternatives!,
        alternative: _routeAlternatives[index].result,
        preferredMode: 'Auto',
      );

      final originName = _lastGeneratedOriginName;
      final destinationName = _lastGeneratedDestinationName;
      if (originName != null && destinationName != null) {
        await RouteCacheRepository.put(
          originName,
          destinationName,
          'Auto',
          'supabase-gtfs-v11',
          next,
        );
      }

      if (!mounted) return;
      setState(() {
        _orsResult = next;
        _selectedAlternativeIndex = index;
        _isLoadingOrs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingOrs = false;
        _orsError = true;
        _orsErrorMessage = 'Failed to build selected alternative route: $e';
      });
    }
  }

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
      builder: (_) => const SearchHelpSheet(),
    );
  }

  void _openDownloadedRoutes() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DownloadedRoutesScreen()),
    );
  }

  // ─── ORS helpers ──────────────────────────────────────────────────────────

  String _totalFareRange() {
    if (_orsResult == null) return '₱0';
    final total = _orsResult!.steps.fold(
      0.0,
      (sum, s) => sum + s.estimatedFare,
    );
    if (total == 0) return 'Free';
    return '₱${(total * 0.9).round()}–${(total * 1.15).round()}';
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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

  Widget _stepModeIcon(String mode) {
    final color = _stepModeColor(mode);
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.2),
      ),
      child: Icon(_stepModeIconData(mode), size: 14, color: color),
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

  /// Builds a SearchRouteCard with inline verified check in the card header.
  Widget _routeCardWithBadge(route_model.Route route) {
    return this._routeCardWithBadgeSection(route);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: _bg,
          appBar: _buildAppBar(),
          body: Column(
            children: [
              _buildSearchBar(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await widget.onRefresh?.call();
                    await _refreshRoutes();
                    await _loadRecentSearches();
                    if (_searchController.text.trim().isNotEmpty) {
                      _onSearch(_searchController.text.trim());
                    }
                  },
                  color: _accent,
                  child:
                      _isSearching
                          ? _buildSearchResults()
                          : _buildSearchSuggestions(),
                ),
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

  AppBar _buildAppBar() {
    return AppBar(
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
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: _openDownloadedRoutes,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: _border),
              ),
              child: const Icon(
                Icons.download_for_offline_rounded,
                size: 17,
                color: _accent,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: _showSearchHelpSheet,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: _border),
              ),
              child: const Icon(
                Icons.help_outline_rounded,
                size: 17,
                color: _textSecondary,
              ),
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
    );
  }

  void _setContributedSortMode(ContributedRouteSortMode mode) {
    setState(() => _contributedSortMode = mode);
  }

  void _setOriginUseCurrentLocation() {
    setState(() {
      _useCurrentLocation = true;
      _originController.clear();
    });
  }

  void _setOriginUseManualAddress() {
    setState(() => _useCurrentLocation = false);
  }

  Widget _buildSearchBar() {
    return this._buildSearchBarSection();
  }

  Widget _buildOmnibox() {
    return this._buildOmniboxSection();
  }

  // ─── Search results ───────────────────────────────────────────────────────

  Widget _buildSearchResults() {
    return this._buildSearchResultsSection();
  }

  Widget _buildGenerateRouteOptionCard() {
    return this._buildGenerateRouteOptionCardSection();
  }

  Widget _buildContributedFilterRow() {
    return this._buildContributedFilterRowSection();
  }

  Widget _sortFilterChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return this._sortFilterChipSection(
      label: label,
      active: active,
      onTap: onTap,
    );
  }

  Widget _buildTopPicksCard(List<route_model.Route> topPicks) {
    return this._buildTopPicksCardSection(topPicks);
  }

  Widget _buildOrsResultCard() {
    return this._buildOrsResultCardSection();
  }

  Widget _buildAlternativesPanel() {
    return this._buildAlternativesPanelSection();
  }

  Widget _buildOrsEmptyState() {
    return this._buildOrsEmptyStateSection();
  }

  Widget _buildOriginSelector() {
    return this._buildOriginSelectorSection();
  }

  Widget _originToggleBtn({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return this._originToggleBtnSection(
      label: label,
      icon: icon,
      active: active,
      onTap: onTap,
    );
  }

  // ─── Suggestions panel ────────────────────────────────────────────────────

  Widget _buildSearchSuggestions() {
    return this._buildSearchSuggestionsSection();
  }

  Widget _buildRecentSearches() {
    return this._buildRecentSearchesSection();
  }

  Widget _buildTopSearches() {
    return this._buildTopSearchesSection();
  }
}
