import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(OrganizationMembership, () {
    test('can be (de)serialized', () {
      final membership = OrganizationMembership(
        organization: Organization.forTest(),
        role: OrganizationRole.member,
      );
      expect(
        OrganizationMembership.fromJson(membership.toJson()).toJson(),
        equals(membership.toJson()),
      );
    });
  });
}
