import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/camanava_places.dart';
import '../../models/ors_route_result.dart';
import '../../models/route.dart' as route_model;
import '../../screens/contribute_screen.dart';
import '../../services/active_navigation_service.dart';
import '../../services/ride_correction.dart';
import '../../services/route_metrics_service.dart';
import '../../services/route_service.dart';
import '../../services/routing_service.dart';
import '../translated_text.dart';

enum _RideChoice { correction, newRoute }

/// After a follow ends: when the vehicle went a different way than the
/// route, offers to turn the ride into a suggested correction of the route
/// (saved routes only) or a new route. Either opens the editor with the
/// ride already applied, so the rider can check it before submitting; both
/// go to moderator review. A one-time detour can just be dismissed.
class RideCorrectionFlow {
  static Future<void> offer(
    BuildContext context, {
    required List<RideDeviation> deviations,
    required List<LatLng> followedPath,
    route_model.Route? route,
    List<int> stepBoundaries = const [],
    OrsRouteResult? generated,
    String originName = '',
    String destinationName = '',
  }) async {
    if (deviations.isEmpty || followedPath.length < 2) return;

    final choice = await showDialog<_RideChoice>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const TranslatedText('Your ride took a different way'),
            content: TranslatedText(_summary(deviations)),
            actionsOverflowDirection: VerticalDirection.down,
            actionsOverflowButtonSpacing: 4,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const TranslatedText('It was a one-time detour'),
              ),
              TextButton(
                onPressed:
                    () => Navigator.of(dialogContext).pop(_RideChoice.newRoute),
                child: const TranslatedText('Save as a new route'),
              ),
              if (route != null)
                FilledButton(
                  onPressed:
                      () => Navigator.of(
                        dialogContext,
                      ).pop(_RideChoice.correction),
                  child: const TranslatedText('Suggest a correction'),
                ),
            ],
          ),
    );
    if (choice == null || !context.mounted) return;

    final mode = _rideMode(route, generated);
    Future<List<LatLng>?> snap(List<LatLng> points) =>
        RoutingService.snapThrough(points, mode: mode);

    // Snapping the ride to roads takes a moment.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 16),
                Expanded(child: TranslatedText('Preparing your route...')),
              ],
            ),
          ),
    );
    route_model.Route draft;
    try {
      draft =
          route != null
              ? await RideCorrection.draftFromRoute(
                route: route,
                followedPath: followedPath,
                stepBoundaries: stepBoundaries,
                deviations: deviations,
                snap: snap,
              )
              : await RideCorrection.draftFromGenerated(
                generated: generated!,
                originName: originName,
                destinationName: destinationName,
                deviations: deviations,
                snap: snap,
              );
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;

    final isCorrection = choice == _RideChoice.correction;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (editorContext) => ContributeScreen(
              draftRoute: draft,
              correctionOf: isCorrection ? route?.id : null,
              onRouteSubmitted: (submitted) async {
                await RouteService.saveRoute(submitted);
                if (!editorContext.mounted) return;
                Navigator.of(editorContext).pop();
                ScaffoldMessenger.of(editorContext).showSnackBar(
                  SnackBar(
                    content: TranslatedText(
                      isCorrection
                          ? 'Thanks! Your correction was sent for review.'
                          : 'Thanks! Your route was sent for review.',
                    ),
                  ),
                );
              },
            ),
      ),
    );
  }

  static String _summary(List<RideDeviation> deviations) {
    final total = deviations.fold<double>(0, (sum, d) => sum + d.lengthMeters);
    final first = deviations.first.points;
    final leftNear = nearestCamanavaPlaceName(first.first, maxMeters: 500);
    final distance = RouteMetricsService.formatDistanceMeters(total);
    return 'The vehicle left this route for about $distance'
        '${leftNear != null ? ' near $leftNear' : ''}. If that is the way it '
        'usually goes, you can help fix the route. Nothing is shared unless '
        'you submit it.';
  }

  /// Mode used to snap the ride to roads: the route's first riding step.
  static String _rideMode(route_model.Route? route, OrsRouteResult? generated) {
    final modes = [
      ...?route?.steps.map((s) => s.mode),
      ...?generated?.steps.map((s) => s.suggestedMode),
    ];
    return modes.firstWhere((m) => m != 'Walk', orElse: () => 'Jeepney');
  }
}
