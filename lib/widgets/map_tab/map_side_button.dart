import 'package:flutter/material.dart';

/// A round icon-only map button for the right-side stack (GPS center, hide
/// pins, report). No labels; the tooltip says what it does.
class MapSideButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Filled accent, e.g. the GPS button while the camera follows you.
  final bool active;
  final Color? iconColor;
  final bool busy;

  const MapSideButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.iconColor,
    this.busy = false,
  });

  static const size = 48.0;
  static const _surface = Color(0xFFFFFFFF);
  static const _accent = Color(0xFF0B8FD6);
  static const _textSecondary = Color(0xFF5B6F8E);

  @override
  Widget build(BuildContext context) {
    final foreground = active ? Colors.white : (iconColor ?? _textSecondary);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? _accent : _surface,
        elevation: 3,
        shadowColor: Colors.black26,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child:
                busy
                    ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foreground,
                      ),
                    )
                    : Icon(icon, color: foreground, size: 22),
          ),
        ),
      ),
    );
  }
}

/// The right-side column of [MapSideButton]s.
class MapSideButtons extends StatelessWidget {
  final List<Widget> children;

  const MapSideButtons({super.key, required this.children});

  static const gap = 10.0;

  /// Height of a column of [count] buttons, for placing things above it.
  static double heightFor(int count) =>
      count <= 0 ? 0 : count * MapSideButton.size + (count - 1) * gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          children[i],
        ],
      ],
    );
  }
}
