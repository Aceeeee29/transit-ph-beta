import 'package:flutter/material.dart';
import '../../models/achievement.dart';
import '../../services/gamification_service.dart';
import 'profile_colors.dart';

Color rarityColor(String rarity) {
  switch (rarity.toLowerCase()) {
    case 'common':
      return ProfileColors.textSecondary;
    case 'rare':
      return ProfileColors.accent;
    case 'epic':
      return const Color(0xFF9B7FE8);
    case 'legendary':
      return const Color(0xFFE89A3C);
    default:
      return ProfileColors.textSecondary;
  }
}

class AchievementsTab extends StatelessWidget {
  final List<String> userAchievements;

  const AchievementsTab({super.key, required this.userAchievements});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Achievement>>(
      future: GamificationService.loadAchievements(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              color: ProfileColors.accent,
              strokeWidth: 2,
            ),
          );
        }
        final achievements = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: achievements.length,
          itemBuilder: (context, index) {
            final achievement = achievements[index];
            final isUnlocked = userAchievements.contains(achievement.id);
            final progress = achievement.progress;
            final color = rarityColor(achievement.rarity);
            return _AchievementCard(
              achievement: achievement,
              isUnlocked: isUnlocked,
              progress: progress,
              rarityColor: color,
            );
          },
        );
      },
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final Achievement achievement;
  final bool isUnlocked;
  final int progress;
  final Color rarityColor;

  const _AchievementCard({
    required this.achievement,
    required this.isUnlocked,
    required this.progress,
    required this.rarityColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ProfileColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnlocked
              ? ProfileColors.green.withOpacity(0.3)
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _iconBox(),
                const SizedBox(width: 12),
                Expanded(child: _nameAndDesc()),
                _lockIcon(),
              ],
            ),
            if (achievement.maxProgress > 1) ...[
              const SizedBox(height: 12),
              _progressBar(),
              const SizedBox(height: 5),
              Text(
                '$progress / ${achievement.maxProgress}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isUnlocked ? ProfileColors.green : ProfileColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _iconBox() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isUnlocked
            ? ProfileColors.green.withOpacity(0.1)
            : ProfileColors.surfaceAlt,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isUnlocked
              ? ProfileColors.green.withOpacity(0.3)
              : ProfileColors.border,
        ),
      ),
      child: Center(
        child: Opacity(
          opacity: isUnlocked ? 1.0 : 0.35,
          child: Text(achievement.icon, style: const TextStyle(fontSize: 24)),
        ),
      ),
    );
  }

  Widget _nameAndDesc() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              achievement.name,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: isUnlocked
                    ? ProfileColors.textPrimary
                    : ProfileColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: rarityColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                achievement.rarity,
                style: TextStyle(
                  fontSize: 10,
                  color: rarityColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          achievement.description,
          style: const TextStyle(color: ProfileColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _lockIcon() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isUnlocked
            ? ProfileColors.green.withOpacity(0.1)
            : ProfileColors.surfaceAlt,
        shape: BoxShape.circle,
      ),
      child: Icon(
        isUnlocked
            ? Icons.check_circle_rounded
            : Icons.lock_outline_rounded,
        color: isUnlocked ? ProfileColors.green : ProfileColors.textSecondary,
        size: 16,
      ),
    );
  }

  Widget _progressBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress / achievement.maxProgress,
        backgroundColor: ProfileColors.surfaceAlt,
        valueColor: AlwaysStoppedAnimation<Color>(
          isUnlocked ? ProfileColors.green : rarityColor,
        ),
        minHeight: 6,
      ),
    );
  }
}
