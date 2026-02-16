import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart' as app_user;
import '../services/gamification_service.dart';

class OnboardingScreen extends StatefulWidget {
  final User user;
  const OnboardingScreen({super.key, required this.user});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _categorySelected = false;
  String? _selectedCategory;

  final List<Map<String, dynamic>> _slides = [
    {
      'title': 'Welcome to TransitPH',
      'description': 'Find the fastest and cheapest public transport routes in the Philippines.',
      'icon': Icons.map,
      'color': Colors.blue,
    },
    {
      'title': 'Search Your Route',
      'description': 'Enter your destination. TransitPH finds available public transport routes.',
      'icon': Icons.search,
      'color': Colors.green,
    },
    {
      'title': 'Multi-Leg Routes',
      'description': 'Some trips need multiple rides. TransitPH breaks trips into clear steps: Walk, Ride, Transfer.\n\nExample: Valenzuela → Monumento → SM North EDSA',
      'icon': Icons.directions,
      'color': Colors.orange,
    },
    {
      'title': 'Route Details',
      'description': 'Estimated travel time, Fare estimate, Landmarks & stops, Step-by-step directions.',
      'icon': Icons.info,
      'color': Colors.purple,
    },
    {
      'title': 'Safety & Tips',
      'description': 'Verified routes and safety tips. Always follow local traffic rules. Data is community & system-assisted.',
      'icon': Icons.security,
      'color': Colors.red,
    },
    {
      'title': 'Contribute a Route',
      'description': 'Know a route that\'s not on TransitPH? Help the community by contributing new routes. Your knowledge makes public transport better for everyone!',
      'icon': Icons.add_location,
      'color': Colors.indigo,
    },
    {
      'title': 'You\'re Ready!',
      'description': 'You\'re all set! Start exploring public transport routes in the Philippines.',
      'icon': Icons.check_circle,
      'color': Colors.teal,
    },
  ];

  void _onSkip() async {
    await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).update({
      'hasSeenTutorial': true,
    });
    Navigator.of(context).pushReplacementNamed('/main', arguments: false);
  }
  
  void _onNext() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _onStartExploring();
    }
  }

  void _onStartExploring() async {
    await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).update({
      'hasSeenTutorial': true,
    });
    Navigator.of(context).pushReplacementNamed('/main', arguments: false);
  }

  void _onCategorySelected(String category) async {
    // Save to Firestore
    await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).update({
      'userCategory': category,
    });
    
    // Also save to SharedPreferences via GamificationService
    final appUser = await GamificationService.loadUser();
    appUser.userCategory = category;
    appUser.name = widget.user.displayName ?? widget.user.email?.split('@').first ?? 'User';
    appUser.email = widget.user.email ?? '';
    await GamificationService.saveUser(appUser);
    
    setState(() {
      _selectedCategory = category;
      _categorySelected = true;
    });
  }

  Widget _buildCategorySelection() {
    return Container(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Welcome to TransitPH!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          const Text(
            'Please select your category to personalize your experience:',
            style: TextStyle(
              fontSize: 16,
              color: Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          Column(
            children: [
              ElevatedButton(
                onPressed: () => _onCategorySelected('Student'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Student', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _onCategorySelected('Employee'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Employee', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _onCategorySelected('Foreigner'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Foreigner', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _onCategorySelected('New to Area'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  foregroundColor: Colors.white,
                ),
                child: const Text('New to Area', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_categorySelected) {
      return Scaffold(
        body: _buildCategorySelection(),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemCount: _slides.length,
            itemBuilder: (context, index) {
              final slide = _slides[index];
              return Container(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      slide['icon'] as IconData,
                      size: 100,
                      color: slide['color'] as Color,
                    ),
                    const SizedBox(height: 40),
                    Text(
                      slide['title'] as String,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      slide['description'] as String,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            top: 50,
            right: 20,
            child: TextButton(
              onPressed: _onSkip,
              child: const Text(
                'Skip',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index ? Colors.blue : Colors.grey,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: _onNext,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _currentPage == _slides.length - 1 ? 'Start Exploring' : 'Next',
                style: const TextStyle(fontSize: 16,
                color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
