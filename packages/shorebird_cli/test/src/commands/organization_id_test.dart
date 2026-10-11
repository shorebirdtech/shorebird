import 'package:shorebird_cli/src/commands/organization_id.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';
import '../helpers.dart';

void main() {
  useTempWorkingDirectory();
  OrganizationMembership membership(int id, String name) =>
      OrganizationMembership(
        organization: Organization(
          id: id,
          name: name,
          organizationType: OrganizationType.team,
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
        role: Role.admin,
      );

  group('parseOrganizationId', () {
    test('parses an integer', () {
      final result = parseOrganizationId('42');
      expect(result.id, equals(42));
      expect(result.error, isNull);
    });

    test('explains a non-integer', () {
      final result = parseOrganizationId('acme');
      expect(result.id, isNull);
      expect(
        result.error?.message,
        equals('"acme" is not a valid organization id.'),
      );
      expect(
        result.error?.hint,
        equals('Organization ids are integers, e.g. --org-id 42.'),
      );
    });
  });

  group('findOrganizationMembership', () {
    final memberships = [membership(1, 'Acme'), membership(2, 'Beta')];

    test('finds the membership', () {
      final result = findOrganizationMembership(
        id: 2,
        memberships: memberships,
      );
      expect(result.membership, equals(memberships[1]));
      expect(result.error, isNull);
    });

    test('lists the available organizations when not a member', () {
      final result = findOrganizationMembership(
        id: 3,
        memberships: memberships,
      );
      expect(result.membership, isNull);
      expect(
        result.error?.message,
        equals('You are not a member of organization 3.'),
      );
      expect(
        result.error?.hint,
        equals('Your organizations: Acme (id: 1), Beta (id: 2).'),
      );
    });

    test('says so when there are no organizations', () {
      final result = findOrganizationMembership(id: 3, memberships: const []);
      expect(
        result.error?.hint,
        equals('You are not a member of any organization.'),
      );
    });
  });
}
