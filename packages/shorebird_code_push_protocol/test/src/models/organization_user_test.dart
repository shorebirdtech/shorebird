import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(OrganizationUser, () {
    test('can be (de)serialized', () {
      final organizationUser = OrganizationUser(
        user: User.fromFullUser(FullUser.forTest()),
        role: OrganizationRole.member,
      );
      expect(
        OrganizationUser.fromJson(organizationUser.toJson()).toJson(),
        equals(organizationUser.toJson()),
      );
    });
  });
}
