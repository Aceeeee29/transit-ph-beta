import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/lockout.dart';
import 'moderation_service.dart';

/// What the locked-out popup needs: the reason (when staff gave one), the
/// key for this lockout's appeal, and the appeal if one was sent.
class LockoutDetails {
  final bool isBan;
  final LockoutRecord? record;
  final String lockoutId;
  final Appeal? appeal;

  const LockoutDetails({
    required this.isBan,
    required this.record,
    required this.lockoutId,
    required this.appeal,
  });

  LockoutDetails withAppeal(Appeal appeal) => LockoutDetails(
    isBan: isBan,
    record: record,
    lockoutId: lockoutId,
    appeal: appeal,
  );
}

/// Ban and restriction reasons, and riders' appeals against them.
class LockoutService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _appeals =>
      _db.collection('appeals');

  /// Longest appeal a rider can write.
  static const maxAppealLength = 1000;

  static DocumentReference<Map<String, dynamic>> recordRef(String uid) =>
      _db.collection('users').doc(uid).collection('moderation').doc('current');

  static bool _isBanned(Map<String, dynamic> userData) =>
      userData['isBanned'] == true ||
      ((userData['status'] as String?) ?? '').trim().toLowerCase() == 'banned';

  /// The record belongs to the lockout the rider has now. An old record
  /// (say, from a restriction that was lifted, then a ban made from an
  /// older dashboard with no reason) must not explain a different one.
  @visibleForTesting
  static bool recordMatches(
    LockoutRecord record,
    Map<String, dynamic> userData,
  ) {
    if (_isBanned(userData)) return record.isBan;
    if (record.isBan) return false;
    final until = userData['restrictedUntil'];
    final recordUntil = record.until;
    if (until is! Timestamp || recordUntil == null) return false;
    // The two are written together, but allow a little clock slack.
    return until.toDate().difference(recordUntil).inMinutes.abs() <= 5;
  }

  /// Loads the reason and appeal for the signed-in rider's lockout. Parts
  /// that can't be loaded (offline, old rules) are left empty, and the
  /// popup still shows without them.
  static Future<LockoutDetails> loadDetails(
    String uid,
    Map<String, dynamic> userData,
  ) async {
    LockoutRecord? record;
    try {
      final snap = await recordRef(uid).get();
      final parsed = LockoutRecord.fromMap(snap.data());
      if (parsed != null && recordMatches(parsed, userData)) record = parsed;
    } catch (e) {
      debugPrint('[Lockout] reason load failed: $e');
    }

    final lockoutId =
        record?.lockoutId ?? LockoutRecord.legacyLockoutId(userData);
    Appeal? appeal;
    try {
      final snap = await _appeals.doc(Appeal.idFor(uid, lockoutId)).get();
      if (snap.exists) appeal = Appeal.fromDoc(snap);
    } catch (e) {
      debugPrint('[Lockout] appeal load failed: $e');
    }

    return LockoutDetails(
      isBan: _isBanned(userData),
      record: record,
      lockoutId: lockoutId,
      appeal: appeal,
    );
  }

  /// Sends the rider's appeal. The appeal's id is tied to the lockout, so
  /// a second one for the same lockout is refused by the server.
  static Future<Appeal> sendAppeal({
    required Map<String, dynamic> userData,
    required LockoutDetails details,
    required String message,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    final ref = _appeals.doc(Appeal.idFor(user.uid, details.lockoutId));
    final name =
        ((userData['name'] as String?) ?? user.displayName ?? '').trim();
    final email = ((userData['email'] as String?) ?? user.email ?? '').trim();
    await ref.set({
      'userId': user.uid,
      'userName': name,
      'userEmail': email,
      'lockoutId': details.lockoutId,
      'action': details.isBan ? 'ban' : 'restrict',
      'reasonLabel': details.record?.reasonLabel ?? '',
      'note': details.record?.note ?? '',
      'message': message.trim(),
      'status': AppealStatus.pending.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return Appeal(
      id: ref.id,
      userId: user.uid,
      userName: name,
      userEmail: email,
      action: details.isBan ? 'ban' : 'restrict',
      reasonLabel: details.record?.reasonLabel ?? '',
      note: details.record?.note ?? '',
      message: message.trim(),
      status: AppealStatus.pending,
      reply: '',
      createdAt: DateTime.now(),
    );
  }

  // Staff

  /// Every appeal, waiting ones first, then newest first.
  static Stream<List<Appeal>> watchAppeals() {
    return _appeals.snapshots().map((snap) {
      final list = snap.docs.map(Appeal.fromDoc).toList();
      list.sort((a, b) {
        final aWaiting = a.status == AppealStatus.pending ? 0 : 1;
        final bWaiting = b.status == AppealStatus.pending ? 0 : 1;
        if (aWaiting != bWaiting) return aWaiting - bWaiting;
        final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });
      return list;
    });
  }

  /// Lifts the lockout, or keeps it ("uphold"). Either way the rider sees
  /// the outcome and [reply] the next time they open the app. Returns
  /// false when it couldn't be saved.
  static Future<bool> decide(
    Appeal appeal, {
    required bool lift,
    String reply = '',
  }) async {
    if (lift && !await ModerationService.liftUserRestriction(appeal.userId)) {
      return false;
    }
    try {
      await _appeals.doc(appeal.id).update({
        'status': (lift ? AppealStatus.lifted : AppealStatus.upheld).name,
        'reply': reply.trim(),
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('[Lockout] appeal decision failed: $e');
      // Lifted already counts: the rider is back in.
      return lift;
    }
  }

  /// Marks the rider's waiting appeals as lifted, after staff lifted the
  /// lockout some other way (the Users list).
  static Future<void> closePendingAppeals(String uid) async {
    try {
      final waiting =
          await _appeals
              .where('userId', isEqualTo: uid)
              .where('status', isEqualTo: AppealStatus.pending.name)
              .get();
      for (final doc in waiting.docs) {
        await doc.reference.update({
          'status': AppealStatus.lifted.name,
          'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
          'reviewedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('[Lockout] closing appeals failed: $e');
    }
  }
}
