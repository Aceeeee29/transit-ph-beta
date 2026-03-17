import 'package:flutter/material.dart';
import 'feed_colors.dart';

/// Small icon button used in the feed post action bar.
class FeedActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool active;
  final String? label;

  const FeedActionButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
    this.active = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.1) : FeedColors.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: active ? color.withOpacity(0.3) : FeedColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                label!,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
