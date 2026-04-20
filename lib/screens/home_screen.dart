import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/route.dart' as route_model;
import 'downloaded_routes_screen.dart';
import 'route_map_screen.dart';
import 'search_screen.dart';
import '../services/gamification_service.dart';
import '../services/weather_service.dart';
import '../services/location_service.dart';
import '../services/recommendation_service.dart';
import '../services/route_metrics_service.dart';
import '../services/route_service.dart';
import '../services/route_trust_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/home/fare_matrix_dialog.dart';
part 'home_screen_sections.dart';

enum RouteSortMode { community, budget, fastest, balanced }

class HomeScreen extends StatefulWidget {
  final List<route_model.Route> routes;
  final Future<void> Function()? onRefresh;

  const HomeScreen({super.key, required this.routes, this.onRefresh});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  WeatherData? _weatherData;
  bool _isLoadingWeather = true;
  bool _isDetectingLocation = false;
  final Set<String> _selectedModes = {};
  Map<String, List<route_model.Route>> _recommendations = {};
  bool _isLoadingRecommendations = true;
  List<String> _userTags = [];
  int? _totalUsers;
  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;
  RouteSortMode _routeSortMode = RouteSortMode.community;

  static const Set<String> _personaTags = {
    'Student',
    'Employee',
    'Foreigner',
    'New to Area',
  };

  // ─── Color tokens ────────────────────────────────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);

  // ─── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _getWeather();
    _loadUserTags();
    _loadRecommendations();
    _loadTotalUsers();
  }

  Future<void> _loadUserTags() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data();
      if (data == null || !mounted) return;
      final tags = List<String>.from(data['userTags'] ?? const []);
      final category = (data['userCategory'] as String?)?.trim();
      if (category != null && category.isNotEmpty && !tags.contains(category)) {
        tags.add(category);
      }
      setState(() => _userTags = tags);
    } catch (_) {
      // Keep empty tags when user profile load fails.
    }
  }

  void _openDownloadedRoutes() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DownloadedRoutesScreen()),
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _loadTotalUsers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .count()
          .get();
      if (mounted) setState(() => _totalUsers = snap.count);
    } catch (_) {
      // silently ignore — widget simply won't render
    }
  }

  Future<void> _loadRecommendations() async {
    setState(() => _isLoadingRecommendations = true);
    try {
      final recs = await RecommendationService.getAllRecommendations(widget.routes);
      final sortedRecs = <String, List<route_model.Route>>{};
      recs.forEach((key, value) {
        final sorted = List<route_model.Route>.from(value)
          ..sort((a, b) => _routePriorityScore(b).compareTo(_routePriorityScore(a)));
        sortedRecs[key] = sorted;
      });
      setState(() {
        _recommendations = sortedRecs;
        _isLoadingRecommendations = false;
      });
    } catch (e) {
      setState(() => _isLoadingRecommendations = false);
    }
  }

  Future<void> _getWeather() async {
    setState(() => _isLoadingWeather = true);
    try {
      final weatherData = await WeatherService.getCurrentWeatherAndLocation();
      if (weatherData != null) {
        setState(() {
          _weatherData = weatherData;
          _startController.text = weatherData.address;
          _isLoadingWeather = false;
        });
      } else {
        setState(() => _isLoadingWeather = false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting weather: $e')),
      );
      setState(() => _isLoadingWeather = false);
    }
  }

  Future<void> _detectCurrentLocation() async {
    setState(() => _isDetectingLocation = true);
    try {
      final address = await LocationService.getCurrentLocationAddress();
      if (address != null) {
        setState(() => _startController.text = address);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location detected successfully'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not detect location. Please check permissions.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error detecting location: $e')),
        );
      }
    } finally {
      setState(() => _isDetectingLocation = false);
    }
  }

  void _onNotificationsDismissed() {
    setState(() {
      _showNotificationOverlay = false;
      _pendingNotifications.clear();
    });
  }

  // ─── Route actions ────────────────────────────────────────────────────────────

  void _findRoute() async {
    final destination = _destinationController.text.trim().toLowerCase();
    if (destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a destination')),
      );
      return;
    }

    final user = await GamificationService.loadUser();
    final unlockedItems = await GamificationService.incrementRoutesSearched(user);
    if (unlockedItems.isNotEmpty) {
      setState(() {
        _pendingNotifications = unlockedItems;
        _showNotificationOverlay = true;
      });
    }

    final matched = widget.routes.where((route) {
      final matchesDest =
          route.endLocation.trim().toLowerCase().contains(destination) ||
          route.shortDescription.trim().toLowerCase().contains(destination);
      if (_selectedModes.isNotEmpty) {
        return matchesDest &&
            route.steps.any((s) => _selectedModes.contains(s.mode));
      }
      return matchesDest;
    }).toList();

    _showSearchResultsSheet(matched);
  }

  int _tagMatchScore(route_model.Route route) {
    if (_userTags.isEmpty || route.audienceTags.isEmpty) return 0;
    final personaUserTags = _userTags
        .where((tag) => _personaTags.contains(tag))
        .toList();
    if (personaUserTags.isEmpty) return 0;

    final userTagsLower = personaUserTags.map((e) => e.toLowerCase()).toSet();
    final matches = route.audienceTags
        .where((t) => userTagsLower.contains(t.toLowerCase()))
        .length;
    return matches * 120;
  }

  int _routePriorityScore(route_model.Route route) {
    return _tagMatchScore(route) + route.views + route.upvotes - route.downvotes;
  }

  double _routeEstimatedFare(route_model.Route route) {
    final fromPrice = _extractFirstNumber(route.price);
    if (fromPrice != null) return fromPrice;

    final transportSteps = route.steps.where((s) => s.mode != 'Walk').toList();
    if (transportSteps.isEmpty) return 0;

    final totalDistanceKm = route.distanceMeters != null && route.distanceMeters! > 0
        ? route.distanceMeters! / 1000
        : (RouteMetricsService.parseDistanceToKm(route.distance) ?? 5.0);
    final perStepDistance = totalDistanceKm / transportSteps.length;

    var total = 0.0;
    for (final step in transportSteps) {
      total += step.actualFare ??
          RouteMetricsService.calculateFareForMode(step.mode, perStepDistance);
    }
    return total;
  }

  int _routeEstimatedMinutes(route_model.Route route) {
    final parsedEta = int.tryParse((route.eta ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
    if (parsedEta != null && parsedEta > 0) return parsedEta;

    final distanceKm = route.distanceMeters != null && route.distanceMeters! > 0
        ? route.distanceMeters! / 1000
        : (RouteMetricsService.parseDistanceToKm(route.distance) ?? 5.0);

    final hasTrain = route.steps.any((s) => s.mode == 'Train');
    final speed = hasTrain ? 28.0 : 20.0;
    final minutes = ((distanceKm / speed) * 60).ceil();
    final transferPenalty = (route.steps.where((s) => s.mode != 'Walk').length - 1) * 4;
    return (minutes + transferPenalty).clamp(8, 180);
  }

  List<route_model.Route> _sortRoutesByMode(
    List<route_model.Route> source,
    RouteSortMode mode,
  ) {
    final sorted = List<route_model.Route>.from(source);
    switch (mode) {
      case RouteSortMode.community:
        sorted.sort((a, b) => _routePriorityScore(b).compareTo(_routePriorityScore(a)));
        break;
      case RouteSortMode.budget:
        sorted.sort((a, b) {
          final fareCmp = _routeEstimatedFare(a).compareTo(_routeEstimatedFare(b));
          if (fareCmp != 0) return fareCmp;
          return _routeEstimatedMinutes(a).compareTo(_routeEstimatedMinutes(b));
        });
        break;
      case RouteSortMode.fastest:
        sorted.sort((a, b) => _routeEstimatedMinutes(a).compareTo(_routeEstimatedMinutes(b)));
        break;
      case RouteSortMode.balanced:
        sorted.sort((a, b) {
          final aScore = _routeEstimatedFare(a) * 0.6 + _routeEstimatedMinutes(a) * 0.4;
          final bScore = _routeEstimatedFare(b) * 0.6 + _routeEstimatedMinutes(b) * 0.4;
          return aScore.compareTo(bScore);
        });
        break;
    }
    return sorted;
  }

  double? _extractFirstNumber(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  List<String> get _activePersonaTags {
    return _userTags.where((tag) => _personaTags.contains(tag)).toList();
  }

  List<route_model.Route> get _tagMatchedRoutes {
    final activeTags = _activePersonaTags;
    if (activeTags.isEmpty) return [];

    final activeTagsLower = activeTags.map((t) => t.toLowerCase()).toSet();

    final matched = widget.routes.where((route) {
      if (route.audienceTags.isEmpty) return false;
      return route.audienceTags
          .map((t) => t.toLowerCase())
          .any((t) => activeTagsLower.contains(t));
    }).toList()
      ..sort((a, b) => _routePriorityScore(b).compareTo(_routePriorityScore(a)));

    return matched.take(8).toList();
  }

  // ─── Dialogs / modals ────────────────────────────────────────────────────────

  void _showFareMatrixDialog() {
    showDialog(
      context: context,
      builder: (_) => const HomeFareMatrixDialog(),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter by Transport Mode'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: ['Jeepney', 'Bus', 'Train', 'Tricycle', 'FX/Van', 'Ferry', 'Walk']
                  .map((mode) => CheckboxListTile(
                        title: Row(
                          children: [
                            _modeIcon(mode),
                            const SizedBox(width: 8),
                            Text(mode),
                          ],
                        ),
                        value: _selectedModes.contains(mode),
                        onChanged: (checked) {
                          setDialogState(() {
                            setState(() {
                              if (checked == true) {
                                _selectedModes.add(mode);
                              } else {
                                _selectedModes.remove(mode);
                              }
                            });
                          });
                        },
                      ))
                  .toList(),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _selectedModes.clear());
              Navigator.pop(context);
              _findRoute();
            },
            child: const Text('Clear All'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showSearchResultsSheet(List<route_model.Route> matchedRoutes) {
    RouteSortMode sheetSortMode = _routeSortMode;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final sortedRoutes = _sortRoutesByMode(matchedRoutes, sheetSortMode);
          final cheapestFare = sortedRoutes.isEmpty
              ? null
              : sortedRoutes.map(_routeEstimatedFare).reduce((a, b) => a < b ? a : b);

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, scrollController) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Search Results (${sortedRoutes.length})',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _showFilterDialog,
                          icon: const Icon(Icons.filter_list),
                          label: Text(
                            'Filter${_selectedModes.isNotEmpty ? ' (${_selectedModes.length})' : ''}',
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _sortChip(
                          label: 'Community',
                          active: sheetSortMode == RouteSortMode.community,
                          onTap: () => setSheetState(() {
                            sheetSortMode = RouteSortMode.community;
                            _routeSortMode = sheetSortMode;
                          }),
                        ),
                        _sortChip(
                          label: 'Budget',
                          active: sheetSortMode == RouteSortMode.budget,
                          onTap: () => setSheetState(() {
                            sheetSortMode = RouteSortMode.budget;
                            _routeSortMode = sheetSortMode;
                          }),
                        ),
                        _sortChip(
                          label: 'Fastest',
                          active: sheetSortMode == RouteSortMode.fastest,
                          onTap: () => setSheetState(() {
                            sheetSortMode = RouteSortMode.fastest;
                            _routeSortMode = sheetSortMode;
                          }),
                        ),
                        _sortChip(
                          label: 'Balanced',
                          active: sheetSortMode == RouteSortMode.balanced,
                          onTap: () => setSheetState(() {
                            sheetSortMode = RouteSortMode.balanced;
                            _routeSortMode = sheetSortMode;
                          }),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedModes.isNotEmpty)
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: _selectedModes
                            .map((mode) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Chip(
                                    label: Text(mode),
                                    deleteIcon: const Icon(Icons.close, size: 18),
                                    onDeleted: () {
                                      setState(() => _selectedModes.remove(mode));
                                      _findRoute();
                                    },
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  const Divider(),
                  Expanded(
                    child: sortedRoutes.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No routes found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Try adjusting your filters',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: sortedRoutes.length,
                            itemBuilder: (context, index) => _buildRouteCard(
                              sortedRoutes[index],
                              cheapestFare: cheapestFare,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Widget builders ─────────────────────────────────────────────────────────

  Widget _buildRouteCard(route_model.Route route, {double? cheapestFare}) {
    return this._buildRouteCardSection(route, cheapestFare: cheapestFare);
  }

  Widget _buildRecommendationSection(String title, List<route_model.Route> routes) {
    if (routes.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: _textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 212,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: routes.length > 5 ? 5 : routes.length,
            itemBuilder: (context, index) =>
                _buildRecommendationCard(routes[index]),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRecommendationCard(route_model.Route route) {
    return this._buildRecommendationCardSection(route);
  }

  Widget _statItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _audienceTagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _accent.withOpacity(0.2)),
      ),
      child: Text(
        tag,
        style: const TextStyle(
          fontSize: 11,
          color: _accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _modeIcon(String mode) {
    switch (mode) {
      case 'Walk':
        return const Icon(Icons.directions_walk, color: Colors.green, size: 20);
      case 'Jeepney':
        return const Icon(Icons.directions_bus, color: Colors.blue, size: 20);
      case 'Bus':
        return const Icon(Icons.directions_bus_filled, color: Colors.red, size: 20);
      case 'Train':
        return const Icon(Icons.train, color: Colors.purple, size: 20);
      case 'Tricycle':
        return const Icon(Icons.pedal_bike, color: Colors.orange, size: 20);
      case 'FX/Van':
        return const Icon(Icons.directions_car, color: Colors.amber, size: 20);
      case 'Ferry':
        return const Icon(Icons.directions_boat, color: Colors.lightBlue, size: 20);
      default:
        return const Icon(Icons.directions_walk, color: Colors.green, size: 20);
    }
  }

  Widget _routeIntegrityChip(route_model.Route route) {
    return StreamBuilder<Map<String, int>>(
      stream: RouteService.watchRouteFeedbackSummary(route.id),
      builder: (context, snapshot) {
        final summary = snapshot.data ?? const {
          'fareAccurateYes': 0,
          'fareAccurateNo': 0,
          'scheduleAccurateYes': 0,
          'scheduleAccurateNo': 0,
          'stillOperatingYes': 0,
          'stillOperatingNo': 0,
        };

        final trust = RouteTrustService.computeConfidence(
          route: route,
          feedbackSummary: summary,
        );
        final trustLabel = RouteTrustService.confidenceLabel(trust.total);
        final trustColor = trust.total >= 85
            ? const Color(0xFF2D9F63)
            : trust.total >= 65
                ? _accent
                : const Color(0xFFB8732F);

        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: trustColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: trustColor.withOpacity(0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user_outlined, size: 13, color: trustColor),
                const SizedBox(width: 5),
                Text(
                  'Integrity ${trust.total}/100 - $trustLabel',
                  style: TextStyle(
                    fontSize: 10,
                    color: trustColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sortChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: active ? _accentSoft : _surfaceAlt,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? _accent.withOpacity(0.35) : _border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? _accent : _textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeChip(String mode) {
    const modeColors = {
      'Walk': Color(0xFF3EC97A),
      'Jeepney': Color(0xFF2E7CF6),
      'Bus': Color(0xFFE05C6A),
      'Train': Color(0xFF9B7FE8),
      'Tricycle': Color(0xFFE89A3C),
      'FX/Van': Color(0xFFD4A017),
      'Ferry': Color(0xFF3EC9D6),
    };
    final color = modeColors[mode] ?? _textSecondary;
    IconData iconData;
    switch (mode) {
      case 'Walk':
        iconData = Icons.directions_walk;
        break;
      case 'Jeepney':
        iconData = Icons.directions_bus;
        break;
      case 'Bus':
        iconData = Icons.directions_bus_filled;
        break;
      case 'Train':
        iconData = Icons.train;
        break;
      case 'Tricycle':
        iconData = Icons.pedal_bike;
        break;
      case 'FX/Van':
        iconData = Icons.directions_car;
        break;
      case 'Ferry':
        iconData = Icons.directions_boat;
        break;
      default:
        iconData = Icons.directions_walk;
    }
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
          Icon(iconData, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            mode,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: _bg),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 28),
                _buildHeader(),
                const SizedBox(height: 20),
                _buildWeatherSection(),
                const SizedBox(height: 16),
                _buildSearchCard(),
                const SizedBox(height: 16),
                _buildFareButton(),
                if (_totalUsers != null) ...[
                  const SizedBox(height: 16),
                  _buildUserCountCard(),
                ],
                const SizedBox(height: 28),
                _buildRecommendations(),
                _buildCtaFooter(),
                const SizedBox(height: 28),
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

  Widget _buildHeader() {
    return this._buildHeaderSection();
  }

  Widget _buildWeatherSection() {
    return this._buildWeatherSectionSection();
  }

  Widget _buildSearchCard() {
    return this._buildSearchCardSection();
  }

  Widget _buildUserCountCard() {
    return this._buildUserCountCardSection();
  }

  Widget _buildFareButton() {
    return GestureDetector(
      onTap: _showFareMatrixDialog,
      child: Container(
        height: 48,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _border, width: 1.5),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payments_outlined, color: _accent, size: 17),
            SizedBox(width: 8),
            Text(
              'View Fare Matrix',
              style: TextStyle(
                color: _accent,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendations() {
    return this._buildRecommendationsSection();
  }

  Widget _buildCtaFooter() {
    return this._buildCtaFooterSection();
  }
}
