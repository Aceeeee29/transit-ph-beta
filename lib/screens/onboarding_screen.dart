import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/gamification_service.dart';
import '../theme/app_colors.dart';

/// The cards a new account sees once: what TransitPH does, then which kind
/// of rider they are.
class OnboardingScreen extends StatefulWidget {
  final User user;

  /// Shown again from Settings (debug builds): nothing is saved, and the
  /// end just closes it.
  final bool replay;

  const OnboardingScreen({super.key, required this.user, this.replay = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isSaving = false;

  static Color get _bg => AppColors.bg;
  static Color get _surface => AppColors.surface;
  static const _accent = Color(0xFF0B8FD6);
  static Color get _accentSoft => AppColors.accentSoft;
  static Color get _textPrimary => AppColors.textPrimary;
  static Color get _textSecondary => AppColors.textSecondary;
  static Color get _border => AppColors.border;

  static const _slides = [
    _Slide(
      title: 'Find your way by jeep, bus and train',
      description:
          'Type where you\'re going and press Generate routes. TransitPH '
          'puts the walks and rides together, with times and fares.',
      icon: Icons.alt_route_rounded,
    ),
    _Slide(
      title: 'Follow your route live',
      description:
          'Press Start and TransitPH shows the ride you\'re on, how far to '
          'your stop, and what comes next. It tells you before you need to '
          'get off.',
      icon: Icons.navigation_rounded,
    ),
    _Slide(
      title: 'Routes by riders, for riders',
      description:
          'Know a jeepney or tricycle route that isn\'t here? Draw it on the '
          'map in Contribute. Once approved, it helps everyone.',
      icon: Icons.edit_road_rounded,
    ),
    _Slide(
      title: 'Works with weak signal',
      description:
          'The CAMANAVA map is built in, and you can download routes for '
          'offline use. Student, PWD or senior? Turn on the discount to see '
          'your real fare.',
      icon: Icons.wifi_off_rounded,
    ),
  ];

  /// The slides, then the category picker.
  int get _pageCount => _slides.length + 1;
  bool get _onCategoryPage => _currentPage == _slides.length;

  Future<void> _finish() async {
    if (widget.replay) {
      Navigator.of(context).pop();
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .update({'hasSeenTutorial': true});
    } catch (_) {
      // Shown again next time; better than holding the rider here.
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/main', arguments: false);
  }

  void _onNext() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _onCategorySelected(String category) async {
    if (widget.replay) {
      await _finish();
      return;
    }
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .update({
            'userCategory': category,
            'userTags': [category],
          });
      final appUser = await GamificationService.loadUser();
      appUser.userCategory = category;
      appUser.userTags = [category];
      appUser.name =
          widget.user.displayName ??
          widget.user.email?.split('@').first ??
          'User';
      appUser.email = widget.user.email ?? '';
      await GamificationService.saveUser(appUser);
    } catch (_) {
      // Continue anyway.
    }
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Align(
                alignment: Alignment.centerRight,
                child:
                    _onCategoryPage
                        ? null
                        : Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: TextButton(
                            onPressed: _finish,
                            child: Text(
                              'Skip',
                              style: TextStyle(
                                color: _textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemCount: _pageCount,
                itemBuilder:
                    (context, index) =>
                        index < _slides.length
                            ? _buildSlide(_slides[index])
                            : _buildCategoryPage(),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pageCount; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _currentPage == i ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: _currentPage == i ? _accent : _border,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                // The category page ends with a choice, not a button.
                child:
                    _onCategoryPage
                        ? null
                        : FilledButton(
                          onPressed: _onNext,
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Next',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(_Slide slide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Center(child: _SlideArt(icon: slide.icon))),
          const SizedBox(height: 24),
          Text(
            slide.title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
              letterSpacing: -0.4,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            slide.description,
            style: TextStyle(fontSize: 15, color: _textSecondary, height: 1.5),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCategoryPage() {
    const categories = [
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

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            'Which fits you best?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'TransitPH uses this to suggest routes for you.',
            style: TextStyle(fontSize: 15, color: _textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(
                child: CircularProgressIndicator(
                  color: _accent,
                  strokeWidth: 2.5,
                ),
              ),
            )
          else
            for (final category in categories)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: _surface,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _onCategorySelected(category.label),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _border),
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
                              category.icon,
                              color: _accent,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category.label,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: _textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  category.description,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: _textSecondary,
                          ),
                        ],
                      ),
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

class _Slide {
  final String title;
  final String description;
  final IconData icon;

  const _Slide({
    required this.title,
    required this.description,
    required this.icon,
  });
}

/// A slide's picture: its icon in soft rings.
class _SlideArt extends StatelessWidget {
  final IconData icon;

  const _SlideArt({required this.icon});

  static const _accent = Color(0xFF0B8FD6);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.accentSoft.withValues(alpha: 0.5),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accentSoft,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 64, color: _accent),
      ),
    );
  }
}

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
