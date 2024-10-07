import 'package:shorebird_cli/src/extensions/organization.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('OrganizationDisplay', () {
    group('displayName', () {
      test('should return the name for a team organization', () {
        final organization = Organization.forTest(
          organizationType: OrganizationType.team,
          name: 'My Organization',
        );
        expect(organization.displayName, 'My Organization');
      });

      test('should return "Personal" for a personal organization', () {
        final organization = Organization.forTest();
        expect(organization.displayName, 'Personal');
      });
    });
  });
}
