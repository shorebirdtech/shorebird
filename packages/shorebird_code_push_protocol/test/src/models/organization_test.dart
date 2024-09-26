import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(Organization, () {
    test('can be (de)serialized', () {
      final organization = Organization(
        id: 1,
        name: 'name',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        organizationType: OrganizationType.team,
        stripeCustomerId: 'cus_123',
      );
      expect(
        Organization.fromJson(organization.toJson()).toJson(),
        equals(organization.toJson()),
      );
    });
  });
}
