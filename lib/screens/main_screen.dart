import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'home_screen.dart';
import 'contribute_screen.dart';
import 'profile_screen.dart';
import 'feed_screen.dart';
import 'moderator_screen.dart';
import 'offline_mode_prompt_screen.dart';
import 'downloaded_routes_screen.dart';
import 'route_map_screen.dart';
import 'search_screen.dart';
import 'ors_route_map_screen.dart';
import '../theme/app_colors.dart';
import '../models/post.dart';
import '../models/route.dart' as route_model;
import '../services/moderation_service.dart';
import '../services/gamification_service.dart';
import '../services/post_service.dart';
import '../services/route_service.dart';
import '../services/active_navigation_service.dart';
import '../services/map_tab_controller.dart';
import '../widgets/announcement_dialog.dart';
import '../widgets/translate_chathead.dart';
import '../widgets/translated_text.dart';

class MainScreen extends StatefulWidget {
  final bool isAdmin;
  final String? quickRouteToken;

  const MainScreen({super.key, this.isAdmin = false, this.quickRouteToken});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  MapTabMode _mapTabMode = MapTabMode.nearby;

  // "Press back again to exit": armed by the first back on Home.
  static const _exitWindow = Duration(seconds: 2);
  bool _exitArmed = false;
  Timer? _exitTimer;
  bool _isLoading = false;
  bool _didCheckAnnouncements = false;
  bool _isOfflinePromptVisible = false;
  bool _offlineModeAccepted = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<User?>? _userSubscription;
  String? _pendingQuickRouteToken;
  Route<dynamic>? _ownRoute;

  List<Post> posts = [];
  List<route_model.Route> routes = [];

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static const _surface = Color(0xFFFFFFFF);
  static const _accent = Color(0xFF0B8FD6);
  static const _accentSoft = Color(0x1A0B8FD6);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  String get currentUserName {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return 'User';
  }

  String get currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid ?? '';
  }

  @override
  void initState() {
    super.initState();
    _pendingQuickRouteToken = widget.quickRouteToken;
    if (_pendingQuickRouteToken != null &&
        _pendingQuickRouteToken!.isNotEmpty) {
      _selectedIndex = 2;
    }
    ModerationService.postsNotifier.value = posts;
    GamificationService.updateStreakOnAppOpen();
    _loadData();
    _startConnectivityMonitoring();
    // Rebuild whenever the signed-in user's profile (name, photo) changes,
    // e.g. after editing it in Settings, so it propagates live to every
    // tab (Feed, Contribute, etc.) instead of only on the next unrelated
    // rebuild.
    _userSubscription = FirebaseAuth.instance.userChanges().listen((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAnnouncements());
    MapTabController.instance.addListener(_onMapTabChanged);
    TranslateChatHead.loadEnabled();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Opening a route from a pushed page (search, notifications) pops back
    // to this page so the Map tab shows it.
    _ownRoute = ModalRoute.of(context);
    MapTabController.instance.hostRoute = _ownRoute;
  }

  @override
  void dispose() {
    final mapTab = MapTabController.instance;
    mapTab.removeListener(_onMapTabChanged);
    if (mapTab.hostRoute == _ownRoute) mapTab.hostRoute = null;
    _connectivitySubscription?.cancel();
    _userSubscription?.cancel();
    _exitTimer?.cancel();
    super.dispose();
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  Future<void> _startConnectivityMonitoring() async {
    final connectivity = Connectivity();

    final initial = await connectivity.checkConnectivity();
    if (mounted && !_hasNetwork(initial)) {
      await _showOfflinePrompt();
    }

    _connectivitySubscription = connectivity.onConnectivityChanged.listen((
      results,
    ) async {
      if (!mounted) return;
      if (_hasNetwork(results)) {
        _offlineModeAccepted = false;
        return;
      }
      if (!_offlineModeAccepted) {
        await _showOfflinePrompt();
      }
    });
  }

  Future<void> _showOfflinePrompt() async {
    if (!mounted || _isOfflinePromptVisible) return;

    // A route being followed keeps working offline (it's already loaded and
    // GPS needs no data), so don't cover it with the full-screen prompt.
    if (ActiveNavigationService.instance.isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText(
            "You're offline. Following continues with the route already loaded.",
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    _isOfflinePromptVisible = true;
    try {
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const OfflineModePromptScreen()),
      );
      if (result == OfflineModePromptScreen.continueOfflineResult) {
        _offlineModeAccepted = true;
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DownloadedRoutesScreen()),
        );
      }
    } finally {
      _isOfflinePromptVisible = false;
    }
  }

  Future<void> _checkAnnouncements() async {
    if (_didCheckAnnouncements || !mounted) return;
    _didCheckAnnouncements = true;
    await AnnouncementDialog.checkAndShow(context);
  }

  /// Fetches the latest routes and posts from Firestore.
  /// Called on init and whenever the user pulls to refresh.
  Future<void> _loadData() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final fetchedPosts = await PostService.getAllPosts();
      final fetchedRoutes = await RouteService.getAllRoutes();
      PostService.deleteExpiredPosts(); // fire-and-forget background cleanup
      setState(() {
        posts = fetchedPosts;
        routes = fetchedRoutes;
        ModerationService.postsNotifier.value = List.from(posts);
      });
    } catch (e) {
      debugPrint('[MainScreen] Error loading data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// The system back gesture: an open route closes, Contribute returns to
  /// the normal map (the drawing is kept), other tabs go Home, and on Home
  /// the first back only arms "press back again to exit".
  void _onBack() {
    final mapTab = MapTabController.instance;
    if (_selectedIndex == 2 && mapTab.current != null) {
      mapTab.close();
    } else if (_selectedIndex == 2 && _mapTabMode == MapTabMode.contribute) {
      setState(() => _mapTabMode = MapTabMode.nearby);
    } else if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
    } else {
      setState(() => _exitArmed = true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: TranslatedText('Press back again to exit'),
            duration: _exitWindow,
          ),
        );
      _exitTimer?.cancel();
      _exitTimer = Timer(_exitWindow, () {
        if (mounted) setState(() => _exitArmed = false);
      });
    }
  }

  /// Route search, optionally already planning a trip to [destination].
  void _openSearch([String? destination, LatLng? point]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => SearchScreen(
              routes: routes,
              onRefresh: _loadData,
              initialDestination: destination,
              initialDestinationPoint: point,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(
        routes: routes,
        onRefresh: _loadData,
        onOpenSearch: _openSearch,
      ),
      FeedScreen(
        key: ValueKey(posts.length),
        posts: posts,
        onRefresh: _loadData,
        onPostCreated: (post) async {
          try {
            await PostService.savePost(post);
          } catch (e) {
            debugPrint('[MainScreen] Failed to save post: $e');
          }
          setState(() {
            posts.add(post);
            ModerationService.postsNotifier.value = List.from(posts);
          });
        },
        onPostDeleted: (post) {
          setState(() {
            posts.removeWhere((p) => p.id == post.id);
            ModerationService.postsNotifier.value = List.from(posts);
          });
        },
        currentUserName: currentUserName,
        currentUserId: currentUserId,
      ),
      _buildMapTab(
        ContributeScreen(
          onRouteSubmitted: (route) async {
            await RouteService.saveRoute(route);
            await _loadData();
          },
          mapMode: _mapTabMode,
          searchableRoutes: routes,
          onOpenDirections: (name, point) => _openSearch(name, point),
          onMapModeChanged: (mode) {
            if (_mapTabMode == mode) return;
            setState(() => _mapTabMode = mode);
          },
          quickRouteToken: _pendingQuickRouteToken,
          onQuickRouteTokenConsumed: () {
            if (!mounted || _pendingQuickRouteToken == null) return;
            setState(() => _pendingQuickRouteToken = null);
          },
        ),
      ),
      ProfileScreen(key: ValueKey('profile_tab_${_selectedIndex == 3}')),
      if (widget.isAdmin) ModeratorScreen(onRoutesModerated: _loadData),
    ];

    // ─── Nav items ────────────────────────────────────────────────────────────
    final navItems = <_NavItem>[
      const _NavItem(
        icon: Icons.search_outlined,
        activeIcon: Icons.search_rounded,
        label: 'Home',
      ),
      const _NavItem(
        icon: Icons.chat_bubble_outline,
        activeIcon: Icons.chat_bubble_rounded,
        label: 'Feed',
      ),
      const _NavItem(
        icon: Icons.map_outlined,
        activeIcon: Icons.map_rounded,
        label: 'Map',
        isAccent: true,
      ),
      const _NavItem(
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: 'Profile',
      ),
      if (widget.isAdmin)
        const _NavItem(
          icon: Icons.shield_outlined,
          activeIcon: Icons.shield_rounded,
          label: 'Moderator',
        ),
    ];

    final mapTab = MapTabController.instance;
    return PopScope(
      // Back steps out one level at a time; only a second back on Home
      // leaves the app.
      canPop: _selectedIndex == 0 && _exitArmed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: ListenableBuilder(
          listenable: Listenable.merge([
            ActiveNavigationService.instance,
            mapTab,
          ]),
          builder: (context, _) {
            // The route view on the Map tab already shows the session, so the
            // "tap to return" banner would point where you already are.
            final viewingRoute = _selectedIndex == 2 && mapTab.current != null;
            final activeTarget =
                viewingRoute
                    ? null
                    : ActiveNavigationService.instance.activeTarget;
            // Expand: the tabs are positioned, so without it the stack would
            // size itself to the bubble, and to nothing once it is turned off.
            final content = Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: IndexedStack(index: _selectedIndex, children: screens),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: TranslateChatHead.enabled,
                  builder:
                      (context, enabled, _) =>
                          enabled
                              ? const TranslateChatHead()
                              : const SizedBox.shrink(),
                ),
              ],
            );

            if (activeTarget == null) return content;

            // The banner already consumes the top status-bar inset via its own
            // SafeArea, so strip it before the tab content below — otherwise
            // each tab's own AppBar reserves that space a second time, leaving
            // a dead gap under the banner.
            return Column(
              children: [
                _buildActiveNavigationBanner(activeTarget),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: content,
                  ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: _buildNavBar(navItems),
      ),
    );
  }

  /// The Map tab: browsing/contributing, with a route view on top while one
  /// is open. Contribute stays alive underneath so a draft isn't lost.
  Widget _buildMapTab(Widget browse) {
    return ListenableBuilder(
      listenable: MapTabController.instance,
      builder: (context, _) {
        final current = MapTabController.instance.current;
        return IndexedStack(
          index: current == null ? 0 : 1,
          children: [
            browse,
            if (current == null)
              const SizedBox.shrink()
            else if (current.route != null)
              RouteMapScreen(
                key: ValueKey('map_route_${current.serial}'),
                route: current.route!,
                enableRouteIntegrity: current.enableRouteIntegrity,
                showDownloadButton: current.showDownloadButton,
                onClose: MapTabController.instance.close,
              )
            else
              OrsRouteMapScreen(
                key: ValueKey('map_route_${current.serial}'),
                result: current.generated!,
                originName: current.originName,
                destinationName: current.destinationName,
                showDownloadButton: current.showDownloadButton,
                onClose: MapTabController.instance.close,
              ),
          ],
        );
      },
    );
  }

  /// A route was opened somewhere in the app: show the Map tab.
  void _onMapTabChanged() {
    if (!mounted) return;
    if (MapTabController.instance.current != null && _selectedIndex != 2) {
      setState(() => _selectedIndex = 2);
    } else {
      // canPop depends on whether a route is open.
      setState(() {});
    }
  }

  Widget _buildActiveNavigationBanner(FollowTarget target) {
    final navigation = ActiveNavigationService.instance;
    final hasArrived = navigation.hasArrived;
    final isPaused = navigation.isPausedForIdle;
    final color =
        hasArrived
            ? const Color(0xFF2D9F63)
            : isPaused
            ? const Color(0xFFB8732F)
            : _accent;
    final route = target.route;
    final generated = target.generatedRoute;
    return SafeArea(
      bottom: false,
      child: GestureDetector(
        onTap:
            () =>
                route != null
                    ? MapTabController.openRoute(
                      context,
                      route,
                      enableRouteIntegrity: navigation.enableRouteIntegrity,
                      showDownloadButton: navigation.showDownloadButton,
                    )
                    : MapTabController.openGenerated(
                      context,
                      generated!,
                      originName: target.startLabel,
                      destinationName: target.endLabel,
                      showDownloadButton: navigation.showDownloadButton,
                    ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                hasArrived
                    ? Icons.check_circle_rounded
                    : isPaused
                    ? Icons.pause_circle_rounded
                    : Icons.navigation_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TranslatedText(
                  hasArrived
                      ? "You've arrived, tap to finish"
                      : isPaused
                      ? 'Following paused to save battery, tap to resume'
                      : 'Route still ongoing, tap to return',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavBar(List<_NavItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: const Border(top: BorderSide(color: _border, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children:
                items.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  final isSelected = _selectedIndex == idx;

                  // Centre "Contribute" gets a gradient circle treatment
                  if (item.isAccent) {
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedIndex = idx),
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors:
                                      isSelected
                                          ? AppColors.buttonGradient
                                          : const [
                                            Color(0xFFD4E4F7),
                                            Color(0xFFEAF2FF),
                                          ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow:
                                    isSelected
                                        ? [
                                          BoxShadow(
                                            color: _accent.withOpacity(0.35),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ]
                                        : null,
                              ),
                              child: Icon(
                                isSelected ? item.activeIcon : item.icon,
                                color:
                                    isSelected ? Colors.white : _textSecondary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(height: 4),
                            TranslatedText(
                              item.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? _accent : _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Regular tabs
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedIndex = idx),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 44,
                            height: 32,
                            decoration: BoxDecoration(
                              color:
                                  isSelected ? _accentSoft : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isSelected ? item.activeIcon : item.icon,
                              color: isSelected ? _accent : _textSecondary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 3),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight:
                                  isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                              color: isSelected ? _accent : _textSecondary,
                            ),
                            child: TranslatedText(item.label),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isAccent;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.isAccent = false,
  });
}
