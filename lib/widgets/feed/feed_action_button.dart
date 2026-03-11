import 'package:flutter/material.dart';
import 'feed_colors.dart';

/// Small icon button used in the feed post action bar.
class FeedActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool active;

  const FeedActionButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
    this.active = false,
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
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }
}
