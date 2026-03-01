import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  bool _isLoading = false;

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  final List<Map<String, dynamic>> _slides = [
    {
      'title': 'Welcome to TransitPH',
      'description':
          'Find the fastest and cheapest public transport routes in the Philippines.',
      'icon': Icons.map,
      'color': Colors.blue,
    },
    {
      'title': 'Search Your Route',
      'description':
          'Enter your destination. TransitPH finds available public transport routes.',
      'icon': Icons.search,
      'color': Colors.green,
    },
    {
      'title': 'Multi-Leg Routes',
      'description':
          'Some trips need multiple rides. TransitPH breaks trips into clear steps: Walk, Ride, Transfer.\n\nExample: Valenzuela → Monumento → SM North EDSA',
      'icon': Icons.directions,
      'color': Colors.orange,
    },
    {
      'title': 'Route Details',
      'description':
          'Estimated travel time, Fare estimate, Landmarks & stops, Step-by-step directions.',
      'icon': Icons.info,
      'color': Colors.purple,
    },
    {
      'title': 'Safety & Tips',
      'description':
          'Verified routes and safety tips. Always follow local traffic rules. Data is community & system-assisted.',
      'icon': Icons.security,
      'color': Colors.red,
    },
    {
      'title': 'Contribute a Route',
      'description':
          'Know a route that\'s not on TransitPH? Help the community by contributing new routes. Your knowledge makes public transport better for everyone!',
      'icon': Icons.add_location,
      'color': Colors.indigo,
    },
    {
      'title': 'You\'re Ready!',
      'description':
          'You\'re all set! Start exploring public transport routes in the Philippines.',
      'icon': Icons.check_circle,
      'color': Colors.teal,
    },
  ];

  void _onSkip() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .update({'hasSeenTutorial': true});
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
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .update({'hasSeenTutorial': true});
    Navigator.of(context).pushReplacementNamed('/main', arguments: false);
  }

  void _onCategorySelected(String category) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .update({'userCategory': category});

      // Also save to SharedPreferences via GamificationService
      final appUser = await GamificationService.loadUser();
      appUser.userCategory = category;
      appUser.name =
          widget.user.displayName ??
          widget.user.email?.split('@').first ??
          'User';
      appUser.email = widget.user.email ?? '';
      await GamificationService.saveUser(appUser);
    } catch (e) {
      print('Error saving category: $e');
      // Continue anyway to proceed
    }

    setState(() {
      _selectedCategory = category;
      _categorySelected = true;
      _isLoading = false;
    });
  }

  // ─── Category selection screen ─────────────────────────────────────────────
  Widget _buildCategorySelection() {
    final categories = [
      _CategoryOption(
        label: 'Student',
        icon: Icons.school_outlined,
        description: 'Budget-friendly routes for school',
      ),
      _CategoryOption(
        label: 'Employee',
        icon: Icons.work_outline_rounded,
        description: 'Commuter routes for the workplace',
      ),
      _CategoryOption(
        label: 'Foreigner',
        icon: Icons.flight_outlined,
        description: 'Tourist-friendly guidance',
      ),
      _CategoryOption(
        label: 'New to Area',
        icon: Icons.explore_outlined,
        description: 'Discover routes in your new home',
      ),
    ];

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),

              // ── Logo badge ──────────────────────────────────────────
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.directions_bus_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),

              const SizedBox(height: 28),

              const Text(
                'Welcome to\nTransitPH!',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Select your category to personalize your experience:',
                style: TextStyle(
                  fontSize: 14,
                  color: _textSecondary,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 36),

              if (_isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: _accent,
                      strokeWidth: 2.5,
                    ),
                  ),
                )
              else
                Expanded(
                  child: Column(
                    children:
                        categories.map((cat) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GestureDetector(
                              onTap:
                                  _isLoading
                                      ? null
                                      : () => _onCategorySelected(cat.label),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _border),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _accent.withOpacity(0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: _accentSoft,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        cat.icon,
                                        color: _accent,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            cat.label,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: _textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            cat.description,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: _textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 14,
                                      color: _textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_categorySelected) {
      return _buildCategorySelection();
    }

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // ── Slide pages ──────────────────────────────────────────────
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
              final slideColor = slide['color'] as Color;
              final isLast = index == _slides.length - 1;

              return Padding(
                padding: const EdgeInsets.fromLTRB(28, 80, 28, 180),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon badge
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: slideColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: slideColor.withOpacity(0.25),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: slideColor.withOpacity(0.15),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        slide['icon'] as IconData,
                        size: 52,
                        color: slideColor,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Slide number pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _accentSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${index + 1} of ${_slides.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _accent,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      slide['title'] as String,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                        letterSpacing: -0.4,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    Text(
                      slide['description'] as String,
                      style: const TextStyle(
                        fontSize: 15,
                        color: _textSecondary,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    if (isLast) ...[
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3EC97A).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF3EC97A).withOpacity(0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 16,
                              color: Color(0xFF3EC97A),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Ready to go!',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF3EC97A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),

          // ── Skip button ──────────────────────────────────────────────
          Positioned(
            top: 50,
            right: 20,
            child: GestureDetector(
              onTap: _onSkip,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Skip',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _textSecondary,
                  ),
                ),
              ),
            ),
          ),

          // ── Page dots ────────────────────────────────────────────────
          Positioned(
            bottom: 110,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentPage == index ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _currentPage == index ? _accent : _border,
                  ),
                ),
              ),
            ),
          ),

          // ── Next / Start Exploring button ────────────────────────────
          Positioned(
            bottom: 36,
            left: 24,
            right: 24,
            child: GestureDetector(
              onTap: _onNext,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _currentPage == _slides.length - 1
                          ? 'Start Exploring'
                          : 'Next',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _currentPage == _slides.length - 1
                          ? Icons.rocket_launch_rounded
                          : Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ],
                ),
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

// ─── Private data class for category options ────────────────────────────────
class _CategoryOption {
  final String label;
  final IconData icon;
  final String description;

  const _CategoryOption({
    required this.label,
    required this.icon,
    required this.description,
  });
}
