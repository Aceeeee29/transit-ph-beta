import 'package:flutter/material.dart';
import '../../models/route.dart' as route_model;

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
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: _accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 13,
                        color: Colors.white,
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
