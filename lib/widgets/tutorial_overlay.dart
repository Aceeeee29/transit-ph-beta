import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/tutorial_service.dart';

class TutorialOverlay extends StatefulWidget {
  final List<TutorialStep> steps;
  final VoidCallback onComplete;
  final bool showSkipButton;
  final VoidCallback? onExampleRouteRequested;

  const TutorialOverlay({
    super.key,
    required this.steps,
    required this.onComplete,
    this.showSkipButton = true,
    this.onExampleRouteRequested,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Offset _targetPosition = Offset.zero;
  Size _targetSize = Size.zero;
  final bool _showAnimation = true;

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();

    // Calculate initial target position after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTargetPosition();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _updateTargetPosition() {
    final currentStep = widget.steps[_currentStep];
    setState(() {
      _targetPosition = currentStep.customPosition ?? Offset.zero;
      _targetSize = currentStep.customSize ?? Size(100, 100);
    });
  }

  void _nextStep() {
    if (_currentStep < widget.steps.length - 1) {
      _animationController.reverse().then((_) {
        setState(() {
          _currentStep++;
        });
        _updateTargetPosition();
        _animationController.forward();
      });
    } else {
      _animationController.reverse().then((_) {
        widget.onComplete();
      });
    }
  }

  void _skipTutorial() {
    _animationController.reverse().then((_) {
      widget.onComplete();
    });
  }

  void _loadExampleRoute() {
    if (widget.onExampleRouteRequested != null) {
      widget.onExampleRouteRequested!();
      _skipTutorial();
    }
  }

  Widget _buildAnimationPreview(String? animationAsset) {
    if (animationAsset == null) {
      return const SizedBox.shrink();
    }

    // This would be replaced with actual animations in a real implementation
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Center(
        child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _accentSoft,
                shape: BoxShape.circle,
                border: Border.all(color: _accent.withOpacity(0.25), width: 2),
              ),
              child: Icon(
                _getAnimationIcon(animationAsset),
                size: 26,
                color: _accent,
              ),
            )
            .animate()
            .fadeIn(duration: 500.ms)
            .then(delay: 200.ms)
            .slide(duration: 500.ms),
      ),
    );
  }

  IconData _getAnimationIcon(String animationAsset) {
    switch (animationAsset) {
      case 'map_overview':
        return Icons.map;
      case 'tap_start_point':
        return Icons.touch_app;
      case 'select_mode':
        return Icons.directions_bus;
      case 'add_route_points':
        return Icons.add_location;
      case 'add_instructions':
        return Icons.edit_note;
      case 'finish_route':
        return Icons.check_circle;
      case 'fill_details':
        return Icons.description;
      case 'add_media':
        return Icons.photo_camera;
      case 'preview_route':
        return Icons.preview;
      case 'submit_route':
        return Icons.send;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentStep = widget.steps[_currentStep];
    final screenSize = MediaQuery.of(context).size;

    // Determine tooltip position based on target position
    final isTargetInTopHalf = _targetPosition.dy < screenSize.height / 2;
    final tooltipTop =
        isTargetInTopHalf
            ? _targetPosition.dy + _targetSize.height + 20
            : _targetPosition.dy - 150;

    final isLast = _currentStep == widget.steps.length - 1;
    final isFirst = _currentStep == 0;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return Opacity(opacity: _fadeAnimation.value, child: child);
        },
        child: Stack(
          children: [
            // Semi-transparent background
            Positioned.fill(
              child: GestureDetector(
                onTap: _nextStep,
                child: Container(color: Colors.black.withOpacity(0.7)),
              ),
            ),

            // Tooltip card
            Positioned(
              left: 20,
              right: 20,
              top: 100, // Fixed position in center-ish
              child: Container(
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _border),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withOpacity(0.12),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Header ─────────────────────────────────────────
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
                          decoration: BoxDecoration(
                            color: _surfaceAlt,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                            border: Border(
                              bottom: BorderSide(color: _border),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: _accentSoft,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: const Icon(
                                  Icons.school_outlined,
                                  color: _accent,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  currentStep.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _textPrimary,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              // Step counter pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _accentSoft,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${_currentStep + 1}/${widget.steps.length}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── Body ───────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(
                                currentStep.description,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _textSecondary,
                                  height: 1.6,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              // Animation preview (if available)
                              if (currentStep.animationAsset != null) ...[
                                const SizedBox(height: 12),
                                _buildAnimationPreview(
                                    currentStep.animationAsset),
                              ],

                              const SizedBox(height: 16),

                              // Step indicator dots
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  widget.steps.length,
                                  (index) => AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 250),
                                    width: index == _currentStep ? 20 : 6,
                                    height: 6,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(3),
                                      color: index == _currentStep
                                          ? _accent
                                          : _border,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // ── Buttons ───────────────────────────────────
                              if (isFirst)
                                Row(
                                  children: [
                                    if (widget.onExampleRouteRequested != null) ...[
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: _loadExampleRoute,
                                          child: Container(
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: _surface,
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                              border: Border.all(
                                                  color: _border),
                                            ),
                                            alignment: Alignment.center,
                                            child: const Text(
                                              'Load Example',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: _textSecondary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Expanded(
                                      flex: widget.onExampleRouteRequested !=
                                              null
                                          ? 1
                                          : 0,
                                      child: _primaryButton(
                                        label: 'Next',
                                        icon: Icons.arrow_forward_rounded,
                                        onTap: _nextStep,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Row(
                                  children: [
                                    if (widget.showSkipButton) ...[
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: _skipTutorial,
                                          child: Container(
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: _surface,
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                              border: Border.all(
                                                  color: _border),
                                            ),
                                            alignment: Alignment.center,
                                            child: const Text(
                                              'Skip',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: _textSecondary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Expanded(
                                      flex: 2,
                                      child: _primaryButton(
                                        label: isLast ? 'Got it!' : 'Next',
                                        icon: isLast
                                            ? Icons.check_rounded
                                            : Icons.arrow_forward_rounded,
                                        onTap: _nextStep,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 300.ms)
                  .moveY(
                    begin: 20,
                    end: 0,
                    duration: 300.ms,
                    curve: Curves.easeOutQuad,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
            Icon(icon, color: Colors.white, size: 15),
          ],
        ),
      ),
    );
  }
}