import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/models/lockout.dart';
import 'package:transitph_beta/services/lockout_service.dart';

void main() {
  final until = DateTime.utc(2026, 11, 10, 8);

  LockoutRecord record(String action, {DateTime? recordUntil}) {
    return LockoutRecord.fromMap({
      'action': action,
      'reasonCode': 'spam',
      'reasonLabel': 'Spam',
      'termsSection': 'Terms, section 6: Things You Must Not Do',
      'note': '  posted the same ad 40 times  ',
      'lockoutId': 'abc123',
      'until': recordUntil == null ? null : Timestamp.fromDate(recordUntil),
    })!;
  }

  group('LockoutReason', () {
    test('only "Other" needs a note', () {
      expect(LockoutReason.byCode('other').needsNote, isTrue);
      expect(LockoutReason.byCode('spam').needsNote, isFalse);
    });

    test('an unknown code falls back to Other', () {
      expect(LockoutReason.byCode('nope').code, 'other');
    });

    test('every reason but Other names a Terms section', () {
      for (final r in LockoutReason.all.where((r) => r.code != 'other')) {
        expect(r.termsSection, isNotEmpty, reason: r.code);
      }
    });
  });

  group('LockoutRecord', () {
    test('reads a saved record and trims the note', () {
      final r = record('restrict', recordUntil: until);
      expect(r.isBan, isFalse);
      expect(r.reasonLabel, 'Spam');
      expect(r.note, 'posted the same ad 40 times');
      expect(r.until!.isAtSameMomentAs(until), isTrue);
    });

    test('a record without a lockout id is ignored', () {
      expect(LockoutRecord.fromMap({'action': 'ban'}), isNull);
      expect(LockoutRecord.fromMap(null), isNull);
    });

    test('old lockouts with no record still get a steady appeal key', () {
      final at = Timestamp.fromDate(DateTime.utc(2026, 11, 1));
      expect(
        LockoutRecord.legacyLockoutId({'restrictedAt': at}),
        'r${at.millisecondsSinceEpoch}',
      );
      expect(LockoutRecord.legacyLockoutId({'isBanned': true}), 'ban-legacy');
      expect(LockoutRecord.legacyLockoutId({'status': 'banned'}), 'ban-legacy');
    });

    test('appeal ids tie the rider to one lockout', () {
      expect(Appeal.idFor('uid1', 'abc123'), 'uid1_abc123');
    });
  });

  group('LockoutService.recordMatches', () {
    test('a ban record explains a ban', () {
      expect(
        LockoutService.recordMatches(record('ban'), {'isBanned': true}),
        isTrue,
      );
    });

    test('an old restriction record does not explain a later ban', () {
      expect(
        LockoutService.recordMatches(
          record('restrict', recordUntil: until),
          {'status': 'banned'},
        ),
        isFalse,
      );
    });

    test('a restriction record matches its own end time', () {
      final data = {
        'status': 'restricted',
        'restrictedUntil': Timestamp.fromDate(
          until.add(const Duration(seconds: 2)),
        ),
      };
      expect(
        LockoutService.recordMatches(
          record('restrict', recordUntil: until),
          data,
        ),
        isTrue,
      );
    });

    test('a restriction record from an earlier restriction is ignored', () {
      final data = {
        'status': 'restricted',
        'restrictedUntil': Timestamp.fromDate(
          until.add(const Duration(days: 3)),
        ),
      };
      expect(
        LockoutService.recordMatches(
          record('restrict', recordUntil: until),
          data,
        ),
        isFalse,
      );
    });
  });
}
