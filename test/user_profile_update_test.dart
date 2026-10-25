import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/models/user.dart';

void main() {
  test('profile saves never write the role or ban fields', () {
    // Saving the whole profile used to write the app's copy of the role
    // back and drop a dashboard superadmin's access.
    final superadmin = User.fromJson({
      'uid': 'u1',
      'name': 'Admin',
      'email': 'a@b.c',
      'role': 'superadmin',
      'isBanned': false,
      'routesSearched': 4,
    });
    expect(superadmin.role, UserRole.superadmin);

    final update = superadmin.toProfileUpdateJson();
    expect(update.keys, isNot(contains('role')));
    expect(update.keys, isNot(contains('isBanned')));
    expect(update.keys, isNot(contains('status')));
    expect(update.keys, isNot(contains('restrictedUntil')));
    expect(update['routesSearched'], 4);
    expect(update['name'], 'Admin');
  });
}
