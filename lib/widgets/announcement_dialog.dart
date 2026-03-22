import 'package:flutter/material.dart';

import '../models/announcement.dart';
import '../services/announcement_service.dart';

class AnnouncementDialog {
  AnnouncementDialog._();

  static Future<void> checkAndShow(BuildContext context) async {
    final announcement = await AnnouncementService.getLatestVisibleAnnouncementForCurrentUser();
    if (announcement == null) return;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AnnouncementAlertDialog(announcement: announcement),
    );
  }
}

class _AnnouncementAlertDialog extends StatelessWidget {
  const _AnnouncementAlertDialog({required this.announcement});

  final Announcement announcement;

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(announcement.type);
    final icon = _iconFor(announcement.type);

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

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              announcement.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F1D35),
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Text(
          announcement.message,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF30435F),
            height: 1.45,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: dismissPermanentlyAndClose,
          child: const Text('Dismiss'),
        ),
        ElevatedButton.icon(
          onPressed: closeForNow,
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Got it'),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(95, 30),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  static Color _accentFor(AnnouncementType type) {
    switch (type) {
      case AnnouncementType.critical:
        return const Color(0xFFE05C6A);
      case AnnouncementType.warning:
        return const Color(0xFFFFB547);
      case AnnouncementType.info:
        return const Color(0xFF2E7CF6);
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
}
