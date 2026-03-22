import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/announcement.dart';

class AnnouncementService {
  AnnouncementService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static String _dismissedKey(String uid) => 'dismissed_announcements_$uid';

  static Future<Announcement?> getLatestVisibleAnnouncementForCurrentUser() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return null;

    try {
      final audience = await _loadCurrentUserAudience(currentUser.uid);
      final dismissedIds = await _loadDismissedAnnouncementIds(currentUser.uid);

      // Avoid composite-index dependency by fetching recent docs, then filtering client-side.
      final snapshot = await _firestore.collection('announcements').limit(50).get();
      final allAnnouncements = snapshot.docs.map(Announcement.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));

      final now = DateTime.now();
      for (final announcement in allAnnouncements) {
        if (!announcement.isActive) continue;
        if (dismissedIds.contains(announcement.id)) continue;
        if (!_isAudienceMatch(announcement.targetAudience, audience)) continue;
        if (announcement.scheduledAt != null && announcement.scheduledAt!.isAfter(now)) continue;
        if (announcement.expiresAt != null && announcement.expiresAt!.isBefore(now)) continue;
        if (announcement.title.isEmpty || announcement.message.isEmpty) continue;
        return announcement;
      }

      return null;
    } catch (e, st) {
      debugPrint('[AnnouncementService] Failed to fetch announcements: $e');
      debugPrint('$st');
      return null;
    }
  }

  static Future<void> dismissForCurrentUser(String announcementId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || announcementId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _dismissedKey(currentUser.uid);
    final dismissed = prefs.getStringList(key) ?? <String>[];

    if (!dismissed.contains(announcementId)) {
      dismissed.add(announcementId);
      await prefs.setStringList(key, dismissed);
    }
  }

  static Future<String> _loadCurrentUserAudience(String uid) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final data = userDoc.data();
    final category = (data?['userCategory'] as String?)?.toLowerCase().trim() ?? '';

    if (category.isEmpty) return 'all';

    switch (category) {
      case 'student':
      case 'employee':
      case 'foreigner':
      case 'new to area':
      case 'new_to_area':
        return category.replaceAll(' ', '_');
      default:
        return 'all';
    }
  }

  static Future<Set<String>> _loadDismissedAnnouncementIds(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getStringList(_dismissedKey(uid)) ?? <String>[];
    return dismissed.toSet();
  }

  static bool _isAudienceMatch(String targetAudience, String userAudience) {
    if (targetAudience == 'all') return true;
    return targetAudience == userAudience;
  }
}
