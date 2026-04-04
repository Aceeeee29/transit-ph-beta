import 'package:flutter/material.dart';
import '../../models/route.dart' as route_model;
import '../../services/route_service.dart';
import '../../services/route_trust_service.dart';

/// A route card used in the search screen results and suggestions.
class SearchRouteCard extends StatelessWidget {
  final route_model.Route route;
  final VoidCallback onTap;
  final bool isVerified;

  static const _surface = Color(0xFFFFFFFF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  const SearchRouteCard({
    super.key,
    required this.route,
    required this.onTap,
    this.isVerified = false,
  });

  @override
  Widget build(BuildContext context) {
    final score = route.views + route.upvotes - route.downvotes;
    final hasTransportSteps = route.steps.any((s) => s.mode != 'Walk');
    final hasActualFare = hasTransportSteps &&
        route.steps.where((s) => s.mode != 'Walk').every((s) => s.actualFare != null);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${route.startLocation} to ${route.endLocation}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                  if (isVerified) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: const BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Verified',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _accentSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _accent.withOpacity(0.2)),
                    ),
                    child: Text(
                      '$score pts',
                      style: const TextStyle(
                        fontSize: 11,
                        color: _accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildRouteIntegrityChip(),
              const SizedBox(height: 8),
              Text(
                route.shortDescription,
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                  color: _textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (route.audienceTags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: route.audienceTags.take(4).map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _accentSoft,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _accent.withOpacity(0.2)),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.visibility, size: 14, color: _textSecondary),
                  const SizedBox(width: 4),
                  Text('${route.views}',
                      style: const TextStyle(fontSize: 12, color: _textSecondary)),
                  const SizedBox(width: 14),
                  const Icon(Icons.thumb_up, size: 14, color: Color(0xFF3EC97A)),
                  const SizedBox(width: 4),
                  Text('${route.upvotes}',
                      style: const TextStyle(fontSize: 12, color: _textSecondary)),
                  const SizedBox(width: 14),
                  const Icon(Icons.thumb_down, size: 14, color: Color(0xFFE05C6A)),
                  const SizedBox(width: 4),
                  Text('${route.downvotes}',
                      style: const TextStyle(fontSize: 12, color: _textSecondary)),
                  if (route.price != null) ...[
                    const SizedBox(width: 14),
                    const Icon(Icons.payments_outlined, size: 14, color: Color(0xFF3EC97A)),
                    const SizedBox(width: 4),
                    Text(route.price!,
                        style: const TextStyle(fontSize: 12, color: _textSecondary)),
                  ],
                  if (hasTransportSteps) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasActualFare
                            ? const Color(0x143EC97A)
                            : const Color(0x14E89A3C),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        hasActualFare ? 'Actual fare' : 'Estimated fare',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: hasActualFare
                              ? const Color(0xFF2D9F63)
                              : const Color(0xFFB8732F),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteIntegrityChip() {
    return StreamBuilder<Map<String, int>>(
      stream: RouteService.watchRouteFeedbackSummary(route.id),
      builder: (context, snapshot) {
        final summary = snapshot.data ?? const {
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
        final trustLabel = RouteTrustService.confidenceLabel(trust.total);

        final trustColor = trust.total >= 85
            ? const Color(0xFF2D9F63)
            : trust.total >= 65
                ? _accent
                : const Color(0xFFB8732F);

        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: trustColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: trustColor.withOpacity(0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 13,
                  color: trustColor,
                ),
                const SizedBox(width: 5),
                Text(
                  'Route integrity ${trust.total}/100 - $trustLabel',
                  style: TextStyle(
                    fontSize: 10,
                    color: trustColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
