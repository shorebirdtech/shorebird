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
      );
      expect(
        Organization.fromJson(organization.toJson()).toJson(),
        equals(organization.toJson()),
      );
    });

    group('Equatable', () {
      final date = DateTime.now();

      group('when two instances are equal', () {
        test('returns true', () {
          final organization = Organization(
            id: 1,
            name: 'name',
            createdAt: date,
            updatedAt: date,
            organizationType: OrganizationType.team,
          );
          final otherOrganization = Organization(
            id: 1,
            name: 'name',
            createdAt: date,
            updatedAt: date,
            organizationType: OrganizationType.team,
          );
          expect(organization, equals(otherOrganization));
        });
      });

      group('when two instances are not equal', () {
        test('returns false', () {
          final organization = Organization(
            id: 1,
            name: 'name',
            createdAt: date,
            updatedAt: date,
            organizationType: OrganizationType.team,
          );
          final otherOrganization = Organization(
            id: 1,
            name: 'name 2',
            createdAt: date,
            updatedAt: date,
            organizationType: OrganizationType.team,
          );
          expect(organization, isNot(equals(otherOrganization)));
        });
      });
    });
  });
}
