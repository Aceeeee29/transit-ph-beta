import 'package:flutter/material.dart';

import '../translated_text.dart';
import '../../theme/app_colors.dart';

/// The big search pill across the top of the Map tab, Google Maps style.
/// The whole bar is one tap target; the round buttons on its right side are
/// separate actions (contribute a route, tutorial).
class MapSearchBar extends StatelessWidget {
  final String hintText;
  final VoidCallback onTap;

  /// Replaces the app pin on the left, e.g. a back arrow out of a mode.
  final Widget? leading;
  final List<MapSearchBarAction> actions;

  const MapSearchBar({
    super.key,
    required this.hintText,
    required this.onTap,
    this.leading,
    this.actions = const [],
  });

  static Color get _surface => AppColors.surface;
  static const _accent = Color(0xFF0B8FD6);
  static Color get _textSecondary => AppColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              const SizedBox(width: 6),
              leading ??
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.location_on_rounded,
                      color: _accent,
                      size: 26,
                    ),
                  ),
              const SizedBox(width: 2),
              Expanded(
                child: TranslatedText(
                  hintText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              for (final action in actions)
                IconButton(
                  onPressed: action.onTap,
                  tooltip: action.tooltip,
                  icon: Icon(action.icon, color: action.color ?? _accent),
                ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class MapSearchBarAction {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const MapSearchBarAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });
}
