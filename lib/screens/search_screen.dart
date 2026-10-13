import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import '../models/route.dart' as route_model;
import '../models/ors_route_result.dart';
import '../repositories/route_cache_repository.dart';
import '../services/map_tab_controller.dart';
import '../services/search_service.dart';
import '../services/fare_matrix.dart';
import '../services/fare_profile_service.dart';
import '../services/gamification_service.dart';
import '../services/routing_service.dart';
import '../services/location_service.dart';
import '../services/route_metrics_service.dart';
import '../services/route_service.dart';
import '../services/supabase_route_service.dart';

import '../widgets/location_permission_notice.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/search/route_option_card.dart';
import '../widgets/search/search_help_sheet.dart';
import 'downloaded_routes_screen.dart';
part 'search_screen_widgets.dart';
part 'search_screen_routing_logic.dart';
part 'search_screen_suggestions.dart';

enum ContributedRouteSortMode { balanced, budget, fastest }

class SearchScreen extends StatefulWidget {
  final List<route_model.Route> routes;
  final Future<void> Function()? onRefresh;

  /// Opens already searching for routes to this place (from "Directions").
  final String? initialDestination;
  final LatLng? initialDestinationPoint;

  /// Reopens a previous search as it was (back from a route opened here).
  final SearchSession? restore;

  const SearchScreen({
    super.key,
    required this.routes,
    this.onRefresh,
    this.initialDestination,
    this.initialDestinationPoint,
    this.restore,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

/// What Search showed when a route was opened from it, so back from that
/// route returns to the same options instead of starting over.
class SearchSession {
  final String origin;
  final String destination;
  final List<route_model.Route> routes;
  final List<DijkstraRouteAlternative> alternatives;
  final Map<int, OrsRouteResult> fallbackRoutes;
  final Map<int, String> labels;
  final int selectedIndex;
  final OrsRouteResult? result;
  final LatLng? originPoint;
  final LatLng? destinationPoint;
  final String? originName;
  final String? destinationName;

  const SearchSession({
    required this.origin,
    required this.destination,
    required this.routes,
    required this.alternatives,
    required this.fallbackRoutes,
    required this.labels,
    required this.selectedIndex,
    required this.result,
    required this.originPoint,
    required this.destinationPoint,
    required this.originName,
    required this.destinationName,
  });
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// Where routes start; empty means "Your location".
  final TextEditingController _originController = TextEditingController();
  final FocusNode _originFocusNode = FocusNode();
  List<String> _originSuggestions = [];

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
  static const _accent = Color(0xFF0B8FD6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);

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

  int? _pendingAlternativeIndex;

  /// The route list refresh started on open; route generation waits for it
  /// only when no routes came with the screen (see _fetchOrsRouteSection).
  Future<void>? _routesRefresh;

  /// The first option being drawn in the background after the list shows.
  Future<void>? _firstRouteDraw;

  /// Counts route searches: only the latest one may show its result, so
  /// changing the trip mid-search never shows the old trip's routes.
  int _routeRequestId = 0;

  /// Student fares (20% off), so generated options show the fare their
  /// route page will.
  bool _studentFare = false;

  /// The start field's text when routes were last searched.
  String _lastOrsOrigin = '';

  bool _isStaleRouteRequest(int id) => !mounted || id != _routeRequestId;

  /// The trip changed: drops the routes shown, and any search still running.
  /// Call inside setState.
  void _clearGeneratedRoutes() {
    _routeRequestId++;
    _firstRouteDraw = null;
    _isLoadingOrs = false;
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

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _routes = List<route_model.Route>.from(widget.routes);
    // Moving on to "Where to?" closes the start field's suggestions.
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus && _originSuggestions.isNotEmpty) {
        setState(() => _originSuggestions = []);
      }
    });
    _loadRecentSearches();
    _routesRefresh = _refreshRoutes();
    FareProfileService.isStudent().then((student) {
      if (student && mounted) setState(() => _studentFare = true);
    });
    final restore = widget.restore;
    if (restore != null) {
      _restore(restore);
      return;
    }
    final destination = widget.initialDestination?.trim() ?? '';
    if (destination.isNotEmpty) {
      _searchController.text = destination;
      // Picked on the map, so its spot is known: no need to look it up.
      final point = widget.initialDestinationPoint;
      if (point != null) _geocodeCache[destination.toLowerCase()] = point;
      // Handed a destination (e.g. the map's Directions): that already
      // asked for routes, so search right away.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _onSearchSubmitted(destination);
        _fetchOrsRoute();
      });
    }
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
    _originFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final searches = await SearchService.getRecentSearches();
    setState(() => _recentSearches = searches);
  }

  // ─── Philippines-biased geocoding ─────────────────────────────────────────

  /// Places found this session. Searching again (another option, a retry,
  /// swapping ends) skips Nominatim, which allows one request per second.
  static final Map<String, LatLng> _geocodeCache = {};

  Future<LatLng?> _geocodePhilippines(String query) async {
    final key = query.trim().toLowerCase();
    final cached = _geocodeCache[key];
    if (cached != null) return cached;
    final found = await _geocodePhilippinesUncached(query);
    if (found != null) _geocodeCache[key] = found;
    return found;
  }

  Future<LatLng?> _geocodePhilippinesUncached(String query) async {
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
      final locations = await locationFromAddress(
        query,
      ).timeout(const Duration(seconds: 6));
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

  /// [showSuggestions] false updates the results without reopening the
  /// suggestions list (e.g. after a background refresh).
  void _onSearch(String query, {bool showSuggestions = true}) {
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
    // Places only: whole routes ("A to B") and route tags read as a
    // destination when picked, which no search can find.
    final newSuggestions = _placeSuggestions(searchTerm);

    newSuggestions.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    setState(() {
      _isSearching = true;
      _suggestions = newSuggestions.take(5).toList();
      _showOmnibox = showSuggestions && _suggestions.isNotEmpty;
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
      if (query.trim() != _lastOrsQuery) _clearGeneratedRoutes();
    });
  }

  /// Recent searches and route ends that contain [searchTerm] (lowercase).
  List<String> _placeSuggestions(String searchTerm) {
    final places = <String>[];
    for (final s in _recentSearches) {
      if (s.toLowerCase().contains(searchTerm) && !places.contains(s)) {
        places.add(s);
      }
    }
    for (final route in _routes) {
      if (route.endLocation.toLowerCase().contains(searchTerm) &&
          !places.contains(route.endLocation)) {
        places.add(route.endLocation);
      }
      if (route.startLocation.toLowerCase().contains(searchTerm) &&
          !places.contains(route.startLocation)) {
        places.add(route.startLocation);
      }
    }
    return places;
  }

  /// Typing in the start field suggests places, like "Where to?" does.
  void _onOriginTyped(String query) {
    final searchTerm = query.trim().toLowerCase();
    setState(() {
      _originSuggestions =
          searchTerm.isEmpty
              ? []
              : (_placeSuggestions(searchTerm)..sort(
                (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
              )).take(5).toList();
      if (_originSuggestions.isNotEmpty) _showOmnibox = false;
      if (query.trim() != _lastOrsOrigin) _clearGeneratedRoutes();
    });
  }

  void _onOriginSuggestionTap(String suggestion) {
    _originController.text = suggestion;
    setState(() {
      _originSuggestions = [];
      if (suggestion.trim() != _lastOrsOrigin) _clearGeneratedRoutes();
    });
    _onOriginChanged();
  }

  void _closeOriginSuggestions() {
    if (_originSuggestions.isEmpty) return;
    setState(() => _originSuggestions = []);
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
    _onSearch(query);
    if (query.trim().isEmpty) return;
    // Submitted: the suggestions would only cover the results.
    setState(() => _showOmnibox = false);
    // Routes are searched with the "Generate routes" button, not on every
    // change. The bookkeeping runs in the background: it saves to
    // Firestore, and a save doesn't finish until the server answers.
    unawaited(_recordSearch(query.trim()));
    // Routes added since the screen opened, without holding up the search.
    unawaited(
      _refreshRoutes().then((_) {
        if (mounted && _searchController.text.trim() == query.trim()) {
          _onSearch(query, showSuggestions: false);
        }
      }),
    );
  }

  /// Recent searches and the "routes searched" achievements.
  Future<void> _recordSearch(String query) async {
    try {
      await SearchService.addRecentSearch(query);
      await _loadRecentSearches();
      final user = await GamificationService.loadUser();
      final unlockedItems = await GamificationService.incrementRoutesSearched(
        user,
      );
      if (unlockedItems.isNotEmpty && mounted) {
        setState(() {
          _pendingNotifications = unlockedItems;
          _showNotificationOverlay = true;
        });
      }
    } catch (e) {
      debugPrint('[Search] Saving the search failed: $e');
    }
  }

  void _onNotificationsDismissed() {
    setState(() {
      _showNotificationOverlay = false;
      _pendingNotifications.clear();
    });
  }

  Future<void> _onRecentSearchTap(String query) async {
    _searchController.text = query;
    _onSearch(query);
    // Moves it to the top; in the background, like _onSearchSubmitted.
    unawaited(
      SearchService.addRecentSearch(query).then((_) => _loadRecentSearches()),
    );
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
    MapTabController.openRoute(context, route, onBack: _returnHere());
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
        .map(
          (leg) =>
              '${leg.routeId}:${leg.tripId}:${leg.boardStopId}:${leg.alightStopId}',
        )
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

      final name =
          '${leg.routeShortName ?? ''} ${leg.routeLongName ?? ''}'
              .toLowerCase();
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
      if (SupabaseRouteService.isEdsaCarouselLeg(
        routeId: leg.routeId,
        routeType: leg.routeType,
        routeShortName: leg.routeShortName,
        routeLongName: leg.routeLongName,
        boardStopId: leg.boardStopId,
        alightStopId: leg.alightStopId,
      )) {
        return true;
      }
    }
    return false;
  }

  // ─── Route generation ─────────────────────────────────────────────────────

  Future<void> _fetchOrsRoute() async {
    await this._fetchOrsRouteSection();
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
          RouteCacheRepository.generatedRouteProfile,
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

  void _showSearchHelpSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SearchHelpSheet(),
    );
  }

  void _openDownloadedRoutes() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DownloadedRoutesScreen()));
  }

  // ─── Generated options ────────────────────────────────────────────────────

  /// Builds option [index] if it isn't the one already built, then opens it
  /// on the map.
  Future<void> _openAlternative(int index) async {
    if (_isLoadingOrs) return;
    // The first option may still be drawing in the background: wait for it
    // rather than drawing it a second time.
    final firstDraw = _firstRouteDraw;
    if (index == 0 && _orsResult == null && firstDraw != null) {
      setState(() => _pendingAlternativeIndex = 0);
      await firstDraw;
      if (!mounted) return;
      setState(() => _pendingAlternativeIndex = null);
    }
    if (_orsResult == null || index != _selectedAlternativeIndex) {
      setState(() => _pendingAlternativeIndex = index);
      await _selectAlternative(index);
      if (!mounted) return;
      setState(() => _pendingAlternativeIndex = null);
      if (index != _selectedAlternativeIndex) return;
    }
    _openResultOnMap();
  }

  void _restore(SearchSession session) {
    _routes = List<route_model.Route>.from(session.routes);
    _originController.text = session.origin;
    _searchController.text = session.destination;
    _lastOrsQuery = session.destination.trim();
    _lastOrsOrigin = session.origin.trim();
    _routeAlternatives = session.alternatives;
    _fallbackAlternativeRoutes = session.fallbackRoutes;
    _alternativeLabels = session.labels;
    _selectedAlternativeIndex = session.selectedIndex;
    _orsResult = session.result;
    _lastOriginForAlternatives = session.originPoint;
    _lastDestinationForAlternatives = session.destinationPoint;
    _lastGeneratedOriginName = session.originName;
    _lastGeneratedDestinationName = session.destinationName;
    // Fills the community list for the same trip (the options stay: the
    // query is unchanged) after the first frame, when setState is allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onSearch(session.destination, showSuggestions: false);
    });
  }

  /// Back from a route opened here: this search again, as it is now.
  void Function(BuildContext) _returnHere() {
    final session = SearchSession(
      origin: _originController.text,
      destination: _searchController.text,
      routes: _routes,
      alternatives: _routeAlternatives,
      fallbackRoutes: _fallbackAlternativeRoutes,
      labels: _alternativeLabels,
      selectedIndex: _selectedAlternativeIndex,
      result: _orsResult,
      originPoint: _lastOriginForAlternatives,
      destinationPoint: _lastDestinationForAlternatives,
      originName: _lastGeneratedOriginName,
      destinationName: _lastGeneratedDestinationName,
    );
    final onRefresh = widget.onRefresh;
    return (context) => Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => SearchScreen(
              routes: session.routes,
              onRefresh: onRefresh,
              restore: session,
            ),
      ),
    );
  }

  /// Draws the first of [alternatives] on the roads after the list is up.
  /// Dropped if a new search or another option replaced it meanwhile.
  Future<void> _drawFirstAlternative(
    List<DijkstraRouteAlternative> alternatives,
    LatLng origin,
    LatLng destination,
    String originName,
    String destinationName,
  ) async {
    try {
      final result = await RoutingService.buildRouteFromDijkstraAlternative(
        origin: origin,
        destination: destination,
        alternative: alternatives.first.result,
        preferredMode: 'Auto',
      );
      await RouteCacheRepository.put(
        originName,
        destinationName,
        'Auto',
        RouteCacheRepository.generatedRouteProfile,
        result,
      );
      if (!mounted ||
          !identical(_routeAlternatives, alternatives) ||
          _orsResult != null) {
        return;
      }
      setState(() {
        _orsResult = result;
        _selectedAlternativeIndex = 0;
      });
    } catch (e) {
      // Opening the option draws it again (and shows any error then).
      debugPrint('[SearchScreen] Drawing the first option failed: $e');
    }
  }

  void _openResultOnMap() {
    final result = _orsResult;
    if (result == null) return;
    MapTabController.openGenerated(
      context,
      result,
      originName:
          _lastGeneratedOriginName ??
          (_originController.text.trim().isEmpty
              ? 'Current Location'
              : _originController.text.trim()),
      destinationName:
          _lastGeneratedDestinationName ?? _searchController.text.trim(),
      onBack: _returnHere(),
    );
  }

  /// The start changed: search again so the options match it, or move on to
  /// the destination when there isn't one yet.
  void _onOriginChanged() {
    if (_searchController.text.trim().isEmpty) {
      _searchFocusNode.requestFocus();
    }
  }

  // These round, which throws on infinity/NaN and would blank the screen,
  // so an unusable number shows as a dash instead.

  static String _minutesLabel(double minutes) {
    if (!minutes.isFinite) return '— min';
    final total = math.max(1, minutes.round());
    if (total < 60) return '$total min';
    final rest = total % 60;
    return rest == 0 ? '${total ~/ 60} hr' : '${total ~/ 60} hr $rest min';
  }

  static String _transfersLabel(int rides) =>
      rides <= 1
          ? 'No transfers'
          : rides == 2
          ? '1 transfer'
          : '${rides - 1} transfers';

  static String _walkLabel(double km) {
    if (!km.isFinite) return 'Some walking';
    return km < 1
        ? '${(km * 1000).round()} m walk'
        : '${km.toStringAsFixed(1)} km walk';
  }

  /// A generated option's fare, worded as on its route page.
  String _tripFareLabel(double baseFare) =>
      PhFareCalculator.tripEstimateLabel(baseFare, student: _studentFare);

  static String _fareLabel(double fare) {
    if (!fare.isFinite) return '₱—';
    return fare <= 0 ? 'Free' : '₱${fare.round()}';
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: Column(
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
        ),
        if (_showNotificationOverlay)
          NotificationOverlay(
            notifications: _pendingNotifications,
            onAllDismissed: _onNotificationsDismissed,
          ),
      ],
    );
  }

  void _setContributedSortMode(ContributedRouteSortMode mode) {
    setState(() => _contributedSortMode = mode);
  }

  Widget _buildSearchBar() => _buildSearchBarSection();

  Widget _buildOmnibox() => _buildOmniboxSection();

  Widget _buildSearchResults() => _buildSearchResultsSection();

  Widget _buildSearchSuggestions() => _buildSearchSuggestionsSection();
}
