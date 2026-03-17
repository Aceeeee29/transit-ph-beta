import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';
import 'contribute_screen.dart';
import 'profile_screen.dart';
import 'feed_screen.dart';
import 'moderator_screen.dart';
import '../models/post.dart';
import '../models/route.dart' as route_model;
import '../services/moderation_service.dart';
import '../services/gamification_service.dart';
import '../services/post_service.dart';
import '../services/route_service.dart';

class MainScreen extends StatefulWidget {
  final bool isAdmin;
  const MainScreen({super.key, this.isAdmin = false});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _isLoading = false;

  List<Post> posts = [];
  List<route_model.Route> routes = [];

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static const _surface = Color(0xFFFFFFFF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  String get currentUserName {
    final user = FirebaseAuth.instance.currentUser;
    return user?.displayName ?? user?.email ?? 'User';
  }

  String get currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid ?? '';
  }

  @override
  void initState() {
    super.initState();
    ModerationService.postsNotifier.value = posts;
    GamificationService.updateStreakOnAppOpen();
    _loadData();
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

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(routes: routes, onRefresh: _loadData),
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
      ContributeScreen(
        onRouteSubmitted: (route) async {
          await RouteService.saveRoute(route);
          await _loadData();
        },
      ),
      const ProfileScreen(),
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
        icon: Icons.add_road_outlined,
        activeIcon: Icons.add_road_rounded,
        label: 'Contribute',
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

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: _buildNavBar(navItems),
    );
  }

  Widget _buildNavBar(List<_NavItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.06),
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
            children: items.asMap().entries.map((entry) {
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
                              colors: isSelected
                                  ? [
                                      const Color(0xFF4A7CE0),
                                      const Color(0xFF6A9EFF),
                                    ]
                                  : [
                                      const Color(0xFFD4E4F7),
                                      const Color(0xFFEAF2FF),
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: isSelected
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
                            color: isSelected ? Colors.white : _textSecondary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
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
                          color: isSelected ? _accentSoft : Colors.transparent,
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
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected ? _accent : _textSecondary,
                        ),
                        child: Text(item.label),
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