import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/utils/password_rules.dart';

void main() {
  group('PasswordRules', () {
    test('accepts a password meeting every rule', () {
      expect(PasswordRules.isValid('Transit#2026'), isTrue);
      expect(PasswordRules.isValid('aB3_efgh'), isTrue);
    });

    test('rejects each missing rule', () {
      expect(PasswordRules.isValid('aB3#efg'), isFalse, reason: 'too short');
      expect(PasswordRules.isValid('transit#2026'), isFalse, reason: 'upper');
      expect(PasswordRules.isValid('TRANSIT#2026'), isFalse, reason: 'lower');
      expect(PasswordRules.isValid('Transit#now'), isFalse, reason: 'number');
      expect(PasswordRules.isValid('Transit2026'), isFalse, reason: 'special');
      expect(PasswordRules.isValid('Transit# 2026'), isFalse, reason: 'space');
      expect(PasswordRules.isValid(''), isFalse);
    });
  });
}
