/// The rules a new password must pass, in the order the sign-up checklist
/// shows them.
///
/// These copy the password policy set in Firebase Authentication. If the app
/// let through a password Firebase refuses, the rider would only see a
/// vague error after tapping Sign up. If the Firebase policy changes, change
/// these too.
class PasswordRules {
  PasswordRules._();

  static const minLength = 8;
  static const maxLength = 16;

  /// The only symbols Firebase counts as "special". Others, like + or =,
  /// don't count, so a password whose only symbol is + is refused.
  static const symbols = r'''^$*.[]{}()?"!@#%&/\,><':;|_~`-''';

  /// Each rule's label and test. Matching the Confirm field is checked
  /// separately, since it needs both fields.
  static final List<(String, bool Function(String))> rules = [
    (
      '$minLength to $maxLength characters',
      (p) => p.length >= minLength && p.length <= maxLength,
    ),
    ('One uppercase letter', (p) => p.contains(RegExp(r'[A-Z]'))),
    ('One lowercase letter', (p) => p.contains(RegExp(r'[a-z]'))),
    ('One number', (p) => p.contains(RegExp(r'[0-9]'))),
    (
      'One symbol, like ! @ # \$ _ - (+ and = don\'t count)',
      (p) => p.split('').any(symbols.contains),
    ),
    ('No spaces', (p) => p.isNotEmpty && !p.contains(RegExp(r'\s'))),
  ];

  static bool isValid(String password) =>
      rules.every((rule) => rule.$2(password));
}
