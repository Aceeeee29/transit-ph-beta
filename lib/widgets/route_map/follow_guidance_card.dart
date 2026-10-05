import 'package:flutter/material.dart';

import '../../services/route_follow_guidance.dart';
import '../../services/route_metrics_service.dart';
import '../translated_text.dart';

/// Tells a traveler who isn't on the route they're following how to get to
/// it: walking to the boarding point, rerouting back, or waiting out a
/// vehicle detour.
class FollowGuidanceCard extends StatelessWidget {
  final FollowGuidance guidance;

  /// Walking distance along the drawn path to the target, when known.
  final double? remainingMeters;
  final bool isRerouting;
  final String routeStartLabel;

  const FollowGuidanceCard({
    super.key,
    required this.guidance,
    required this.remainingMeters,
    required this.isRerouting,
    required this.routeStartLabel,
  });

  static const _accent = Color(0xFF2E7CF6);
  static const _warning = Color(0xFFB8732F);
  static const _textPrimary = Color(0xFF0F1D35);

  @override
  Widget build(BuildContext context) {
    if (guidance.kind == FollowGuidanceKind.none) return const SizedBox.shrink();

    final isDetour = guidance.kind == FollowGuidanceKind.vehicleDetour;
    final isRejoin = guidance.kind == FollowGuidanceKind.rejoin;
    final color = isDetour || isRejoin ? _warning : _accent;
    final icon =
        isDetour
            ? Icons.alt_route_rounded
            : isRerouting
            ? Icons.sync_rounded
            : Icons.directions_walk_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TranslatedText(
              _message(),
              style: const TextStyle(
                color: _textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _message() {
    switch (guidance.kind) {
      case FollowGuidanceKind.none:
        return '';
      case FollowGuidanceKind.vehicleDetour:
        return 'Off route. The vehicle may be taking a detour; following '
            'resumes when you are back on the route.';
      case FollowGuidanceKind.rejoin:
        if (isRerouting) return 'Rerouting...';
        final stopName = guidance.stopName;
        if (guidance.atDesignatedStop && stopName != null) {
          return 'Off route. Walk ${_distance()} to $stopName to rejoin '
              'the route.';
        }
        final place = guidance.placeName;
        return 'Off route. Walk ${_distance()} to rejoin the route'
            '${place != null ? ' near $place' : ''}.';
      case FollowGuidanceKind.approach:
        return _approachMessage();
    }
  }

  String _approachMessage() {
    final distance = _distance();
    if (guidance.isRouteStart) {
      return 'Walk $distance to the start of the route at $routeStartLabel.';
    }
    final place = guidance.placeName;
    final mode = guidance.mode;
    if (guidance.atDesignatedStop) {
      final isTrain = mode == 'Train';
      final stop =
          guidance.stopName ??
          (place != null
              ? 'the ${isTrain ? 'station' : 'stop'} near $place'
              : 'the ${isTrain ? 'station' : 'stop'}');
      final line =
          isTrain
              ? 'A train line'
              : mode == null
              ? 'This route'
              : '${_article(mode)} ${_modeLabel(mode)} route';
      return '$line passes near you. Walk $distance to $stop to board.';
    }
    if (mode == null || mode == 'Walk') {
      return 'This route passes near you. Walk $distance to join it'
          '${place != null ? ' near $place' : ''}.';
    }
    final point = place != null ? 'the stop near $place' : 'the boarding point';
    return '${_article(mode)} ${_modeLabel(mode)} route passes near you. '
        'Walk $distance to $point to ride this route.';
  }

  /// Rounded so the text (and its translation) doesn't change every fix.
  String _distance() {
    final meters = remainingMeters ?? guidance.distanceMeters;
    final rounded = meters < 1000 ? (meters / 10).round() * 10.0 : meters;
    return RouteMetricsService.formatDistanceMeters(rounded);
  }

  static String _modeLabel(String mode) =>
      mode == 'FX/Van' ? 'FX/van' : mode.toLowerCase();

  static String _article(String mode) =>
      mode == 'FX/Van' ? 'An' : 'A';
}
