import 'package:flutter/material.dart';

import 'translated_text.dart';

/// Marks a ride that comes from an admin-approved, user-contributed route
/// rather than government GTFS data.
class CommunityRouteBadge extends StatelessWidget {
  final String label;

  const CommunityRouteBadge({super.key, this.label = 'Community route'});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 12, color: Colors.green.shade700),
          const SizedBox(width: 3),
          Flexible(
            child: TranslatedText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
