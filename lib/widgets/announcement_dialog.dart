import 'package:flutter/material.dart';

import '../models/announcement.dart';
import '../services/announcement_service.dart';
import '../theme/app_colors.dart';

class AnnouncementDialog {
  AnnouncementDialog._();

  static Future<void> checkAndShow(BuildContext context) async {
    final announcement =
        await AnnouncementService.getLatestVisibleAnnouncementForCurrentUser();
    if (announcement == null) return;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AnnouncementAlertDialog(announcement: announcement),
    );
  }
}

/// The latest announcement: its type's icon, the title, when it was sent,
/// the message, then "Got it" (closes it for now) and "Don't show again".
class _AnnouncementAlertDialog extends StatelessWidget {
  const _AnnouncementAlertDialog({required this.announcement});

  final Announcement announcement;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(announcement.type);
    final sent = announcement.scheduledAt ?? announcement.createdAt;
    final subtitle = [
      _labelFor(announcement.type),
      if (sent != null) '${_months[sent.month - 1]} ${sent.day}',
    ].join(' · ');

    Future<void> dismissPermanentlyAndClose() async {
      await AnnouncementService.dismissForCurrentUser(announcement.id);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    void closeForNow() {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconFor(announcement.type),
                    color: accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        announcement.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  announcement.message,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: AppColors.textPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: closeForNow,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Got it'),
            ),
            TextButton(
              onPressed: dismissPermanentlyAndClose,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: const Text("Don't show again"),
            ),
          ],
        ),
      ),
    );
  }

  static Color _accentFor(AnnouncementType type) {
    switch (type) {
      case AnnouncementType.critical:
        return const Color(0xFFE05C6A);
      case AnnouncementType.warning:
        return const Color(0xFFF2A33A);
      case AnnouncementType.info:
        return AppColors.accent;
    }
  }

  static IconData _iconFor(AnnouncementType type) {
    switch (type) {
      case AnnouncementType.critical:
        return Icons.warning_amber_rounded;
      case AnnouncementType.warning:
        return Icons.info_outline_rounded;
      case AnnouncementType.info:
        return Icons.campaign_rounded;
    }
  }

  static String _labelFor(AnnouncementType type) {
    switch (type) {
      case AnnouncementType.critical:
        return 'Important';
      case AnnouncementType.warning:
        return 'Heads up';
      case AnnouncementType.info:
        return 'Announcement';
    }
  }
}
