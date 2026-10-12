import 'package:flutter/material.dart';

import '../translated_text.dart';

const _surface = Color(0xFFFFFFFF);
const _accent = Color(0xFF0B8FD6);
const _textPrimary = Color(0xFF0F1D35);
const _textSecondary = Color(0xFF7A92B2);
const _danger = Color(0xFFE05C6A);
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
              icon: const Icon(Icons.arrow_back_rounded, color: _textPrimary),
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
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
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
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 12,
                          ),
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
        icon: const Icon(Icons.arrow_back_rounded, color: _textPrimary),
      ),
    );
  }
}

/// The route drawer's resting row: time left (or the trip time), the
/// distance and fare under it, and Start / Stop / Done on the right.
class RouteDrawerHeader extends StatelessWidget {
  final String primary;
  final String? secondary;
  final Widget trailing;

  /// Who suggested the route, e.g. "Suggested by Juan".
  final String? byline;

  const RouteDrawerHeader({
    super.key,
    required this.primary,
    required this.secondary,
    required this.trailing,
    this.byline,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TranslatedText(
                  primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                if (secondary != null)
                  Text(
                    secondary!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (byline != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
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
                          style: const TextStyle(
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
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

/// Start, Stop, or Done once arrived.
class RouteFollowButton extends StatelessWidget {
  final bool isFollowing;
  final bool hasArrived;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onDone;

  const RouteFollowButton({
    super.key,
    required this.isFollowing,
    required this.hasArrived,
    required this.onStart,
    required this.onStop,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
    );
    const padding = EdgeInsets.symmetric(horizontal: 18);
    const minSize = Size(0, 44);
    if (hasArrived) {
      return FilledButton.icon(
        onPressed: onDone,
        icon: const Icon(Icons.check_circle_rounded, size: 18),
        label: const TranslatedText('Done'),
        style: FilledButton.styleFrom(
          backgroundColor: _green,
          shape: shape,
          padding: padding,
          minimumSize: minSize,
        ),
      );
    }
    if (isFollowing) {
      return OutlinedButton.icon(
        onPressed: onStop,
        icon: const Icon(Icons.stop_rounded, size: 18),
        label: const TranslatedText('Stop'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _danger,
          side: BorderSide(color: _danger.withValues(alpha: 0.5)),
          shape: shape,
          padding: padding,
          minimumSize: minSize,
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onStart,
      icon: const Icon(Icons.navigation_rounded, size: 18),
      label: const TranslatedText('Start'),
      style: FilledButton.styleFrom(
        backgroundColor: _accent,
        shape: shape,
        padding: padding,
        minimumSize: minSize,
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
          active
              ? activeColor.withValues(alpha: 0.12)
              : const Color(0xFFF0F4FA),
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
