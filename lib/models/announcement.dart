import 'package:cloud_firestore/cloud_firestore.dart';

enum AnnouncementType { info, warning, critical }

class Announcement {
  final String id;
  final String title;
  final String message;
  final AnnouncementType type;
  final String targetAudience;
  final bool isActive;
  final DateTime? scheduledAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  const Announcement({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.targetAudience,
    required this.isActive,
    required this.scheduledAt,
    required this.expiresAt,
    required this.createdAt,
  });

  factory Announcement.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Announcement(
      id: doc.id,
      title: (data['title'] as String?)?.trim() ?? '',
      message: (data['message'] as String?)?.trim() ?? '',
      type: _parseType(data['type'] as String?),
      targetAudience: _normalizeAudience(data['targetAudience'] as String?),
      isActive: data['isActive'] == true,
      scheduledAt: _toDateTime(data['scheduledAt']),
      expiresAt: _toDateTime(data['expiresAt']),
      createdAt: _toDateTime(data['createdAt']),
    );
  }

  static AnnouncementType _parseType(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'critical':
        return AnnouncementType.critical;
      case 'warning':
        return AnnouncementType.warning;
      default:
        return AnnouncementType.info;
    }
  }

  static String _normalizeAudience(String? raw) {
    final normalized = (raw ?? 'all').toLowerCase().trim().replaceAll(' ', '_');
    if (normalized.isEmpty) return 'all';
    return normalized;
  }

  static DateTime? _toDateTime(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
