import 'package:flutter/material.dart';
import '../../models/route.dart' as route_model;
import '../../models/route_rejection_reason.dart';
import '../../screens/contribute_screen.dart';
import '../../services/route_service.dart';
import '../../services/route_metrics_service.dart';
import '../../services/route_trust_service.dart';
import '../unverified_badge.dart';
import 'profile_colors.dart';

class RouteContributionCard extends StatelessWidget {
  final route_model.Route route;
  final String userEmail;
  final String distanceUnit;

  /// Called when the editor closes, so the list can show the new status.
  final VoidCallback? onEdited;

  const RouteContributionCard({
    super.key,
    required this.route,
    required this.userEmail,
    required this.distanceUnit,
    this.onEdited,
  });

  /// Saving only: the editor confirms and closes itself. (This card can be gone
  /// by then: an edited route goes back to pending, which rebuilds the list,
  /// and using its context failed with "Null check operator used on a null
  /// value".)
  static void openEditor(
    BuildContext context, {
    required route_model.Route route,
    required String userEmail,
    VoidCallback? onEdited,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ContributeScreen(
              onRouteSubmitted: RouteService.updateRoute,
              routeToEdit: route,
              contributorId: userEmail,
            ),
      ),
    ).then((_) => onEdited?.call());
  }

  /// Asks first, then deletes a rider's own pending or rejected route. This is
  /// how a rider frees a slot when their 3 pending routes are all waiting.
  static Future<void> confirmAndDelete(
    BuildContext context, {
    required route_model.Route route,
    VoidCallback? onDeleted,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete this route?'),
            content: Text(
              route.isPending
                  ? 'It will be taken out of the review queue and deleted. '
                      'This can\'t be undone.'
                  : 'It will be deleted. This can\'t be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: ProfileColors.danger,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await RouteService.deleteRoute(route.id);
      messenger.showSnackBar(const SnackBar(content: Text('Route deleted.')));
    } catch (e) {
      // Most likely a moderator decided on it a moment ago.
      debugPrint('[RouteContributionCard] Delete failed: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Couldn\'t delete it. It may have just been reviewed. Pull to refresh and try again.',
          ),
        ),
      );
    }
    onDeleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final distance = RouteMetricsService.routeDistanceKm(route);
    final distanceLabel = RouteMetricsService.formatDistanceForUnit(
      distance,
      distanceUnit: distanceUnit,
    );

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
            _CardHeader(route: route, userEmail: userEmail, onEdited: onEdited),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusChip(route: route),
                if (route.isUnverified) const UnverifiedBadge(),
                PossiblyOutdatedBadge(routeKey: route.id),
              ],
            ),
            // Why a moderator needs to look and what the rider can do about
            // it, so a wait isn't a mystery.
            if (route.isPending)
              _WaitingPanel(
                route: route,
                userEmail: userEmail,
                onEdited: onEdited,
              ),
            if (route.approvalStatus ==
                route_model.RouteApprovalStatus.rejected)
              _RejectionPanel(
                route: route,
                userEmail: userEmail,
                onEdited: onEdited,
              ),
            const SizedBox(height: 14),
            Divider(color: ProfileColors.border, height: 1),
            const SizedBox(height: 12),
            _MetricsGrid(route: route),
            const SizedBox(height: 10),
            Row(
              children: [
                _infoPill(icon: Icons.straighten, label: distanceLabel),
                const SizedBox(width: 8),
                _infoPill(
                  icon: Icons.schedule_outlined,
                  label: RouteMetricsService.routeEtaLabel(route),
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
            style: TextStyle(
              fontSize: 12,
              color: ProfileColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Waiting for review · 3 days". Kept apart for tests.
String waitingLabel(route_model.Route route, [DateTime? now]) {
  final days = route.daysWaiting(now);
  final since = switch (days) {
    0 => 'since today',
    1 => '1 day',
    _ => '$days days',
  };
  return 'Waiting for review · $since';
}

class _StatusChip extends StatelessWidget {
  final route_model.Route route;

  const _StatusChip({required this.route});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (route.approvalStatus) {
      route_model.RouteApprovalStatus.approved => (
        'Live',
        const Color(0xFF2E9E5B),
      ),
      route_model.RouteApprovalStatus.pending => (
        waitingLabel(route),
        const Color(0xFFB7791F),
      ),
      route_model.RouteApprovalStatus.rejected => (
        'Rejected',
        ProfileColors.danger,
      ),
      route_model.RouteApprovalStatus.withdrawn => (
        'Withdrawn',
        ProfileColors.textSecondary,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

/// What a pending route is waiting on. Each flag says whether the rider can
/// fix it or only has to wait, and an Edit button shows when there's
/// something to fix.
class _WaitingPanel extends StatelessWidget {
  final route_model.Route route;
  final String userEmail;
  final VoidCallback? onEdited;

  const _WaitingPanel({
    required this.route,
    required this.userEmail,
    this.onEdited,
  });

  static const _wait = Color(0xFFB7791F);

  @override
  Widget build(BuildContext context) {
    final flags = route.flaggedChecks;
    final canFix = flags.any((check) => check.riderCanFix);
    final daysLeft = route_model.Route.reviewDays - route.daysWaiting();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final check in flags)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    check.message,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: ProfileColors.textPrimary,
                    ),
                  ),
                  Text(
                    check.riderNextStep,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color:
                          check.riderCanFix
                              ? ProfileColors.accent
                              : ProfileColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          // Only "new contributor" is left, so the wait has an end.
          if (route.goesLiveWhenWaited)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                daysLeft > 1
                    ? 'If no moderator gets to it, it goes live as Unverified in $daysLeft days.'
                    : daysLeft == 1
                    ? 'If no moderator gets to it, it goes live as Unverified tomorrow.'
                    : 'No moderator got to it in ${route_model.Route.reviewDays} days, so it goes live as Unverified within the hour.',
                style: const TextStyle(fontSize: 12, height: 1.4, color: _wait),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (canFix)
                OutlinedButton.icon(
                  onPressed:
                      () => RouteContributionCard.openEditor(
                        context,
                        route: route,
                        userEmail: userEmail,
                        onEdited: onEdited,
                      ),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit route'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ProfileColors.accent,
                    side: const BorderSide(color: ProfileColors.accent),
                  ),
                ),
              _DeleteButton(route: route, onDeleted: onEdited),
            ],
          ),
        ],
      ),
    );
  }
}

/// Why the route was rejected, and the way to fix it. Sending it again is the
/// rider's appeal, so there's no separate appeal flow.
class _RejectionPanel extends StatelessWidget {
  final route_model.Route route;
  final String userEmail;
  final VoidCallback? onEdited;

  const _RejectionPanel({
    required this.route,
    required this.userEmail,
    this.onEdited,
  });

  @override
  Widget build(BuildContext context) {
    final decision = route.latestDecision;
    // A moderator's reasons have labels. The checks explain themselves below, so
    // their codes are left out here.
    final reasons = (decision?.reasonCodes ?? const <String>[])
        .map((code) => RouteRejectionReason.byCode(code)?.label)
        .whereType<String>()
        .join(', ');
    final note = decision?.note?.trim() ?? '';
    final failed = route.failedChecks;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ProfileColors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ProfileColors.danger.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Routes rejected before reasons existed have none to show.
          if (reasons.isNotEmpty || failed.isEmpty)
            Text(
              reasons.isEmpty ? 'No reason was recorded.' : reasons,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ProfileColors.textPrimary,
              ),
            ),
          for (final check in failed)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                check.message,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: ProfileColors.textPrimary,
                ),
              ),
            ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              note,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: ProfileColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed:
                    () => RouteContributionCard.openEditor(
                      context,
                      route: route,
                      userEmail: userEmail,
                      onEdited: onEdited,
                    ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit and resubmit'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ProfileColors.accent,
                  side: const BorderSide(color: ProfileColors.accent),
                ),
              ),
              _DeleteButton(route: route, onDeleted: onEdited),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final route_model.Route route;
  final String userEmail;
  final VoidCallback? onEdited;

  const _CardHeader({
    required this.route,
    required this.userEmail,
    this.onEdited,
  });

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
          child: const Icon(
            Icons.alt_route,
            color: ProfileColors.accent,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                route.shortDescription,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
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
            style: TextStyle(fontSize: 12, color: ProfileColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _editButton(BuildContext context) {
    return GestureDetector(
      onTap:
          () => RouteContributionCard.openEditor(
            context,
            route: route,
            userEmail: userEmail,
            onEdited: onEdited,
          ),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: ProfileColors.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: ProfileColors.border),
        ),
        child: Icon(
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

  const _MetricsGrid({required this.route});

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
          _integrityMetricCell(),
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
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ProfileColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: ProfileColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _integrityMetricCell() {
    return Expanded(
      child: StreamBuilder<Map<String, int>>(
        stream: RouteService.watchRouteFeedbackSummary(route.id),
        builder: (context, snapshot) {
          final summary =
              snapshot.data ??
              const {
                'fareAccurateYes': 0,
                'fareAccurateNo': 0,
                'scheduleAccurateYes': 0,
                'scheduleAccurateNo': 0,
                'stillOperatingYes': 0,
                'stillOperatingNo': 0,
              };

          final trust = RouteTrustService.computeConfidence(
            route: route,
            feedbackSummary: summary,
          );

          return Column(
            children: [
              const Text('🛡️', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                '${trust.total}/100',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: ProfileColors.textPrimary,
                ),
              ),
              Text(
                'Integrity',
                style: TextStyle(
                  fontSize: 10,
                  color: ProfileColors.textSecondary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _vDivider() {
    return Container(width: 1, height: 36, color: ProfileColors.border);
  }
}

/// The "Delete" link under a pending or rejected route.
class _DeleteButton extends StatelessWidget {
  final route_model.Route route;
  final VoidCallback? onDeleted;

  const _DeleteButton({required this.route, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed:
          () => RouteContributionCard.confirmAndDelete(
            context,
            route: route,
            onDeleted: onDeleted,
          ),
      icon: const Icon(Icons.delete_outline, size: 16),
      label: const Text('Delete'),
      style: TextButton.styleFrom(foregroundColor: ProfileColors.danger),
    );
  }
}
