import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(OrganizationMembership, () {
    test('can be (de)serialized', () {
      final membership = OrganizationMembership(
        organization: organizationForTest(),
        role: Role.developer,
      );
      expect(
        OrganizationMembership.fromJson(membership.toJson()).toJson(),
        equals(membership.toJson()),
      );
    });

    group('Equatable', () {
      final date = DateTime.now();

      group('when two instances are equal', () {
        test('returns true', () {
          final membership = OrganizationMembership(
            organization: organizationForTest(
              createdAt: date,
              updatedAt: date,
            ),
            role: Role.developer,
          );
          final otherMembership = OrganizationMembership(
            organization: organizationForTest(
              createdAt: date,
              updatedAt: date,
            ),
            role: Role.developer,
          );
          expect(membership, equals(otherMembership));
        });
      });

      group('when two instances are not equal', () {
        test('returns false', () {
          final membership = OrganizationMembership(
            organization: organizationForTest(
              createdAt: date,
              updatedAt: date,
            ),
            role: Role.developer,
          );
          final otherMembership = OrganizationMembership(
            organization: organizationForTest(
              createdAt: date,
              updatedAt: date,
            ),
            role: Role.admin,
          );
          expect(membership, isNot(equals(otherMembership)));
        });
      });
    });
  });
}
