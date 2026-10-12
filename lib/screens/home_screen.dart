import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/route.dart' as route_model;
import 'downloaded_routes_screen.dart';
import '../services/map_tab_controller.dart';
import '../services/weather_service.dart';
import '../services/recommendation_service.dart';
import '../services/route_service.dart';
import '../services/route_trust_service.dart';
import '../theme/app_colors.dart';
import '../widgets/home/fare_matrix_dialog.dart';
import '../widgets/map_tab/region_weather_row.dart';
import '../widgets/translated_text.dart';

part 'home_screen_widgets.dart';

/// The Home tab: a "Where to?" bar, shortcuts, and recommended routes.
class HomeScreen extends StatefulWidget {
  final List<route_model.Route> routes;
  final Future<void> Function()? onRefresh;

  /// Route search ("Where to?").
  final VoidCallback onOpenSearch;

  const HomeScreen({
    super.key,
    required this.routes,
    this.onRefresh,
    required this.onOpenSearch,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  WeatherData? _weatherData;
  Map<String, List<route_model.Route>> _recommendations = {};
  bool _isLoadingRecommendations = true;
  List<String> _userTags = [];

  static const Set<String> _personaTags = {
    'Student',
    'Employee',
    'Foreigner',
    'New to Area',
  };

  // ─── Color tokens ────────────────────────────────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _accent = AppColors.accent;
  static const _accentSoft = AppColors.accentSoft;
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);

  // ─── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadWeather();
    _loadUserTags();
    _loadRecommendations();
  }

  Future<void> _loadUserTags() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
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

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Home is built before the routes finish loading; rank them once they
    // arrive (and whenever they're reloaded).
    if (!identical(widget.routes, oldWidget.routes)) _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() => _isLoadingRecommendations = true);
    try {
      final recs = await RecommendationService.getAllRecommendations(
        widget.routes,
      );
      final sortedRecs = <String, List<route_model.Route>>{};
      recs.forEach((key, value) {
        final sorted = List<route_model.Route>.from(value)..sort(
          (a, b) => _routePriorityScore(b).compareTo(_routePriorityScore(a)),
        );
        sortedRecs[key] = sorted;
      });
      if (!mounted) return;
      setState(() {
        _recommendations = sortedRecs;
        _isLoadingRecommendations = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingRecommendations = false);
    }
  }

  /// Shared with the map's weather chip, so it's fetched once.
  Future<void> _loadWeather() async {
    final weather = await WeatherChip.load();
    if (mounted) setState(() => _weatherData = weather);
  }

  // New routes re-rank through didUpdateWidget.
  Future<void> _refresh() async {
    final refresh = widget.onRefresh;
    if (refresh != null) {
      await refresh();
    } else {
      await _loadRecommendations();
    }
  }

  void _openDownloadedRoutes() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DownloadedRoutesScreen()));
  }

  void _showFareMatrixDialog() {
    showDialog(context: context, builder: (_) => const HomeFareMatrixDialog());
  }

  // ─── Ranking ─────────────────────────────────────────────────────────────────

  int _tagMatchScore(route_model.Route route) {
    if (_userTags.isEmpty || route.audienceTags.isEmpty) return 0;
    final personaUserTags =
        _userTags.where((tag) => _personaTags.contains(tag)).toList();
    if (personaUserTags.isEmpty) return 0;

    final userTagsLower = personaUserTags.map((e) => e.toLowerCase()).toSet();
    final matches =
        route.audienceTags
            .where((t) => userTagsLower.contains(t.toLowerCase()))
            .length;
    return matches * 120;
  }

  int _routePriorityScore(route_model.Route route) {
    return _tagMatchScore(route) +
        route.views +
        route.upvotes -
        route.downvotes;
  }

  List<String> get _activePersonaTags {
    return _userTags.where((tag) => _personaTags.contains(tag)).toList();
  }

  List<route_model.Route> get _tagMatchedRoutes {
    final activeTags = _activePersonaTags;
    if (activeTags.isEmpty) return [];

    final activeTagsLower = activeTags.map((t) => t.toLowerCase()).toSet();

    final matched =
        widget.routes.where((route) {
            if (route.audienceTags.isEmpty) return false;
            return route.audienceTags
                .map((t) => t.toLowerCase())
                .any((t) => activeTagsLower.contains(t));
          }).toList()
          ..sort(
            (a, b) => _routePriorityScore(b).compareTo(_routePriorityScore(a)),
          );

    return matched.take(8).toList();
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _bg,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeaderSection(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_weatherData?.isStorm == true) ...[
                    _buildStormWarningSection(),
                    const SizedBox(height: 20),
                  ],
                  _buildRecommendationsSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
