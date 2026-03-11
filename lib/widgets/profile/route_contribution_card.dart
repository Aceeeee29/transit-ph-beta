import 'package:flutter/material.dart';
import '../../models/route.dart' as route_model;
import '../../screens/contribute_screen.dart';
import '../../services/route_service.dart';
import '../../services/route_metrics_service.dart';
import 'profile_colors.dart';

class RouteContributionCard extends StatelessWidget {
  final route_model.Route route;
  final String userEmail;

  const RouteContributionCard({
    super.key,
    required this.route,
    required this.userEmail,
  });

  double _calculateAverageRating() {
    final total = route.upvotes + route.downvotes;
    if (total == 0) return 0.0;
    return (route.upvotes - route.downvotes) / (total + 1);
  }

  @override
  Widget build(BuildContext context) {
    final distance = RouteMetricsService.calculateRouteDistance(route.pathPoints);
    final avgRating = _calculateAverageRating();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ProfileColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ProfileColors.border),
        boxShadow: [
          BoxShadow(
            color: ProfileColors.accent.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(route: route, userEmail: userEmail),
            const SizedBox(height: 14),
            Divider(color: ProfileColors.border, height: 1),
            const SizedBox(height: 12),
            _MetricsGrid(route: route, avgRating: avgRating),
            const SizedBox(height: 10),
            Row(
              children: [
                _infoPill(
                  icon: Icons.straighten,
                  label: '${distance.toStringAsFixed(1)} km',
                ),
                const SizedBox(width: 8),
                _infoPill(
                  icon: Icons.schedule_outlined,
                  label: route.eta ?? 'N/A',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ProfileColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ProfileColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: ProfileColors.accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: ProfileColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final route_model.Route route;
  final String userEmail;

  const _CardHeader({required this.route, required this.userEmail});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: ProfileColors.accentSoft,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.alt_route, color: ProfileColors.accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                route.shortDescription,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ProfileColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              _locationRow(Icons.radio_button_checked, route.startLocation),
              const SizedBox(height: 1),
              _locationRow(Icons.location_on_outlined, route.endLocation),
            ],
          ),
        ),
        _editButton(context),
      ],
    );
  }

  Widget _locationRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 11, color: ProfileColors.accent),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: ProfileColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _editButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContributeScreen(
            onRouteSubmitted: (updatedRoute) async {
              try {
                await RouteService.updateRoute(updatedRoute);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Route updated!')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to update route: $e')),
                );
              }
            },
            routeToEdit: route,
            contributorId: userEmail,
          ),
        ),
      ),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: ProfileColors.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: ProfileColors.border),
        ),
        child: const Icon(
          Icons.edit_outlined,
          size: 16,
          color: ProfileColors.textSecondary,
        ),
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  final route_model.Route route;
  final double avgRating;

  const _MetricsGrid({required this.route, required this.avgRating});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ProfileColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ProfileColors.border),
      ),
      child: Row(
        children: [
          _metricCell('👥', '${route.views}', 'Views'),
          _vDivider(),
          _metricCell('⭐', avgRating.toStringAsFixed(1), 'Rating'),
          _vDivider(),
          _metricCell('👍', '${route.upvotes}', 'Upvotes'),
          _vDivider(),
          _metricCell('👎', '${route.downvotes}', 'Downvotes'),
        ],
      ),
    );
  }

  Widget _metricCell(String emoji, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: ProfileColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: ProfileColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() {
    return Container(width: 1, height: 36, color: ProfileColors.border);
  }
}
