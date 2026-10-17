import 'package:flutter/material.dart';

import '../../models/route_issue_report.dart';
import '../../theme/app_colors.dart';

/// Riders' reports on the road a route rides (from any route on it): the
/// latest one, and how many more.
class RouteReportBanner extends StatelessWidget {
  const RouteReportBanner({super.key, required this.reports, this.routeId});

  /// Newest first.
  final List<RouteIssueReport> reports;

  /// The route being shown, so a report filed on it isn't labeled as
  /// coming from another route.
  final String? routeId;

  static const _amber = Color(0xFFB7791F);

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) return const SizedBox.shrink();
    final latest = reports.first;
    final others = reports.length - 1;
    final elsewhere = latest.routeId != routeId;
    final detail = [
      if (elsewhere) 'On ${latest.routeLabel}',
      if (latest.description case final note? when note.isNotEmpty) note,
    ].join(': ');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: AppColors.isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.report_problem_outlined, color: _amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${latest.type} · reported ${_ago(latest.createdAt)}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
                if (others > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    others == 1
                        ? '1 more report on this road'
                        : '$others more reports on this road',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _amber,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }
}
