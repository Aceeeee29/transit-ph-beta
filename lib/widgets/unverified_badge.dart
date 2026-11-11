import 'package:flutter/material.dart';

import '../services/route_issue_service.dart';
import 'translated_text.dart';

/// Marks a route that 5 or more riders say has changed, like a new fare or a
/// route that stopped running. Search avoids it, and this says why. Shows
/// nothing for other routes.
class PossiblyOutdatedBadge extends StatelessWidget {
  /// The route's id, or `gtfs:<route_id>` for the DOTC 2013 feed.
  final String routeKey;

  const PossiblyOutdatedBadge({super.key, required this.routeKey});

  static const _color = Color(0xFFC2410C);

  @override
  Widget build(BuildContext context) {
    final label = RouteIssueService.labelFor(routeKey);
    if (label == null) return const SizedBox.shrink();
    return Tooltip(
      message: label.summary,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _color.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 12, color: _color),
            SizedBox(width: 3),
            Flexible(
              child: TranslatedText(
                'Possibly outdated',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: _color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Marks a live route that only the automatic checks have looked at so far, so
/// riders know to treat it with a little more care.
class UnverifiedBadge extends StatelessWidget {
  const UnverifiedBadge({super.key});

  static const _color = Color(0xFFB7791F);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.help_outline_rounded, size: 12, color: _color),
          SizedBox(width: 3),
          Flexible(
            child: TranslatedText(
              'Unverified',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
