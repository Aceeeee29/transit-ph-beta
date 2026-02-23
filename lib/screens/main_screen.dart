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
import '../services/route_service.dart';

class MainScreen extends StatefulWidget {
  final bool isAdmin;
  const MainScreen({super.key, this.isAdmin = false});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  List<Post> posts = [];
  List<route_model.Route> routes = [];

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
    _loadData();
    // Update streak on app open
    GamificationService.updateStreakOnAppOpen();
  }

  Future<void> _loadData() async {
    // Load posts from notifier
    posts = ModerationService.postsNotifier.value;
    ModerationService.postsNotifier.addListener(_onPostsChanged);

    // Load routes from Firestore
    routes = await RouteService.getAllRoutes();

    setState(() {});
  }

  void _onPostsChanged() {
    setState(() {
      posts = ModerationService.postsNotifier.value;
    });
  }

  @override
  void dispose() {
    ModerationService.postsNotifier.removeListener(_onPostsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(routes: routes),
      FeedScreen(
        key: ValueKey(posts.length), // Force rebuild when posts change
        posts: posts,
        onPostCreated: (post) {
          setState(() {
            posts.add(post);
            ModerationService.postsNotifier.value = List.from(posts);
          });
        },
        currentUserName: currentUserName,
        currentUserId: currentUserId,
      ),
      ContributeScreen(
        onRouteSubmitted: (route) async {
          try {
            await RouteService.saveRoute(route);
            setState(() => routes.add(route));
          } catch (e) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Failed to save route: $e')));
          }
        },
        contributorId: currentUserId,
      ),
      const ProfileScreen(),
      if (widget.isAdmin) const ModeratorScreen(),
    ];

    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search),
        label: 'Home',
      ),
      const NavigationDestination(
        icon: Icon(Icons.chat_bubble_outline),
        selectedIcon: Icon(Icons.chat_bubble),
        label: 'Feed',
      ),
      const NavigationDestination(
        icon: Icon(Icons.add_circle_outline),
        selectedIcon: Icon(Icons.add_circle),
        label: 'Contribute',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Profile',
      ),
      if (widget.isAdmin)
        const NavigationDestination(
          icon: Icon(Icons.shield_outlined),
          selectedIcon: Icon(Icons.shield),
          label: 'Moderator',
        ),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: destinations,
      ),
    );
  }
}
