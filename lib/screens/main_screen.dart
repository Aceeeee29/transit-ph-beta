import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'contribute_screen.dart';
import 'profile_screen.dart';
import 'feed_screen.dart';
import 'moderator_screen.dart';
import '../models/post.dart';
import '../models/route.dart' as route_model;
import '../services/moderation_service.dart';

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

  late List<Widget> _screens;
  late List<NavigationDestination> _destinations;

  @override
  void initState() {
    super.initState();
    ModerationService.postsNotifier.value = posts;
    _screens = [
      HomeScreen(routes: routes),
      FeedScreen(
        posts: posts,
        onPostCreated: (post) => setState(() { posts.add(post); ModerationService.postsNotifier.value = List.from(posts); }),
      ),
      ContributeScreen(
        onRouteSubmitted: (route) {
          setState(() {
            routes.add(route);
          });
        },
      ),
      const ProfileScreen(),
    ];
    _destinations = [
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
    ];
    if (widget.isAdmin) {
      _screens = List<Widget>.from(_screens);
      _destinations = List<NavigationDestination>.from(_destinations);
      _screens.add(const ModeratorScreen());
      _destinations.add(
        const NavigationDestination(
          icon: Icon(Icons.shield_outlined),
          selectedIcon: Icon(Icons.shield),
          label: 'Moderator',
        ),
      );
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: _destinations,
      ),
    );
  }
}
