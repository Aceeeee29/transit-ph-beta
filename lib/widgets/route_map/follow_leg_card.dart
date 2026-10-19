import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/route_metrics_service.dart';
import '../../theme/app_colors.dart';
import '../translated_text.dart';
import 'route_modes.dart';

/// One step of a followed route as the top card shows it.
class FollowLegInfo {
  final String mode;

  /// "Ride to Balintawak", "Walk to LRT-1 Monumento", or the step's own
  /// instruction when its end has no name.
  final String headline;

  /// Where the step starts, when known.
  final String? from;

  /// The step's fare after any discount ("₱13"); null on foot.
  final String? fare;

  const FollowLegInfo({
    required this.mode,
    required this.headline,
    this.from,
    this.fare,
  });

  bool get isWalk => mode == 'Walk';
}

/// While following: the step being travelled (what to do, how far and how
/// long to its end, its fare) and, in a strip under it, the step after.
/// Off the route, [guidance] (how to get back) takes the card's place.
class FollowLegCard extends StatelessWidget {
  final FollowLegInfo leg;
  final double metersLeft;

  /// "Walk to LRT-1 Balintawak", or "Arrive at STI College" on the last.
  final String next;

  /// Near the end of a ride: the strip turns amber.
  final bool getOffSoon;
  final String? getOffName;

  /// The off-route card, shown instead of the leg while set.
  final Widget? guidance;

  const FollowLegCard({
    super.key,
    required this.leg,
    required this.metersLeft,
    required this.next,
    this.getOffSoon = false,
    this.getOffName,
    this.guidance,
  });

  static const _amber = Color(0xFFB8732F);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [guidance ?? _legCard(), _nextStrip()],
    );
  }

  Widget _legCard() {
    final color = RouteModes.color(leg.mode);
    final minutes = math.max(
      1,
      (metersLeft / 1000 / RouteMetricsService.speedKmhForMode(leg.mode) * 60)
          .ceil(),
    );
    final meta = [
      _distance(metersLeft),
      '$minutes min',
      if (leg.fare != null) leg.fare!,
    ].join(' · ');
    final sub =
        leg.isWalk
            ? (leg.from != null ? 'From ${leg.from}' : null)
            : leg.from != null
            ? '${leg.mode} from ${leg.from}'
            : leg.mode;

    return Material(
      color: AppColors.surface,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: color),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(RouteModes.icon(leg.mode), color: color, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TranslatedText(
                      leg.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      TranslatedText(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nextStrip() {
    final warn = getOffSoon;
    final text =
        warn
            ? 'Get off soon · ${getOffName ?? 'your stop'} in '
                '${_distance(metersLeft)}'
            : 'Next: $next';
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 6),
      child: Material(
        color: warn ? _amber : AppColors.surface,
        elevation: 3,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                warn
                    ? Icons.notifications_active_rounded
                    : Icons.subdirectory_arrow_right_rounded,
                size: 16,
                color: warn ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: TranslatedText(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: warn ? Colors.white : AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Rounded to 10 m (100 m past a kilometre) so the text doesn't change
  /// on every fix.
  static String _distance(double meters) {
    final step = meters < 1000 ? 10.0 : 100.0;
    return RouteMetricsService.formatDistanceMeters(
      (meters / step).round() * step,
    );
  }
}
