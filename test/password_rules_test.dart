import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/utils/password_rules.dart';

void main() {
  group('PasswordRules', () {
    test('accepts a password meeting every rule', () {
      expect(PasswordRules.isValid('Transit#2026'), isTrue);
      expect(PasswordRules.isValid('aB3_efgh'), isTrue);
      expect(PasswordRules.isValid('Abcdefghijklm1!x'), isTrue, reason: '16');
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

    // Firebase refuses these, so the app must too.
    test('rejects passwords over 16 characters', () {
      expect(PasswordRules.isValid('Abcdefghijklmn1!x'), isFalse);
    });

    test('does not count + or = as the symbol', () {
      expect(PasswordRules.isValid('Transit+2026'), isFalse);
      expect(PasswordRules.isValid('Transit=2026'), isFalse);
      // Allowed alongside a symbol Firebase counts.
      expect(PasswordRules.isValid('Transit+2026!'), isTrue);
    });

    test('counts every symbol on the Firebase list', () {
      for (final symbol in PasswordRules.symbols.split('')) {
        expect(
          PasswordRules.isValid('Transit${symbol}26'),
          isTrue,
          reason: symbol,
        );
      }
      expect(PasswordRules.symbols.length, 30);
    });
  });
}
