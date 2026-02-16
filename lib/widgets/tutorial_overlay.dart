import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/tutorial_service.dart';

class TutorialOverlay extends StatefulWidget {
  final List<TutorialStep> steps;
  final Map<String, GlobalKey> targetKeys;
  final VoidCallback onComplete;
  final bool showSkipButton;
  final VoidCallback? onExampleRouteRequested;

  const TutorialOverlay({
    super.key,
    required this.steps,
    required this.targetKeys,
    required this.onComplete,
    this.showSkipButton = true,
    this.onExampleRouteRequested,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Offset _targetPosition = Offset.zero;
  Size _targetSize = Size.zero;
  bool _showAnimation = false;

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
    final targetKey = widget.targetKeys[widget.steps[_currentStep].targetKey];
    if (targetKey?.currentContext != null) {
      final RenderBox renderBox = targetKey!.currentContext!.findRenderObject() as RenderBox;
      final position = renderBox.localToGlobal(Offset.zero);
      
      setState(() {
        _targetPosition = position;
        _targetSize = renderBox.size;
      });
    }
  }

  void _nextStep() {
    if (_currentStep < widget.steps.length - 1) {
      _animationController.reverse().then((_) {
        setState(() {
          _currentStep++;
          _showAnimation = false;
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

  void _toggleAnimation() {
    setState(() {
      _showAnimation = !_showAnimation;
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
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getAnimationIcon(animationAsset),
              size: 48,
              color: Colors.blue,
            ).animate()
              .fadeIn(duration: 500.ms)
              .then(delay: 200.ms)
              .slide(duration: 500.ms),
            const SizedBox(height: 8),
            Text(
              'Animation: $animationAsset',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
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
    final tooltipTop = isTargetInTopHalf 
        ? _targetPosition.dy + _targetSize.height + 20
        : _targetPosition.dy - 150;
    
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          );
        },
        child: Stack(
          children: [
            // Semi-transparent background
            Positioned.fill(
              child: GestureDetector(
                onTap: _nextStep,
                child: Container(
                  color: Colors.black.withOpacity(0.7),
                ),
              ),
            ),
            
            // Highlight around target
            Positioned(
              left: _targetPosition.dx - 10,
              top: _targetPosition.dy - 10,
              width: _targetSize.width + 20,
              height: _targetSize.height + 20,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue, width: 3),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.transparent,
                ),
              ).animate()
                .fadeIn(duration: 300.ms)
                .then(delay: 200.ms)
                .shimmer(duration: 1000.ms, curve: Curves.easeInOut),
            ),
            
            // Tooltip
            Positioned(
              left: 20,
              right: 20,
              top: tooltipTop,
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentStep.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        currentStep.description,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      
                      // Animation preview (if available)
                      if (currentStep.animationAsset != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: _toggleAnimation,
                              icon: Icon(_showAnimation ? Icons.visibility_off : Icons.visibility),
                              label: Text(_showAnimation ? 'Hide Animation' : 'Show Animation'),
                            ),
                          ],
                        ),
                        if (_showAnimation) ...[
                          const SizedBox(height: 8),
                          _buildAnimationPreview(currentStep.animationAsset),
                        ],
                      ],
                      
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (widget.showSkipButton)
                            TextButton(
                              onPressed: _skipTutorial,
                              child: const Text('Skip Tutorial'),
                            )
                          else
                            const SizedBox.shrink(),
                          if (widget.onExampleRouteRequested != null && _currentStep == 0)
                            TextButton(
                              onPressed: _loadExampleRoute,
                              child: const Text('Load Example Route'),
                            ),
                          ElevatedButton(
                            onPressed: _nextStep,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(
                              _currentStep < widget.steps.length - 1
                                  ? 'Next'
                                  : 'Got it!',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Step indicator
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          widget.steps.length,
                          (index) => Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: index == _currentStep
                                  ? Colors.blue
                                  : Colors.grey.shade300,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate()
                .fadeIn(duration: 300.ms)
                .moveY(begin: 20, end: 0, duration: 300.ms, curve: Curves.easeOutQuad),
            ),
          ],
        ),
      ),
    );
  }
}
