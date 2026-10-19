import 'package:flutter/material.dart';

import '../services/tutorial_service.dart';
import '../theme/app_colors.dart';
import 'translated_text.dart';

/// A tutorial as swipeable cards over a dimmed screen: a screenshot (or an
/// icon until there is one), a title and a line or two each, with dots,
/// Skip and Next / Got it!.
class TutorialOverlay extends StatefulWidget {
  final List<TutorialStep> steps;
  final VoidCallback onComplete;
  final bool showSkipButton;

  /// "Try an example route" on the last card: fills in a sample route.
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
  final _pages = PageController();
  int _page = 0;

  // Set once the overlay starts fading out for good, so the fade doesn't take
  // taps meant for the map underneath.
  bool _closing = false;
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();

  static const _accent = Color(0xFF0B8FD6);

  bool get _isLast => _page == widget.steps.length - 1;

  @override
  void dispose() {
    _fade.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      _close();
    } else {
      _pages.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  void _close() {
    if (_closing) return;
    setState(() => _closing = true);
    _fade.reverse().then((_) => widget.onComplete());
  }

  void _tryExample() {
    widget.onExampleRouteRequested?.call();
    _close();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: _closing,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: Colors.black.withValues(alpha: 0.55),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _card(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            // Room for a phone screenshot, short of the whole screen.
            height: (height * 0.62).clamp(320.0, 560.0),
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.steps.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, i) => _stepPage(widget.steps[i], i),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.steps.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? _accent : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Skip, and on the last card the example in its place.
              if (_isLast && widget.onExampleRouteRequested != null)
                Flexible(
                  child: TextButton(
                    onPressed: _tryExample,
                    child: const TranslatedText(
                      'Try an example route',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
              else if (widget.showSkipButton && !_isLast)
                TextButton(
                  onPressed: _close,
                  child: TranslatedText(
                    'Skip',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  minimumSize: const Size(112, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                child: TranslatedText(_isLast ? 'Got it!' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepPage(TutorialStep step, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child:
                step.image != null
                    ? Image.asset(
                      step.image!,
                      // Fills the width, zoomed to the part the card is about.
                      fit: BoxFit.cover,
                      alignment: Alignment(0, step.focus),
                      cacheWidth: 720,
                    )
                    : Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: AppColors.accentSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(step.icon, size: 42, color: _accent),
                      ),
                    ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${index + 1} of ${widget.steps.length}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        TranslatedText(
          step.title,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        TranslatedText(
          step.description,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
