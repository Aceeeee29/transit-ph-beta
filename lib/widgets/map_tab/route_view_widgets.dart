import 'package:flutter/material.dart';

import '../route_map/route_modes.dart';
import '../route_map/step_done_label.dart';
import '../translated_text.dart';
import '../../theme/app_colors.dart';

Color get _surface => AppColors.surface;
const _accent = Color(0xFF0B8FD6);
Color get _textPrimary => AppColors.textPrimary;
Color get _textSecondary => AppColors.textSecondary;
const _green = Color(0xFF2D9F63);

/// The pill across the top of a route view before it is followed: back to
/// the map, and where the route goes.
class RouteTopBar extends StatelessWidget {
  final String from;
  final String to;
  final VoidCallback onBack;

  const RouteTopBar({
    super.key,
    required this.from,
    required this.to,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            const SizedBox(width: 4),
            IconButton(
              onPressed: onBack,
              tooltip: 'Back to map',
              icon: Icon(Icons.arrow_back_rounded, color: _textPrimary),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    from,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.arrow_forward,
                        size: 12,
                        color: _textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          to,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

/// A round back button, for beside the guidance card while following.
class RouteBackButton extends StatelessWidget {
  final VoidCallback onBack;

  const RouteBackButton({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onBack,
        tooltip: 'Back to map',
        icon: Icon(Icons.arrow_back_rounded, color: _textPrimary),
      ),
    );
  }
}

/// The route drawer's resting part, the same on every route view. The
/// centered time ([primary]) over distance and fare; an X to stop
/// on the left while following, and the whole-route button on the right.
/// Before Start (and once arrived) a full-width Start (Done) button sits
/// under it.
class RouteDrawerHeader extends StatelessWidget {
  /// "25 min".
  final String primary;

  /// "6.3 km · ₱26 est.".
  final String? secondary;

  /// Who suggested the route, e.g. "Suggested by Juan". Not while following.
  final String? byline;

  final bool isFollowing;
  final bool hasArrived;

  /// Start pressed, waiting for the first GPS fix.
  final bool isStarting;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onDone;
  final VoidCallback onOverview;

  const RouteDrawerHeader({
    super.key,
    required this.primary,
    required this.secondary,
    required this.isFollowing,
    required this.hasArrived,
    required this.onStart,
    required this.onStop,
    required this.onDone,
    required this.onOverview,
    this.byline,
    this.isStarting = false,
  });

  /// The drawer's resting height (handle included) for this header.
  static double peekHeight({required bool showsButton, bool byline = false}) =>
      22 + 76 + (byline ? 18 : 0) + (showsButton ? 64 : 0);

  bool get _showsButton => !isFollowing || hasArrived;

  @override
  Widget build(BuildContext context) {
    final details = secondary ?? '';
    final showsByline = byline != null && !isFollowing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 76 + (showsByline ? 18 : 0),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child:
                      isFollowing && !hasArrived
                          ? _RoundIconButton(
                            icon: Icons.close_rounded,
                            tooltip: 'Stop route',
                            onTap: onStop,
                          )
                          : null,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TranslatedText(
                        primary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (showsByline) ...[
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 13,
                              color: _textSecondary,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                byline!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: _RoundIconButton(
                    icon: Icons.alt_route_rounded,
                    tooltip: 'Whole route',
                    onTap: onOverview,
                  ),
                ),
              ],
            ),
          ),
          if (_showsButton)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: hasArrived ? _doneButton() : _startButton(),
              ),
            ),
        ],
      ),
    );
  }

  static final _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(23),
  );

  Widget _startButton() {
    return FilledButton.icon(
      onPressed: isStarting ? null : onStart,
      icon:
          isStarting
              ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
              : const Icon(Icons.navigation_rounded, size: 18),
      label: TranslatedText(
        isStarting ? 'Getting your location…' : 'Start',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: _accent,
        disabledBackgroundColor: _accent.withValues(alpha: 0.75),
        disabledForegroundColor: Colors.white,
        shape: _shape,
      ),
    );
  }

  Widget _doneButton() {
    return FilledButton.icon(
      onPressed: onDone,
      icon: const Icon(Icons.check_circle_rounded, size: 18),
      label: const TranslatedText(
        'Done',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      style: FilledButton.styleFrom(backgroundColor: _green, shape: _shape),
    );
  }
}

/// The drawer header's round X and whole-route buttons.
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: AppColors.surfaceAlt,
        shape: CircleBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: _textPrimary, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small caps heading in a route drawer ("ROUTE STEPS (4)").
class RouteSectionLabel extends StatelessWidget {
  final String label;

  const RouteSectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: _textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// One step in a route drawer's list, the same on every route view: the
/// mode's icon and number, mode and length, the instruction, any [extras]
/// (details, boarding, schedule…) and the fare. Done steps are crossed out.
class RouteStepCard extends StatelessWidget {
  final int number;
  final String mode;
  final String instruction;
  final bool isCompleted;

  /// "1.2 km", beside the mode.
  final String? distance;

  /// "Fare: PHP 13 (estimated)", with a discount line under it if any.
  final String? fare;
  final List<Widget> extras;

  const RouteStepCard({
    super.key,
    required this.number,
    required this.mode,
    required this.instruction,
    required this.isCompleted,
    this.distance,
    this.fare,
    this.extras = const [],
  });

  @override
  Widget build(BuildContext context) {
    final modeColor = isCompleted ? _textSecondary : RouteModes.color(mode);
    final instructionStyle = TextStyle(
      fontSize: 13,
      color: _textPrimary,
      height: 1.4,
    );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: isCompleted ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isCompleted ? AppColors.surfaceAlt : _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: modeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: modeColor.withValues(alpha: 0.3)),
                  ),
                  child: Icon(
                    isCompleted ? Icons.check_rounded : RouteModes.icon(mode),
                    color: modeColor,
                    size: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Center(
                    child: Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        mode,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: modeColor,
                        ),
                      ),
                      if (distance != null)
                        Text(
                          ' · $distance',
                          style: TextStyle(fontSize: 12, color: _textSecondary),
                        ),
                      if (isCompleted) ...[
                        const SizedBox(width: 6),
                        const StepDoneLabel(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    instruction,
                    style:
                        isCompleted
                            ? StepDoneLabel.strike(instructionStyle)
                            : instructionStyle,
                  ),
                  ...extras,
                  if (fare != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF8F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFB9E4C6)),
                      ),
                      child: Text(
                        fare!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF2D9F63),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which color is which mode on the map, inline under the drawer actions.
class RouteModeLegend extends StatelessWidget {
  final List<String> modes;

  const RouteModeLegend({super.key, required this.modes});

  @override
  Widget build(BuildContext context) {
    if (modes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final mode in modes)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 4,
                  decoration: BoxDecoration(
                    color: RouteModes.color(mode),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  RouteModes.icon(mode),
                  size: 13,
                  color: RouteModes.color(mode),
                ),
                const SizedBox(width: 3),
                Text(
                  mode,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A pill in the drawer's action row (votes, download, fit route).
class RouteActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final Color activeColor;
  final bool busy;

  const RouteActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor = _accent,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : _textPrimary;
    return Material(
      color:
          active ? activeColor.withValues(alpha: 0.12) : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  icon,
                  size: 17,
                  color: active ? activeColor : _textSecondary,
                ),
              const SizedBox(width: 6),
              TranslatedText(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
