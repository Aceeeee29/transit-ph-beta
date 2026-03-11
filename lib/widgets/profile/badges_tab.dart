import 'package:flutter/material.dart';
import '../../models/badge.dart' as badge_model;
import '../../services/gamification_service.dart';
import 'profile_colors.dart';

class BadgesTab extends StatelessWidget {
  const BadgesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<badge_model.Badge>>(
      future: GamificationService.loadBadges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              color: ProfileColors.accent,
              strokeWidth: 2,
            ),
          );
        }
        final badges = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: badges.length,
          itemBuilder: (context, index) => _BadgeCard(badge: badges[index]),
        );
      },
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final badge_model.Badge badge;

  const _BadgeCard({required this.badge});

  @override
  Widget build(BuildContext context) {
    final isUnlocked = badge.isUnlocked;
    final earnedDate = badge.earnedAt?.toDate();
    final formattedDate = earnedDate != null
        ? '${earnedDate.month}/${earnedDate.day}/${earnedDate.year}'
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: ProfileColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnlocked
              ? ProfileColors.accent.withOpacity(0.3)
              : ProfileColors.border,
          width: isUnlocked ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: ProfileColors.accent.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _iconBox(isUnlocked),
            const SizedBox(width: 12),
            Expanded(child: _details(isUnlocked, formattedDate)),
            _statusIcon(isUnlocked),
          ],
        ),
      ),
    );
  }

  Widget _iconBox(bool isUnlocked) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: isUnlocked ? ProfileColors.accentSoft : ProfileColors.surfaceAlt,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isUnlocked
              ? ProfileColors.accent.withOpacity(0.25)
              : ProfileColors.border,
        ),
      ),
      child: Center(
        child: Text(badge.icon, style: const TextStyle(fontSize: 24)),
      ),
    );
  }

  Widget _details(bool isUnlocked, String? formattedDate) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          badge.name,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: isUnlocked
                ? ProfileColors.textPrimary
                : ProfileColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          badge.description,
          style: const TextStyle(
            color: ProfileColors.textSecondary,
            fontSize: 12,
          ),
        ),
        if (isUnlocked && formattedDate != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 11,
                color: ProfileColors.accent,
              ),
              const SizedBox(width: 3),
              Text(
                'Earned $formattedDate',
                style: const TextStyle(
                  fontSize: 11,
                  color: ProfileColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _statusIcon(bool isUnlocked) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isUnlocked ? ProfileColors.accentSoft : ProfileColors.surfaceAlt,
        shape: BoxShape.circle,
      ),
      child: Icon(
        isUnlocked ? Icons.verified_rounded : Icons.lock_outline_rounded,
        color: isUnlocked ? ProfileColors.accent : ProfileColors.textSecondary,
        size: 15,
      ),
    );
  }
}
