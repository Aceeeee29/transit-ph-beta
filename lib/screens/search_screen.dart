import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import '../models/route.dart' as route_model;
import '../models/ors_route_result.dart';
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
import 'route_map_screen.dart';
import 'ors_route_map_screen.dart';

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

  String _alternativeTripIdSignature(DijkstraRouteAlternative alt) {
    return alt.result.plan.legs.map((leg) => leg.tripId).join('>');
  }

  String _alternativeRouteSignature(DijkstraRouteAlternative alt) {
    return alt.result.plan.legs
        .map((leg) => '${leg.routeId}:${leg.tripId}:${leg.boardStopId}:${leg.alightStopId}')
        .join('>');
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
        final originText = _originController.text.trim();
        if (originText.isEmpty) {
          setState(() {
            _isLoadingOrs = false;
            _orsError = true;
            _orsErrorMessage = 'Please enter a starting point.';
          });
          return;
        }
        final originLatLng = await _geocodePhilippines(originText);
        if (originLatLng == null) {
          setState(() {
            _isLoadingOrs = false;
            _orsError = true;
            _orsErrorMessage =
                'Could not find "$originText". Try a more specific address.';
          });
          return;
        }
        origin = originLatLng;
        originName = originText;
      }

      final destLatLng = await _geocodePhilippines(query);
      if (destLatLng == null) {
        setState(() {
          _isLoadingOrs = false;
          _orsError = true;
          _orsErrorMessage =
              'Could not find "$query". Try a more specific name.';
        });
        return;
      }

      List<DijkstraRouteAlternative> alternatives = [];
      var fallbackAlternatives = <int, OrsRouteResult>{};
      var labelsByIndex = <int, String>{};
      try {
        final pools = await Future.wait([
          RoutingService.getRouteAlternatives(
            origin: origin,
            destination: destLatLng,
            optimization: 'balanced',
            maxAlternatives: 8,
          ),
          RoutingService.getRouteAlternatives(
            origin: origin,
            destination: destLatLng,
            optimization: 'fastest',
            maxAlternatives: 8,
          ),
          RoutingService.getRouteAlternatives(
            origin: origin,
            destination: destLatLng,
            optimization: 'budget',
            maxAlternatives: 8,
          ),
        ]);

        final merged = <DijkstraRouteAlternative>[];
        final mergedSeen = <String>{};
        for (final pool in pools) {
          for (final alt in pool) {
            final sig = _alternativeRouteSignature(alt);
            if (!mergedSeen.add(sig)) continue;
            merged.add(alt);
          }
        }

        final selected = <DijkstraRouteAlternative>[];
        final selectedSeen = <String>{};

        DijkstraRouteAlternative? pickFrom(
          List<DijkstraRouteAlternative> pool,
        ) {
          for (final alt in pool) {
            final sig = _alternativeRouteSignature(alt);
            if (selectedSeen.contains(sig)) continue;
            return alt;
          }
          for (final alt in merged) {
            final sig = _alternativeRouteSignature(alt);
            if (selectedSeen.contains(sig)) continue;
            return alt;
          }
          return null;
        }

        void addLabeled(String label, DijkstraRouteAlternative? alt) {
          if (alt == null) return;
          final sig = _alternativeRouteSignature(alt);
          if (!selectedSeen.add(sig)) return;
          selected.add(alt);
          labelsByIndex[selected.length - 1] = label;
        }

        final balancedPick = pickFrom(pools[0]);
        addLabeled('Balanced', balancedPick);

        final byTime = List<DijkstraRouteAlternative>.from(merged)
          ..sort((a, b) => a.estimatedTimeMinutes.compareTo(b.estimatedTimeMinutes));
        addLabeled('Fastest', pickFrom(byTime));

        final byFare = List<DijkstraRouteAlternative>.from(merged)
          ..sort((a, b) => a.estimatedFarePhp.compareTo(b.estimatedFarePhp));
        addLabeled('Budget', pickFrom(byFare));

        final hasTrainAlready = selected.any(_alternativeHasTrain);
        if (!hasTrainAlready) {
          final trainPick = pickFrom(
            merged.where(_alternativeHasTrain).toList(),
          );
          addLabeled('Train', trainPick);
        }

        alternatives = selected;

        final tripIdSignatures = <String>{};
        for (var i = 0; i < alternatives.length; i++) {
          final signature = _alternativeTripIdSignature(alternatives[i]);
          if (signature.isEmpty || tripIdSignatures.add(signature)) continue;

          fallbackAlternatives[i] = await RoutingService.buildWalkFallbackRoute(
            origin: origin,
            destination: destLatLng,
            note: 'Showing walking fallback route for visual variety.',
          );
        }
      } catch (e) {
        debugPrint('[SearchScreen] Alternative lookup failed: $e');
      }

      final result =
          fallbackAlternatives[0] ??
          (alternatives.isNotEmpty
              ? await RoutingService.buildRouteFromDijkstraAlternative(
                origin: origin,
                destination: destLatLng,
                alternative: alternatives.first.result,
                preferredMode: 'Auto',
              )
              : await RoutingService.getRoute(
                originName: originName,
                origin: origin,
                destinationName: query,
                destination: destLatLng,
                mode: 'Auto',
              ));

      setState(() {
        _isLoadingOrs = false;
        _orsResult = result;
        _routeAlternatives = alternatives;
        _fallbackAlternativeRoutes = fallbackAlternatives;
        _alternativeLabels = labelsByIndex;
        _selectedAlternativeIndex = 0;
        _lastOriginForAlternatives = origin;
        _lastDestinationForAlternatives = destLatLng;
      });
    } on RoutingException catch (e) {
      setState(() {
        _isLoadingOrs = false;
        _orsError = true;
        _orsErrorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isLoadingOrs = false;
        _orsError = true;
        _orsErrorMessage = 'Unexpected error: $e';
      });
    }
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
    return SearchRouteCard(
      route: route,
      onTap: () => _onRouteTap(route),
      isVerified: route.isApproved,
    );
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

  Widget _buildSearchBar() {
    return Container(
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
                hintText: 'Search destinations...',
                hintStyle: const TextStyle(color: _textSecondary, fontSize: 14),
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
          if (_showOmnibox && _suggestions.isNotEmpty) _buildOmnibox(),
        ],
      ),
    );
  }

  Widget _buildOmnibox() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _suggestions.length,
        separatorBuilder: (_, index) => Divider(color: _border, height: 1),
        itemBuilder: (context, index) {
          final suggestion = _suggestions[index];
          final isRecent = _recentSearches.contains(suggestion);
          return InkWell(
            onTap: () => _onSuggestionTap(suggestion),
            borderRadius: BorderRadius.vertical(
              top: index == 0 ? const Radius.circular(14) : Radius.zero,
              bottom:
                  index == _suggestions.length - 1
                      ? const Radius.circular(14)
                      : Radius.zero,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isRecent ? _surfaceAlt : _accentSoft,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      isRecent ? Icons.history_rounded : Icons.search_rounded,
                      size: 14,
                      color: isRecent ? _textSecondary : _accent,
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
                  const Icon(Icons.north_west, size: 13, color: _textSecondary),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Search results ───────────────────────────────────────────────────────

  Widget _buildSearchResults() {
    if (_filteredRoutes.isNotEmpty) {
      final sortedRoutes = _sortContributedRoutes(
        _filteredRoutes,
        _contributedSortMode,
      );
      final topPicks = _topThreeModePicks(_filteredRoutes);

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildContributedFilterRow(),
          const SizedBox(height: 10),
          if (topPicks.isNotEmpty) ...[
            _buildTopPicksCard(topPicks),
            const SizedBox(height: 12),
          ],
          ...sortedRoutes.map(_routeCardWithBadge),
        ],
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_isLoadingOrs) ...[
            const SizedBox(height: 60),
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'Finding your route…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
          ] else if (_orsResult != null) ...[
            _buildOrsResultCard(),
          ] else ...[
            _buildOrsEmptyState(),
          ],
        ],
      ),
    );
  }

  Widget _buildContributedFilterRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _sortFilterChip(
          label: 'Balanced',
          active: _contributedSortMode == ContributedRouteSortMode.balanced,
          onTap:
              () => setState(
                () => _contributedSortMode = ContributedRouteSortMode.balanced,
              ),
        ),
        _sortFilterChip(
          label: 'Budget',
          active: _contributedSortMode == ContributedRouteSortMode.budget,
          onTap:
              () => setState(
                () => _contributedSortMode = ContributedRouteSortMode.budget,
              ),
        ),
        _sortFilterChip(
          label: 'Fastest',
          active: _contributedSortMode == ContributedRouteSortMode.fastest,
          onTap:
              () => setState(
                () => _contributedSortMode = ContributedRouteSortMode.fastest,
              ),
        ),
      ],
    );
  }

  Widget _sortFilterChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _accentSoft : _surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? _accent.withValues(alpha: 0.35) : _border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? _accent : _textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTopPicksCard(List<route_model.Route> topPicks) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top route picks',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.blue.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Best picks for Balanced, Budget, and Fastest based on available contributed routes.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          ...topPicks.asMap().entries.map((entry) {
            final route = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _onRouteTap(route),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${route.startLocation} to ${route.endLocation}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'PHP ${_routeEstimatedFare(route).toStringAsFixed(0)} • ${_routeEstimatedMinutes(route)} min',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOrsResultCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Fallback auto-generated route from transit stop data. '
                  'Use community-verified routes first whenever available. '
                  'Distances and fares here are estimates.',
                  style: TextStyle(fontSize: 13, color: Colors.blue.shade800),
                ),
              ),
            ],
          ),
        ),
        if (_routeAlternatives.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildAlternativesPanel(),
        ],
        const SizedBox(height: 16),
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
                Row(
                  children: [
                    Icon(Icons.route, color: Colors.blue.shade700, size: 20),
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
                    'Route steps',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        borderRadius: BorderRadius.circular(4),
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

        const SizedBox(height: 16),
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
      ],
    );
  }

  Widget _buildAlternativesPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top ${_routeAlternatives.length} alternatives',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.blue.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Best picks for Balanced, Fastest, and Budget from GTFS alternatives.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          ..._routeAlternatives.asMap().entries.map((entry) {
            final index = entry.key;
            final alt = entry.value;
            final selected = index == _selectedAlternativeIndex;
            final fallbackRoute = _fallbackAlternativeRoutes[index];
            final displayFare =
                fallbackRoute == null
                    ? alt.estimatedFarePhp
                    : fallbackRoute.steps.fold<double>(
                      0.0,
                      (sum, s) => sum + s.estimatedFare,
                    );
            final displayTimeMinutes =
                fallbackRoute == null
                    ? alt.estimatedTimeMinutes
                    : fallbackRoute.durationSeconds / 60.0;

            final tags = <String>[];
            final optionLabel = _alternativeLabels[index];
            if (optionLabel != null && optionLabel.isNotEmpty) {
              tags.add(optionLabel);
            }
            if (fallbackRoute != null) {
              tags.add('Walk Fallback');
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _selectAlternative(index),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? Colors.blue.shade50 : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          selected
                              ? Colors.blue.shade400
                              : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Option ${index + 1}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Fare: PHP ${displayFare.toStringAsFixed(0)} • Time: ${displayTimeMinutes.toStringAsFixed(0)} min',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            if (tags.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                tags.join(' • '),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle,
                          color: Colors.blue.shade700,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOrsEmptyState() {
    return Column(
      children: [
        const SizedBox(height: 32),
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
          'No community routes found',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'You can use fallback generated guidance from transit stop data.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: _textSecondary),
        ),
        const SizedBox(height: 24),
        _buildOriginSelector(),
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
            onPressed: _isLoadingOrs ? null : _onGenerateRoutePressed,
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
    );
  }

  Widget _buildOriginSelector() {
    return Container(
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
          Row(
            children: [
              _originToggleBtn(
                label: 'My location',
                icon: Icons.my_location,
                active: _useCurrentLocation,
                onTap:
                    () => setState(() {
                      _useCurrentLocation = true;
                      _originController.clear();
                    }),
              ),
              const SizedBox(width: 8),
              _originToggleBtn(
                label: 'Enter address',
                icon: Icons.edit_location_alt_outlined,
                active: !_useCurrentLocation,
                onTap: () => setState(() => _useCurrentLocation = false),
              ),
            ],
          ),
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
                        hintText: 'e.g. Quezon City Hall, EDSA Cubao...',
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
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed:
                        _isDetectingLocation ? null : _detectAndFillOrigin,
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
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _originToggleBtn({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Colors.blue.shade700 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? Colors.blue.shade700 : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Suggestions panel ────────────────────────────────────────────────────

  Widget _buildSearchSuggestions() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_recentSearches.isNotEmpty) ...[
            _buildRecentSearches(),
            const SizedBox(height: 24),
          ],
          _buildTopSearches(),
        ],
      ),
    );
  }

  Widget _buildRecentSearches() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RECENT SEARCHES',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
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
      ],
    );
  }

  Widget _buildTopSearches() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TOP SEARCHES',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Popular routes based on community activity',
          style: TextStyle(fontSize: 13, color: _textSecondary),
        ),
        const SizedBox(height: 16),
        ..._topSearches.map((route) => _routeCardWithBadge(route)),
      ],
    );
  }
}
