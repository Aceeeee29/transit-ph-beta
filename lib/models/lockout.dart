import 'package:cloud_firestore/cloud_firestore.dart';

/// A reason staff can pick when banning or restricting a rider. Each one
/// points at the part of the Terms the rider broke, so the rider sees the
/// rule and not just a label. Keep in step with the dashboard's
/// `lockoutReasons.ts`.
class LockoutReason {
  final String code;
  final String label;

  /// Where it sits in the Terms, shown to the rider. Empty for "Other".
  final String termsSection;

  const LockoutReason(this.code, this.label, this.termsSection);

  static const _mustNotDo = 'Terms, section 6: Things You Must Not Do';

  static const all = <LockoutReason>[
    LockoutReason('spam', 'Spam', _mustNotDo),
    LockoutReason('harassment', 'Harassment or bullying', _mustNotDo),
    LockoutReason('hate', 'Hateful or abusive content', _mustNotDo),
    LockoutReason('sexual', 'Sexual or explicit content', _mustNotDo),
    LockoutReason(
      'fake',
      'Fake routes, false reports or vote manipulation',
      _mustNotDo,
    ),
    LockoutReason('misleading', 'Misleading information', _mustNotDo),
    LockoutReason(
      'not_theirs',
      'Sharing someone else\'s content without permission',
      _mustNotDo,
    ),
    LockoutReason(
      'security',
      'Trying to break into accounts or disrupt the app',
      _mustNotDo,
    ),
    LockoutReason('other', 'Other', ''),
  ];

  static LockoutReason byCode(String code) =>
      all.firstWhere((r) => r.code == code, orElse: () => all.last);

  /// "Other" means nothing on its own, so staff must explain it.
  bool get needsNote => code == 'other';
}

/// Why and how a rider is locked out: users/{uid}/moderation/current.
/// Kept off the profile itself because any signed-in account can read
/// profiles. Only the rider and staff can read this one.
class LockoutRecord {
  /// 'ban' or 'restrict'.
  final String action;
  final String reasonCode;
  final String reasonLabel;
  final String termsSection;
  final String note;

  /// Changes with every new ban or restriction, so each one gets its own
  /// appeal.
  final String lockoutId;
  final DateTime? until;

  const LockoutRecord({
    required this.action,
    required this.reasonCode,
    required this.reasonLabel,
    required this.termsSection,
    required this.note,
    required this.lockoutId,
    this.until,
  });

  bool get isBan => action == 'ban';

  static LockoutRecord? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final lockoutId = (data['lockoutId'] as String?)?.trim() ?? '';
    if (lockoutId.isEmpty) return null;
    final until = data['until'];
    return LockoutRecord(
      action: data['action'] == 'ban' ? 'ban' : 'restrict',
      reasonCode: (data['reasonCode'] as String?) ?? 'other',
      reasonLabel: (data['reasonLabel'] as String?) ?? '',
      termsSection: (data['termsSection'] as String?) ?? '',
      note: (data['note'] as String?)?.trim() ?? '',
      lockoutId: lockoutId,
      until: until is Timestamp ? until.toDate() : null,
    );
  }

  /// A new record, written next to the ban or restriction itself.
  static Map<String, dynamic> newRecord({
    required String action,
    required LockoutReason reason,
    required String note,
    required String byUid,
    DateTime? until,
  }) {
    return {
      'action': action,
      'reasonCode': reason.code,
      'reasonLabel': reason.label,
      'termsSection': reason.termsSection,
      'note': note.trim(),
      'by': byUid,
      'via': 'app',
      'at': FieldValue.serverTimestamp(),
      'until': until == null ? null : Timestamp.fromDate(until.toUtc()),
      'lockoutId': DateTime.now().microsecondsSinceEpoch.toRadixString(36),
    };
  }

  /// The appeal key for a lockout with no record (made before reasons
  /// existed). It stays the same across launches, so the one-appeal limit
  /// still holds.
  static String legacyLockoutId(Map<String, dynamic> userData) {
    final at = userData['restrictedAt'];
    if (at is Timestamp) return 'r${at.millisecondsSinceEpoch}';
    final banned =
        userData['isBanned'] == true || userData['status'] == 'banned';
    return banned ? 'ban-legacy' : 'restrict-legacy';
  }
}

enum AppealStatus { pending, lifted, upheld }

/// A rider asking staff to undo a ban or restriction:
/// appeals/{uid}_{lockoutId}. The id makes it one appeal per lockout.
class Appeal {
  final String id;
  final String userId;
  final String userName;
  final String userEmail;
  final String action;
  final String reasonLabel;
  final String note;
  final String message;
  final AppealStatus status;
  final String reply;
  final DateTime? createdAt;

  const Appeal({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.action,
    required this.reasonLabel,
    required this.note,
    required this.message,
    required this.status,
    required this.reply,
    this.createdAt,
  });

  bool get isBan => action == 'ban';

  static String idFor(String uid, String lockoutId) => '${uid}_$lockoutId';

  factory Appeal.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final created = data['createdAt'];
    return Appeal(
      id: doc.id,
      userId: (data['userId'] as String?) ?? '',
      userName: (data['userName'] as String?) ?? '',
      userEmail: (data['userEmail'] as String?) ?? '',
      action: data['action'] == 'ban' ? 'ban' : 'restrict',
      reasonLabel: (data['reasonLabel'] as String?) ?? '',
      note: (data['note'] as String?) ?? '',
      message: (data['message'] as String?) ?? '',
      status: AppealStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => AppealStatus.pending,
      ),
      reply: (data['reply'] as String?)?.trim() ?? '',
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}
