import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'translated_text.dart';

/// One control explained inside a step's card: its icon, name and what it
/// does.
class SpotlightPoint {
  final IconData icon;
  final String label;
  final String text;

  const SpotlightPoint(this.icon, this.label, this.text);
}

/// One stop of a [SpotlightTutorial]: the part of the screen it lights up
/// and what the card says about it.
class SpotlightStep {
  final String title;
  final String body;
  final List<SpotlightPoint> points;

  /// The widget to light up. Without it (and without [area]) the card sits
  /// in the middle of a fully dimmed screen.
  final GlobalKey? target;

  /// A part of the screen with no widget of its own (an area of the map),
  /// in the overlay's coordinates; [SpotlightTutorial.rectOf] measures the
  /// widgets around it. Null while those aren't laid out yet.
  final Rect? Function(RenderBox overlay)? area;

  /// Room left around the lit part.
  final double margin;

  /// Puts the screen in the state this step talks about (e.g. a step being
  /// drawn), before the lit part is measured.
  final VoidCallback? onShow;

  const SpotlightStep({
    required this.title,
    required this.body,
    this.points = const [],
    this.target,
    this.area,
    this.margin = 8,
    this.onShow,
  });
}

/// A step-by-step tour over a screen: the rest is dimmed and locked, one
/// part at a time is lit, and a card explains it. Shown over the screen it
/// explains (in the same Stack), so it lights the real controls.
class SpotlightTutorial extends StatefulWidget {
  final List<SpotlightStep> steps;

  /// Called once, when the last card is closed or the tour is skipped.
  final VoidCallback onComplete;

  final String finishLabel;

  /// A second way to close from the last card (e.g. "Try the example"),
  /// called right after [onComplete].
  final String? extraLabel;
  final VoidCallback? onExtra;

  const SpotlightTutorial({
    super.key,
    required this.steps,
    required this.onComplete,
    this.finishLabel = 'Got it!',
    this.extraLabel,
    this.onExtra,
  });

  /// Where [key]'s widget is, in [overlay]'s coordinates.
  static Rect? rectOf(GlobalKey key, RenderBox overlay) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return overlay.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
  }

  @override
  State<SpotlightTutorial> createState() => _SpotlightTutorialState();
}

class _SpotlightTutorialState extends State<SpotlightTutorial>
    with TickerProviderStateMixin {
  final _overlayKey = GlobalKey();
  int _index = 0;
  Rect? _hole;
  Rect? _holeFrom;
  bool _closing = false;
  int _measureToken = 0;

  /// Re-checks where the lit part is: the screen behind can still settle
  /// after the first measure (a card growing a line, a drawer easing down).
  Timer? _follow;

  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 0,
  )..forward();

  SpotlightStep get _step => widget.steps[_index];
  bool get _isLast => _index == widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    // After the first frame: a step's onShow rebuilds the screen behind
    // us, which can't happen while it's building this overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _show(0);
    });
    _follow = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _followTarget();
    });
  }

  void _followTarget() {
    if (!mounted || _closing || _move.isAnimating || _hole == null) return;
    final rect = _measure();
    if (rect == null) return;
    final old = _hole!;
    final moved =
        (rect.left - old.left).abs() > 1.5 ||
        (rect.top - old.top).abs() > 1.5 ||
        (rect.right - old.right).abs() > 1.5 ||
        (rect.bottom - old.bottom).abs() > 1.5;
    if (moved) _moveHoleTo(rect);
  }

  @override
  void dispose() {
    _follow?.cancel();
    _move.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _show(int index) {
    final token = ++_measureToken;
    setState(() => _index = index);
    widget.steps[index].onShow?.call();
    // The lit control may only appear once the screen rebuilds for this
    // step, so measure after the frame and retry for a few.
    _measureAfterFrame(token, attempts: 12);
  }

  void _measureAfterFrame(int token, {required int attempts}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _measureToken) return;
      final rect = _measure();
      final wantsHole = _step.target != null || _step.area != null;
      if (rect == null && wantsHole && attempts > 0) {
        _measureAfterFrame(token, attempts: attempts - 1);
        return;
      }
      _moveHoleTo(rect);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Rect? _measure() {
    final overlay = _overlayKey.currentContext?.findRenderObject();
    if (overlay is! RenderBox || !overlay.hasSize) return null;
    final step = _step;
    if (step.area != null) return step.area!(overlay);
    final target = step.target;
    if (target == null) return null;
    return SpotlightTutorial.rectOf(target, overlay)?.inflate(step.margin);
  }

  void _moveHoleTo(Rect? rect) {
    setState(() {
      _holeFrom = _currentHole();
      _hole = rect;
    });
    _move.forward(from: 0);
  }

  /// Where the hole is drawn right now, mid-move included.
  Rect? _currentHole() {
    final t = Curves.easeInOutCubic.transform(_move.value);
    if (_hole == null) return null;
    if (_holeFrom == null) return _hole;
    return Rect.lerp(_holeFrom, _hole, t);
  }

  void _next() {
    if (_isLast) {
      _close();
    } else {
      _show(_index + 1);
    }
  }

  void _back() {
    if (_index > 0) _show(_index - 1);
  }

  Future<void> _close({VoidCallback? then}) async {
    if (_closing) return;
    setState(() => _closing = true);
    await _fade.reverse();
    if (!mounted) return;
    widget.onComplete();
    then?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        // While fading out the map underneath already takes taps.
        ignoring: _closing,
        child: FadeTransition(
          opacity: _fade,
          child: AnimatedBuilder(
            animation: _move,
            builder: (context, _) {
              final hole = _currentHole();
              return Stack(
                key: _overlayKey,
                children: [
                  // Locks the screen: taps anywhere, the lit part included,
                  // stay with the tour.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: CustomPaint(
                        painter: _ScrimPainter(
                          hole: hole,
                          scrim: Colors.black.withValues(
                            alpha: AppColors.isDark ? 0.72 : 0.62,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _placeCard(hole),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _placeCard(Rect? hole) {
    // Positioned.fill + inner Stack: the card is a Positioned, which has to
    // sit straight in a Stack, not under the LayoutBuilder.
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final padding = MediaQuery.of(context).padding;
          const gap = 14.0;
          final card = _SpotlightCard(
            step: _step,
            index: _index,
            count: widget.steps.length,
            isLast: _isLast,
            finishLabel: widget.finishLabel,
            onNext: _next,
            onBack: _index > 0 ? _back : null,
            onSkip: _close,
            extraLabel: widget.extraLabel,
            onExtra:
                widget.onExtra == null
                    ? null
                    : () => _close(then: widget.onExtra),
          );
          if (hole == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: size.height * 0.8),
                  child: card,
                ),
              ),
            );
          }
          final top = padding.top + 8;
          final bottom = size.height - padding.bottom - 8;
          final above = hole.top - gap - top;
          final below = bottom - hole.bottom - gap;
          // The side with more room; the card scrolls if even that is short.
          // Kept on screen; on a very short screen the top limit wins.
          double within(double v, double lo, double hi) =>
              v < lo ? lo : (v > hi ? (hi < lo ? lo : hi) : v);
          if (below >= above) {
            return Stack(
              children: [
                Positioned(
                  left: 16,
                  right: 16,
                  top: within(hole.bottom + gap, top, bottom - 160),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: below.clamp(160, size.height),
                    ),
                    child: card,
                  ),
                ),
              ],
            );
          }
          return Stack(
            children: [
              Positioned(
                left: 16,
                right: 16,
                bottom: within(
                  size.height - hole.top + gap,
                  size.height - bottom,
                  size.height - top - 160,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: above.clamp(160, size.height),
                  ),
                  child: card,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  final Rect? hole;
  final Color scrim;

  _ScrimPainter({required this.hole, required this.scrim});

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Path()..addRect(Offset.zero & size);
    final lit = hole;
    if (lit == null) {
      canvas.drawPath(screen, Paint()..color = scrim);
      return;
    }
    final rrect = RRect.fromRectAndRadius(lit, const Radius.circular(16));
    canvas.drawPath(
      Path.combine(PathOperation.difference, screen, Path()..addRRect(rrect)),
      Paint()..color = scrim,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.scrim != scrim;
}

class _SpotlightCard extends StatelessWidget {
  final SpotlightStep step;
  final int index;
  final int count;
  final bool isLast;
  final String finishLabel;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;
  final String? extraLabel;
  final VoidCallback? onExtra;

  const _SpotlightCard({
    required this.step,
    required this.index,
    required this.count,
    required this.isLast,
    required this.finishLabel,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
    this.extraLabel,
    this.onExtra,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${index + 1} of $count',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (!isLast)
                  TextButton(
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const TranslatedText('Skip tour'),
                  ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TranslatedText(
                      step.title,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TranslatedText(
                      step.body,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                    for (final point in step.points) ...[
                      const SizedBox(height: 10),
                      _PointRow(point: point),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Wraps onto a second line on a narrow screen or in a long
            // translation.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  if (isLast && extraLabel != null && onExtra != null)
                    TextButton(
                      onPressed: onExtra,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.accent,
                      ),
                      child: TranslatedText(extraLabel!),
                    )
                  else if (onBack != null)
                    TextButton(
                      onPressed: onBack,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                      ),
                      child: const TranslatedText('Back'),
                    ),
                  FilledButton(
                    onPressed: onNext,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: TranslatedText(
                      isLast ? finishLabel : 'Next',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PointRow extends StatelessWidget {
  final SpotlightPoint point;

  const _PointRow({required this.point});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(point.icon, size: 16, color: AppColors.textPrimary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TranslatedText(
                point.label,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 1),
              TranslatedText(
                point.text,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
