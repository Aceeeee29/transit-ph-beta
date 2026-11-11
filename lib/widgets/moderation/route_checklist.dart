import 'package:flutter/material.dart';

import '../../models/route.dart' as route_model;
import '../../theme/app_colors.dart';

/// The automatic checks, for a moderator deciding on a route. What needs their
/// attention comes first. What passed is folded away, since they only need to
/// know it was checked.
class RouteChecklist extends StatelessWidget {
  final List<route_model.RouteCheck> checks;

  const RouteChecklist({super.key, required this.checks});

  static const _danger = Color(0xFFE05C6A);
  static const _warning = Color(0xFFB7791F);
  static const _success = Color(0xFF2E9E5B);

  @override
  Widget build(BuildContext context) {
    final problems = [
      ...checks.where((c) => c.failed),
      ...checks.where((c) => c.flagged),
    ];
    final passed = checks.where((c) => c.passed).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CHECKLIST',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        for (final check in problems) _row(check),
        if (passed.isNotEmpty)
          Theme(
            // The default divider lines look out of place inside a card.
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              dense: true,
              visualDensity: VisualDensity.compact,
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text(
                '${passed.length} checks passed',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _success,
                ),
              ),
              children: [for (final check in passed) _row(check)],
            ),
          ),
      ],
    );
  }

  Widget _row(route_model.RouteCheck check) {
    final (icon, color) =
        check.failed
            ? (Icons.error_outline_rounded, _danger)
            : check.flagged
            ? (Icons.flag_outlined, _warning)
            : (Icons.check_circle_outline_rounded, _success);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              check.message,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
