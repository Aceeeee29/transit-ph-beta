/// The rules a new password must pass, in the order the sign-up checklist
/// shows them.
class PasswordRules {
  PasswordRules._();

  static const minLength = 8;

  /// Each rule's label and test. Matching the Confirm field is checked
  /// separately, since it needs both fields.
  static final List<(String, bool Function(String))> rules = [
    ('At least $minLength characters', (p) => p.length >= minLength),
    ('One uppercase letter', (p) => p.contains(RegExp(r'[A-Z]'))),
    ('One lowercase letter', (p) => p.contains(RegExp(r'[a-z]'))),
    ('One number', (p) => p.contains(RegExp(r'[0-9]'))),
    // Anything that isn't a letter, number or space counts as special.
    ('One special character', (p) => p.contains(RegExp(r'[^A-Za-z0-9\s]'))),
    ('No spaces', (p) => p.isNotEmpty && !p.contains(RegExp(r'\s'))),
  ];

  static bool isValid(String password) =>
      rules.every((rule) => rule.$2(password));
}
