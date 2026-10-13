import 'package:flutter/material.dart';

import '../../models/place.dart';
import 'place_widgets.dart' show placeNeutralColor;
import '../translated_text.dart';
import '../../theme/app_colors.dart';

/// The always-visible row of place-category chips under the search bar.
/// No selection means "All".
class PlaceCategoryChips extends StatelessWidget {
  final Set<PlaceCategory> selected;
  final VoidCallback onSelectAll;
  final ValueChanged<PlaceCategory> onToggle;

  const PlaceCategoryChips({
    super.key,
    required this.selected,
    required this.onSelectAll,
    required this.onToggle,
  });

  static const height = 32.0;
  static Color get _surface => AppColors.surface;
  static Color get _textPrimary => AppColors.textPrimary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(
            label: 'All',
            icon: Icons.apps,
            color: placeNeutralColor,
            isSelected: selected.isEmpty,
            onTap: onSelectAll,
          ),
          for (final category in PlaceCategory.values) ...[
            const SizedBox(width: 8),
            _chip(
              label: category.label,
              icon: category.icon,
              color: placeNeutralColor,
              isSelected: selected.contains(category),
              onTap: () => onToggle(category),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? color : _surface,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: isSelected ? Colors.white : color),
              const SizedBox(width: 5),
              TranslatedText(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : _textPrimary,
                  fontSize: 12,
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
