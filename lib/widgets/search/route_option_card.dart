import 'package:flutter/material.dart';

/// One route in a search result list. Every option (generated or
/// community) uses the same row so they read the same way: the main fact on
/// top, the rest in grey under it, then the modes in order.
class RouteOptionRow extends StatelessWidget {
  final String headline;
  final String details;
  final List<String> modes;
  final String? tag;

  /// Tints the tag, e.g. for options built from community routes.
  final bool tagHighlighted;
  final VoidCallback? onTap;
  final bool busy;

  const RouteOptionRow({
    super.key,
    required this.headline,
    required this.details,
    required this.modes,
    this.tag,
    this.tagHighlighted = false,
    this.onTap,
    this.busy = false,
  });

  static const _accent = Color(0xFF0B8FD6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF6B7F99);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          headline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (tag != null) ...[
                        const SizedBox(width: 8),
                        _Tag(label: tag!, highlighted: tagHighlighted),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _textSecondary, fontSize: 13),
                  ),
                  if (modes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ModeSequence(modes: modes),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            busy
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFB4C2D6),
                ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final bool highlighted;

  const _Tag({required this.label, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    const accent = RouteOptionRow._accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color:
            highlighted
                ? accent.withValues(alpha: 0.1)
                : const Color(0xFFF0F3F8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlighted ? accent : RouteOptionRow._textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// The modes of a trip as small icons in order: walk › jeep › train.
class ModeSequence extends StatelessWidget {
  final List<String> modes;

  const ModeSequence({super.key, required this.modes});

  static IconData iconFor(String mode) {
    switch (mode) {
      case 'Walk':
        return Icons.directions_walk_rounded;
      case 'Bus':
        return Icons.directions_bus_filled_rounded;
      case 'Train':
        return Icons.train_rounded;
      case 'Tricycle':
        return Icons.two_wheeler_rounded;
      case 'FX/Van':
        return Icons.airport_shuttle_rounded;
      case 'Ferry':
        return Icons.directions_boat_rounded;
      default:
        return Icons.directions_bus_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 4,
      children: [
        for (var i = 0; i < modes.length; i++) ...[
          if (i > 0)
            const Icon(
              Icons.chevron_right_rounded,
              size: 14,
              color: Color(0xFFB4C2D6),
            ),
          Tooltip(
            message: modes[i],
            child: Icon(
              iconFor(modes[i]),
              size: 17,
              color: RouteOptionRow._textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// A titled group of [RouteOptionRow]s on one white surface.
class RouteOptionSection extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;
  final String? footnote;

  const RouteOptionSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: RouteOptionRow._textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      indent: 16,
                      color: Color(0xFFEDF1F7),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ),
        if (footnote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              footnote!,
              style: const TextStyle(
                color: RouteOptionRow._textSecondary,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}

/// Collapses consecutive repeats, so walk › walk › jeep shows walk › jeep.
List<String> collapseModes(Iterable<String> modes) {
  final out = <String>[];
  for (final mode in modes) {
    if (out.isEmpty || out.last != mode) out.add(mode);
  }
  return out;
}
